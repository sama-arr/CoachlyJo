require('dotenv').config();
require('express-async-errors'); // makes async route throws reach the error handler instead of crashing
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { pool } = require('./db/pool_v0_13');
const { EXPECTED_SCHEMA_VERSION } = require('./db/version_v0_13');
const { regenerateAllApproved } = require('./services/schedule.service_v0_13');
const { autoCompleteOverdue } = require('./services/booking.service_v0_13');
const { runScheduledNotifications } = require('./services/notification.service_v0_13');

const app = express();

// =============================================================================
// (v0.13) Production hardening — required before the app can face the stores.
// =============================================================================
const isProd = process.env.NODE_ENV === 'production';

// Behind a reverse proxy (nginx / Render / Railway) so rate limiting and
// req.ip see the real client address rather than the proxy's.
app.set('trust proxy', 1);

// Security headers. The API serves JSON plus two small HTML pages, so the
// default CSP is relaxed only enough for those to render.
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", 'data:'],
      objectSrc: ["'none'"],
      frameAncestors: ["'none'"],
    },
  },
  crossOriginEmbedderPolicy: false,
}));

// CORS: the mobile app sends no Origin header, so it is unaffected. In
// production only the domains listed in CORS_ORIGINS may call the API from a
// browser; in development everything is allowed.
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',').map((o) => o.trim()).filter(Boolean);
app.use(cors({
  origin(origin, cb) {
    if (!origin || !isProd || allowedOrigins.length === 0) return cb(null, true);
    return cb(null, allowedOrigins.includes(origin));
  },
}));

app.use(express.json({ limit: '15mb' })); // allow base64 document uploads at signup (item 1)

// Rate limits. Auth endpoints are the ones worth brute-forcing, so they get a
// tighter budget than the rest of the API.
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: isProd ? 600 : 100000,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests — please slow down and try again shortly.' },
});
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: isProd ? 30 : 100000,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,   // only failed attempts count
  message: { error: 'Too many attempts — please try again in a few minutes.' },
});
app.use('/api', apiLimiter);
app.use(['/api/auth/login', '/api/auth/verify', '/api/auth/forgot-password',
         '/api/auth/reset-password', '/api/account/request-deletion'], authLimiter);

// Refuse to boot in production with development defaults. Better a loud crash
// at deploy time than leaking OTP codes to real users.
if (isProd) {
  const problems = [];
  if (process.env.OTP_DEV_MODE === 'true') problems.push('OTP_DEV_MODE must be false in production (it returns verification codes in API responses)');
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET === 'change-me-in-production') problems.push('JWT_SECRET must be set to a strong unique value');
  if (!process.env.PGPASSWORD) problems.push('PGPASSWORD must be set');
  if (problems.length > 0) {
    console.error('\nRefusing to start in production:\n  - ' + problems.join('\n  - ') + '\n');
    process.exit(1);
  }
}

app.get('/health', (req, res) => res.json({ ok: true, service: 'fitness-platform-api' }));

// Reports whether the DB schema matches what this code expects (v0.3 hardening).
app.get('/health/schema', async (req, res) => {
  try {
    const r = await pool.query(`SELECT version FROM schema_meta WHERE id=1`);
    const current = r.rows[0]?.version ?? 0;
    res.json({ current, expected: EXPECTED_SCHEMA_VERSION, upToDate: current >= EXPECTED_SCHEMA_VERSION });
  } catch {
    res.json({ current: 0, expected: EXPECTED_SCHEMA_VERSION, upToDate: false, note: 'schema_meta missing — run: npm run migrate' });
  }
});

app.use('/api/auth', require('./routes/auth_v0_13'));
app.use('/api/members', require('./routes/members_v0_13'));
app.use('/api/coaches', require('./routes/coaches_v0_13'));
app.use('/api/bookings', require('./routes/bookings_v0_13'));
app.use('/api/notifications', require('./routes/notifications_v0_13'));
app.use('/api/admin', require('./routes/admin_v0_13'));
app.use('/api/account', require('./routes/account_v0_13'));
app.use('/api/profile', require('./routes/profile_v0_13').router);
app.use('/api/push', require('./routes/push_v0_13'));
app.use('/api/health', require('./routes/health_v0_13'));

// (v0.13) Public pages required by the stores: a privacy policy URL and a
// web account-deletion request form that works without the app installed.
app.use('/', require('./routes/public_pages_v0_13'));

// 404 + error fallthrough
app.use((req, res) => res.status(404).json({ error: 'Not found' }));
app.use((err, req, res, next) => {
  // Postgres invalid-text-representation (e.g. malformed UUID in a param)
  if (err && err.code === '22P02') return res.status(400).json({ error: 'Invalid identifier format' });
  // Check-constraint violation (e.g. overbooking backstop, spec §7.2)
  if (err && err.code === '23514') return res.status(409).json({ error: 'Operation violates a data constraint' });
  // Undefined column / table — almost always a stale schema (v0.3 hardening)
  if (err && (err.code === '42703' || err.code === '42P01'))
    return res.status(500).json({ error: 'Database schema is out of date. Run: npm run migrate' });
  console.error(err);
  res.status(500).json({ error: 'Internal error' });
});

async function checkSchema() {
  try {
    const r = await pool.query(`SELECT version FROM schema_meta WHERE id=1`);
    const current = r.rows[0]?.version ?? 0;
    if (current < EXPECTED_SCHEMA_VERSION) {
      console.warn(`\n⚠️  DB schema is v${current} but this code expects v${EXPECTED_SCHEMA_VERSION}.`);
      console.warn('   Run "npm run migrate" before using the app, or registrations and some tabs will error.\n');
    }
  } catch {
    console.warn('\n⚠️  Could not read schema version (schema_meta missing). Run "npm run migrate".\n');
  }
}

const PORT = parseInt(process.env.PORT || '4000', 10);
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`API listening on http://localhost:${PORT}`);
    checkSchema();
    // v0.5: keep the rolling 4-week session horizon topped up.
    regenerateAllApproved()
      .then((n) => { if (n > 0) console.log(`[schedule] generated ${n} sessions at startup`); })
      .catch((e) => console.error('[schedule] startup generation failed:', e.message));
    autoCompleteOverdue().catch((e) => console.error('[auto-complete] startup run failed:', e.message));
    setInterval(() => {
      regenerateAllApproved().catch((e) => console.error('[schedule] periodic generation failed:', e.message));
      autoCompleteOverdue().catch((e) => console.error('[auto-complete] periodic run failed:', e.message));
    }, 6 * 60 * 60 * 1000);
    // (v0.11) Session reminders (24h / 1h) and package expiry notices need a
    // finer tick than the 6-hour maintenance job.
    runScheduledNotifications().catch((e) => console.error('[notifications] startup run failed:', e.message));
    setInterval(() => {
      runScheduledNotifications().catch((e) => console.error('[notifications] periodic run failed:', e.message));
      // (v0.14 item 13) 5-minute tick so the 15-minute reminder is accurate.
    }, 5 * 60 * 1000);
  });
}

module.exports = app;
