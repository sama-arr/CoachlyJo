// =============================================================================
// Push notifications via Firebase Cloud Messaging (v0.14 item 13).
//
// CONFIGURATION (see README "Push notifications"):
//   FIREBASE_PROJECT_ID
//   FIREBASE_CLIENT_EMAIL
//   FIREBASE_PRIVATE_KEY      (the whole key; \n escapes are handled)
// All three come from the Firebase service-account JSON. iOS additionally needs
// an APNs Auth Key uploaded inside the Firebase console — no server setting.
//
// Without those variables this module is a silent no-op: notifications still
// appear in the in-app centre and by email, nothing errors, nothing logs noise.
// That means the app ships complete today and push switches on the moment the
// credentials are added — no code change, no new build.
//
// Implemented with the FCM HTTP v1 REST API and a self-signed JWT, so there is
// no firebase-admin dependency to install or keep updated.
// =============================================================================
const crypto = require('crypto');
const { pool } = require('../db/pool_v0_13');

const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

function isConfigured() {
  return !!(process.env.FIREBASE_PROJECT_ID
    && process.env.FIREBASE_CLIENT_EMAIL
    && process.env.FIREBASE_PRIVATE_KEY);
}

let cachedToken = null;
let cachedUntil = 0;

function base64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

/** Exchange the service-account key for a short-lived OAuth access token. */
async function accessToken() {
  if (cachedToken && Date.now() < cachedUntil - 60000) return cachedToken;

  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = base64url(JSON.stringify({
    iss: process.env.FIREBASE_CLIENT_EMAIL,
    scope: SCOPE,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));

  // Render and most hosts store the key with literal \n sequences.
  const privateKey = process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n');
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(`${header}.${claim}`)
    .sign(privateKey, 'base64')
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claim}.${signature}`,
    }),
  });
  if (!r.ok) throw new Error(`Firebase token request failed (${r.status}): ${await r.text()}`);
  const data = await r.json();
  cachedToken = data.access_token;
  cachedUntil = Date.now() + (data.expires_in || 3600) * 1000;
  return cachedToken;
}

/**
 * Send one push to every device registered to a user.
 * Never throws: a failed push must not break the action that triggered it.
 *
 * @param {string} userId
 * @param {object} msg { title, body, type, relatedId }
 */
async function sendToUser(userId, msg) {
  if (!isConfigured()) return { sent: 0, skipped: true };

  const devices = await pool.query(
    `SELECT token, platform FROM device_tokens WHERE user_id = $1`, [userId]);
  if (devices.rowCount === 0) return { sent: 0, skipped: false };

  let token;
  try {
    token = await accessToken();
  } catch (err) {
    console.error(`[push] auth failed: ${err.message}`);
    return { sent: 0, skipped: false };
  }

  const url = `https://fcm.googleapis.com/v1/projects/${process.env.FIREBASE_PROJECT_ID}/messages:send`;
  let sent = 0;

  for (const d of devices.rows) {
    const payload = {
      message: {
        token: d.token,
        notification: { title: msg.title, body: msg.body },
        // The app reads these on tap to open the right screen.
        data: {
          type: String(msg.type || ''),
          relatedId: String(msg.relatedId || ''),
        },
        android: {
          priority: 'high',
          notification: { channel_id: 'coachlyjo_default', sound: 'default' },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'default', badge: 1 } },
        },
      },
    };

    try {
      const r = await fetch(url, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (r.ok) {
        sent++;
        continue;
      }
      const text = await r.text();
      // 404 UNREGISTERED / 400 INVALID_ARGUMENT means the app was uninstalled
      // or the token rotated — drop it so the table stays clean.
      if (r.status === 404 || /UNREGISTERED|INVALID_ARGUMENT/.test(text)) {
        await pool.query(`DELETE FROM device_tokens WHERE token = $1`, [d.token]);
      } else {
        console.error(`[push] FCM ${r.status}: ${text.slice(0, 200)}`);
      }
    } catch (err) {
      console.error(`[push] send failed: ${err.message}`);
    }
  }
  return { sent, skipped: false };
}

module.exports = { sendToUser, isConfigured };
