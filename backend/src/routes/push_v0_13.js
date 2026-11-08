// =============================================================================
// Push notification device registration (v0.14 item 13).
//
// The app asks the OS for notification permission, gets an FCM token and posts
// it here. The server stores one row per device and sends through Firebase.
// Tokens are removed when Firebase reports them invalid (app uninstalled).
// =============================================================================
const express = require('express');
const { pool } = require('../db/pool_v0_13');
const { authenticate } = require('../middleware/auth_v0_13');

const router = express.Router();

// Register (or refresh) this device's push token for the signed-in user.
router.post('/register', authenticate, async (req, res) => {
  const { token, platform } = req.body || {};
  if (!token || typeof token !== 'string' || token.length < 20)
    return res.status(400).json({ error: 'A valid device token is required' });
  if (!['android', 'ios', 'web'].includes(platform))
    return res.status(400).json({ error: 'platform must be android, ios or web' });

  // A phone can change hands or accounts — the token always points at the
  // account that most recently signed in on that device.
  await pool.query(
    `INSERT INTO device_tokens (user_id, token, platform)
     VALUES ($1, $2, $3)
     ON CONFLICT (token) DO UPDATE
        SET user_id = EXCLUDED.user_id,
            platform = EXCLUDED.platform,
            last_seen = now()`,
    [req.user.id, token, platform]);
  res.json({ registered: true });
});

// Called on sign-out so the next user of the device does not receive the
// previous user's notifications.
router.delete('/register', authenticate, async (req, res) => {
  const { token } = req.body || {};
  if (!token) return res.status(400).json({ error: 'token required' });
  await pool.query(`DELETE FROM device_tokens WHERE token = $1 AND user_id = $2`,
    [token, req.user.id]);
  res.json({ removed: true });
});

module.exports = router;
