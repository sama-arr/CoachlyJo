// =============================================================================
// CoachlyJo Zoom integration
//
// Production:
//   - Uses Zoom Server-to-Server OAuth
//   - Creates a real scheduled meeting under ZOOM_HOST_USER
//   - Never silently creates a fake Zoom link
//
// Required Render environment variables:
//   ZOOM_ACCOUNT_ID
//   ZOOM_CLIENT_ID
//   ZOOM_CLIENT_SECRET
//   ZOOM_HOST_USER
//
// Optional LOCAL development only:
//   ZOOM_ALLOW_PLACEHOLDER=true
// =============================================================================

const crypto = require('crypto');

let _token = null;
let _tokenExpiresAt = 0;

function hasCreds() {
  return !!(
    process.env.ZOOM_ACCOUNT_ID &&
    process.env.ZOOM_CLIENT_ID &&
    process.env.ZOOM_CLIENT_SECRET &&
    process.env.ZOOM_HOST_USER
  );
}

function allowPlaceholder() {
  return process.env.ZOOM_ALLOW_PLACEHOLDER === 'true';
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
  if (_token && Date.now() < _tokenExpiresAt - 60000) {
    return _token;
  }

  const basic = Buffer.from(
    `${process.env.ZOOM_CLIENT_ID}:${process.env.ZOOM_CLIENT_SECRET}`
  ).toString('base64');

  const url =
    'https://zoom.us/oauth/token' +
    '?grant_type=account_credentials' +
    `&account_id=${encodeURIComponent(process.env.ZOOM_ACCOUNT_ID)}`;

  const r = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${basic}`,
    },
  });

  if (!r.ok) {
    throw new Error(
      `Zoom token request failed (${r.status}): ${await r.text()}`
    );
  }

  const data = await r.json();

  if (!data.access_token) {
    throw new Error('Zoom did not return an access token');
  }

  _token = data.access_token;
  _tokenExpiresAt =
    Date.now() + (data.expires_in || 3600) * 1000;

  return _token;
}

/**
 * Create a Zoom meeting for an online CoachlyJo session.
 *
 * @param {string} sessionId
 * @param {object} details
 * @param {string} details.topic
 * @param {Date|string} details.startAt
 * @param {number} details.durationMinutes
 */
async function generateZoomLink(sessionId, details = {}) {
  if (!hasCreds()) {
    if (allowPlaceholder()) {
      console.warn(
        `[ZOOM DEV] Missing Zoom credentials. Using placeholder for session ${sessionId}`
      );

      return placeholder(sessionId);
    }

    throw new Error(
      'Zoom is not configured. ZOOM_ACCOUNT_ID, ZOOM_CLIENT_ID, ' +
      'ZOOM_CLIENT_SECRET and ZOOM_HOST_USER are required.'
    );
  }

  try {
    const token = await getAccessToken();

    const hostUser = process.env.ZOOM_HOST_USER.trim();

    const body = {
      topic: details.topic || 'CoachlyJo coaching session',
      type: 2,
      start_time: details.startAt
        ? new Date(details.startAt).toISOString()
        : undefined,
      duration: details.durationMinutes || 50,

      settings: {
        join_before_host: true,
        waiting_room: false,
        approval_type: 2,
      },
    };

    const r = await fetch(
      `https://api.zoom.us/v2/users/${encodeURIComponent(hostUser)}/meetings`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      }
    );

    if (!r.ok) {
      throw new Error(
        `Zoom meeting creation failed (${r.status}): ${await r.text()}`
      );
    }

    const meeting = await r.json();

    if (
      !meeting.id ||
      !meeting.join_url
    ) {
      throw new Error(
        'Zoom created a meeting but did not return a valid meeting ID or join URL'
      );
    }

    console.log(
      `[ZOOM] Created real meeting ${meeting.id} for session ${sessionId}`
    );

    return {
      meetingId: String(meeting.id),
      joinUrl: meeting.join_url,
      startUrl: meeting.start_url || null,
      placeholder: false,
    };
  } catch (err) {
    console.error(
      `[ZOOM ERROR] Session ${sessionId}: ${err.message}`
    );

    // Fake links are allowed ONLY when explicitly enabled for local development.
    if (allowPlaceholder()) {
      console.warn(
        `[ZOOM DEV] Falling back to placeholder for session ${sessionId}`
      );

      return placeholder(sessionId);
    }

    // Production must never pretend a fake Zoom meeting exists.
    throw err;
  }
}

module.exports = {
  generateZoomLink,
  hasCreds,
};