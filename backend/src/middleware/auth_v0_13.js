const jwt = require('jsonwebtoken');
const { pool } = require('../db/pool_v0_13');

const SECRET = process.env.JWT_SECRET || 'dev-secret';

// (v0.13) A token stays cryptographically valid until it expires, so a deleted
// or deactivated account could keep using the API for days. Every authenticated
// request now confirms the account is still live. One indexed primary-key
// lookup; results are cached briefly to keep it cheap under load.
const liveCache = new Map();           // userId -> { live: boolean, at: number }
const CACHE_MS = 30 * 1000;

async function accountIsLive(userId) {
  const hit = liveCache.get(userId);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.live;
  const r = await pool.query(
    `SELECT deleted_at, is_active FROM users WHERE id = $1`, [userId]);
  const live = r.rowCount > 0 && r.rows[0].deleted_at === null && r.rows[0].is_active !== false;
  liveCache.set(userId, { live, at: Date.now() });
  return live;
}

/** Called after deleting/deactivating an account so the change takes effect at once. */
function invalidateAccount(userId) {
  liveCache.delete(userId);
}

function sign(user) {
  return jwt.sign(
    { id: user.id, role: user.role, email: user.email },
    SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
  );
}

// Verifies the Bearer token and attaches req.user.
async function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Missing token' });
  let payload;
  try {
    payload = jwt.verify(token, SECRET);
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  if (!(await accountIsLive(payload.id))) {
    return res.status(401).json({ error: 'This account is no longer active' });
  }
  req.user = payload;
  next();
}

// Like authenticate, but also accepts ?token= in the query string. Use ONLY on
// binary download endpoints (document / payment-proof viewing), where the file
// may be opened by an external viewer that cannot set an Authorization header.
async function authenticateAllowQueryToken(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : (req.query.token || null);
  if (!token) return res.status(401).json({ error: 'Missing token' });
  let payload;
  try {
    payload = jwt.verify(token, SECRET);
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
  if (!(await accountIsLive(payload.id))) {
    return res.status(401).json({ error: 'This account is no longer active' });
  }
  req.user = payload;
  next();
}

// Restricts a route to one or more roles.
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Forbidden: insufficient role' });
    }
    next();
  };
}

module.exports = {
  invalidateAccount, sign, authenticate, authenticateAllowQueryToken, requireRole };
