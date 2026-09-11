// =============================================================================
// Mail service (v0.5 item 1). Sends real email when SMTP_* env vars are set;
// otherwise runs in dev mode: the message is logged to the server console and
// (for OTP/reset codes) surfaced to API responses when OTP_DEV_MODE is on.
//
// .env keys:
//   SMTP_HOST=smtp.example.com
//   SMTP_PORT=587            (465 => implicit TLS)
//   SMTP_USER=apikey-or-account
//   SMTP_PASS=secret
//   SMTP_FROM="Apex Fitness <no-reply@example.com>"   (defaults to SMTP_USER)
// =============================================================================
const nodemailer = require('nodemailer');

function smtpConfigured() {
  return !!(process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS);
}

let _transporter = null;
function transporter() {
  if (!_transporter) {
    const port = parseInt(process.env.SMTP_PORT || '587', 10);
    _transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port,
      secure: port === 465,
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    });
  }
  return _transporter;
}

/**
 * Sends an email. Returns { sent: boolean, dev: boolean }.
 * Never throws — mail failure must not break the calling flow; it is logged.
 */
async function sendMail({ to, subject, text }) {
  if (!smtpConfigured()) {
    console.log(`[DEV MAIL] to=${to} subject="${subject}"\n${text}\n`);
    return { sent: false, dev: true };
  }
  try {
    await transporter().sendMail({
      from: process.env.SMTP_FROM || process.env.SMTP_USER,
      to,
      subject,
      text,
    });
    return { sent: true, dev: false };
  } catch (err) {
    console.error(`[MAIL ERROR] to=${to}: ${err.message}`);
    return { sent: false, dev: false };
  }
}

module.exports = { sendMail, smtpConfigured };
