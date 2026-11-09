// =============================================================================
// Integration health (v0.15).
//
// The Zoom link failure in v0.14 testing was caused by ONE missing environment
// variable (ZOOM_HOST_USER), and nothing in the product said so — bookings just
// quietly had no link. This endpoint makes the running server state visible, so
// a misconfiguration is obvious in the admin app instead of being discovered by
// a member who cannot join their session.
//
// Admin-only: it reports whether credentials are present, never their values.
// =============================================================================
const express = require('express');
const { pool } = require('../db/pool_v0_13');
const { authenticate, requireRole } = require('../middleware/auth_v0_13');
const { hasCreds: zoomConfigured } = require('../services/zoom.service_v0_13');
const { smtpConfigured } = require('../services/mail.service_v0_13');
const { isConfigured: pushConfigured } = require('../services/push.service_v0_13');
const { EXPECTED_SCHEMA_VERSION } = require('../db/version_v0_13');

const router = express.Router();

router.get('/integrations', authenticate, requireRole('admin'), async (req, res) => {
  const zoomOk = zoomConfigured();
  const missingZoom = ['ZOOM_ACCOUNT_ID', 'ZOOM_CLIENT_ID', 'ZOOM_CLIENT_SECRET', 'ZOOM_HOST_USER']
    .filter((k) => !process.env[k]);

  // Sessions accepted recently that still have no meeting link — the symptom a
  // member actually experiences.
  const pending = await pool.query(
    `SELECT COUNT(*)::int AS n
       FROM bookings b JOIN coach_sessions cs ON cs.id = b.session_id
      WHERE b.status = 'accepted' AND cs.delivery = 'online'
        AND cs.start_at > now()
        AND (cs.zoom_join_url IS NULL OR cs.zoom_join_url = '')`);

  const devices = await pool.query(
    `SELECT platform, COUNT(*)::int AS n FROM device_tokens GROUP BY platform`);

  const schema = await pool.query(`SELECT version FROM schema_meta WHERE id=1`);

  res.json({
    zoom: {
      configured: zoomOk,
      missing: missingZoom,
      placeholdersAllowed: process.env.ZOOM_ALLOW_PLACEHOLDER === 'true',
      sessionsWithoutLink: pending.rows[0].n,
    },
    email: { configured: smtpConfigured() },
    push: {
      configured: pushConfigured(),
      devices: devices.rows.reduce((acc, r) => ({ ...acc, [r.platform]: r.n }), {}),
    },
    schema: {
      current: schema.rows[0]?.version ?? null,
      expected: EXPECTED_SCHEMA_VERSION,
      upToDate: (schema.rows[0]?.version ?? null) === EXPECTED_SCHEMA_VERSION,
    },
    environment: process.env.NODE_ENV || 'development',
  });
});

module.exports = router;
