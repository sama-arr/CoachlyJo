// =============================================================================
// Zoom integration (v0.5 item 3) — real Server-to-Server OAuth flow.
//
// Setup (see README "Zoom setup"):
//   1. marketplace.zoom.us -> Develop -> Build App -> Server-to-Server OAuth
//   2. Add the meeting:write:admin scope, activate the app
//   3. Put the three credentials in backend/.env:
//        ZOOM_ACCOUNT_ID=...
//        ZOOM_CLIENT_ID=...
//        ZOOM_CLIENT_SECRET=...
//
// Without credentials the service returns deterministic PLACEHOLDER links so
// every flow stays testable in dev — Zoom will report "invalid meeting ID"
// for those, which is expected until real credentials are configured.
// With credentials, a real meeting is created (topic, start time, duration).
// If the Zoom API call fails, we log the error and fall back to a placeholder
// so a Zoom outage can never block bookings; the failure is visible in logs.
// =============================================================================
const crypto = require('crypto');

let _token = null;
let _tokenExpiresAt = 0;

function hasCreds() {
  return !!(process.env.ZOOM_ACCOUNT_ID && process.env.ZOOM_CLIENT_ID && process.env.ZOOM_CLIENT_SECRET);
}

function placeholder(sessionId) {
  const id = crypto.randomBytes(5).toString('hex');
  return {
    meetingId: `dev-${id}`,
    joinUrl: `https://zoom.us/j/${id}?session=${sessionId}`,
    startUrl: `https://zoom.us/s/${id}?session=${sessionId}`,
    placeholder: true,
  };
}

async function getAccessToken() {
  if (_token && Date.now() < _tokenExpiresAt - 60000) return _token;
  const basic = Buffer.from(`${process.env.ZOOM_CLIENT_ID}:${process.env.ZOOM_CLIENT_SECRET}`).toString('base64');
  const url = `https://zoom.us/oauth/token?grant_type=account_credentials&account_id=${encodeURIComponent(process.env.ZOOM_ACCOUNT_ID)}`;
  const r = await fetch(url, { method: 'POST', headers: { Authorization: `Basic ${basic}` } });
  if (!r.ok) throw new Error(`Zoom token request failed (${r.status}): ${await r.text()}`);
  const data = await r.json();
  _token = data.access_token;
  _tokenExpiresAt = Date.now() + (data.expires_in || 3600) * 1000;
  return _token;
}

/**
 * Creates a Zoom meeting for a session.
 * @param {string} sessionId
 * @param {object} [details] { topic, startAt (Date|ISO), durationMinutes }
 */
async function generateZoomLink(sessionId, details = {}) {
  if (!hasCreds()) return placeholder(sessionId);

  try {
    const token = await getAccessToken();
    const body = {
      topic: details.topic || 'Fitness coaching session',
      type: 2, // scheduled meeting
      start_time: details.startAt ? new Date(details.startAt).toISOString() : undefined,
      duration: details.durationMinutes || 50,
      settings: {
        join_before_host: true,
        waiting_room: false,
        approval_type: 2,
      },
    };
    const r = await fetch('https://api.zoom.us/v2/users/me/meetings', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(`Zoom meeting creation failed (${r.status}): ${await r.text()}`);
    const m = await r.json();
    return { meetingId: String(m.id), joinUrl: m.join_url, startUrl: m.start_url, placeholder: false };
  } catch (err) {
    console.error(`[ZOOM ERROR] ${err.message} — falling back to placeholder link for session ${sessionId}`);
    return placeholder(sessionId);
  }
}

module.exports = { generateZoomLink, hasCreds };
