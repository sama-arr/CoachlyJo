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
async function sendMail({ to, subject, text, html }) {
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
      ...(html ? { html } : {}),
    });
    return { sent: true, dev: false };
  } catch (err) {
    console.error(`[MAIL ERROR] to=${to}: ${err.message}`);
    return { sent: false, dev: false };
  }
}

// =============================================================================
// (v0.14 item 10) Branded HTML email.
//
// The wordmark is rendered as styled TEXT, not an image: most mail clients
// block remote images by default, so a logo <img> shows as a broken box for a
// large share of recipients. Gradient text degrades to a solid colour in older
// clients and is always legible. Every email also carries a plain-text part.
// =============================================================================
const BRAND_MAGENTA = '#C91E97';
const BRAND_ORANGE = '#D9700F';

function emailShell({ heading, intro, bodyHtml, footerNote, dir = 'ltr' }) {
  const align = dir === 'rtl' ? 'right' : 'left';
  return `<!doctype html>
<html dir="${dir}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0A0A0E;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0A0A0E;padding:28px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:520px;background:#15151B;border:1px solid #23232C;border-radius:18px;overflow:hidden;">
        <!-- brand bar -->
        <tr><td style="background:linear-gradient(90deg,${BRAND_MAGENTA},${BRAND_ORANGE});padding:22px 26px;">
          <span style="font:800 26px/1 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#ffffff;letter-spacing:-0.5px;">CoachlyJo</span>
        </td></tr>
        <tr><td style="padding:28px 26px 8px;text-align:${align};">
          <h1 style="margin:0 0 10px;font:700 19px/1.4 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#EDEDF2;">${heading}</h1>
          <p style="margin:0 0 18px;font:400 14px/1.7 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#CFCFDA;">${intro}</p>
          ${bodyHtml}
        </td></tr>
        <tr><td style="padding:10px 26px 26px;text-align:${align};">
          <p style="margin:0;font:400 12px/1.6 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#9A9AA6;">${footerNote}</p>
        </td></tr>
        <tr><td style="background:#101016;padding:16px 26px;text-align:center;">
          <p style="margin:0;font:400 11px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#6E6E7A;">
            CoachlyJo — fitness coaching in Amman
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

/** Big, selectable, monospaced code block used for OTP and reset codes. */
function codeBlock(code) {
  return `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 18px;">
    <tr><td style="background:#0F0F14;border:1px solid ${BRAND_MAGENTA};border-radius:12px;padding:16px 26px;">
      <span style="font:800 30px/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;color:#FFFFFF;letter-spacing:7px;">${code}</span>
    </td></tr></table>`;
}

/**
 * Verification / password-reset code email, in the user's language.
 * @param {'verify'|'reset'} kind
 */
async function sendCodeEmail({ to, code, kind, minutes = 10, lang = 'en' }) {
  const ar = lang === 'ar';
  const copy = ar
    ? {
        subject: kind === 'reset' ? 'رمز إعادة تعيين كلمة المرور' : 'رمز التحقق الخاص بك',
        heading: kind === 'reset' ? 'إعادة تعيين كلمة المرور' : 'تأكيد بريدك الإلكتروني',
        intro: kind === 'reset'
          ? 'استخدم الرمز التالي لإعادة تعيين كلمة المرور الخاصة بك:'
          : 'استخدم الرمز التالي لتأكيد حسابك:',
        footer: `ينتهي هذا الرمز خلال ${minutes} دقائق. إذا لم تطلبه، يمكنك تجاهل هذه الرسالة.`,
      }
    : {
        subject: kind === 'reset' ? 'Your password reset code' : 'Your verification code',
        heading: kind === 'reset' ? 'Reset your password' : 'Confirm your email',
        intro: kind === 'reset'
          ? 'Use the code below to reset your password:'
          : 'Use the code below to confirm your account:',
        footer: `This code expires in ${minutes} minutes. If you did not request it, you can ignore this email.`,
      };

  return sendMail({
    to,
    subject: `CoachlyJo — ${copy.subject}`,
    text: `${copy.heading}\n\n${code}\n\n${copy.footer}`,
    html: emailShell({
      heading: copy.heading,
      intro: copy.intro,
      bodyHtml: codeBlock(code),
      footerNote: copy.footer,
      dir: ar ? 'rtl' : 'ltr',
    }),
  });
}

/** Generic branded notification email (bookings, packages, reminders). */
async function sendNotificationEmail({ to, title, body, lang = 'en' }) {
  const ar = lang === 'ar';
  return sendMail({
    to,
    subject: `CoachlyJo — ${title}`,
    text: `${title}\n\n${body}`,
    html: emailShell({
      heading: title,
      intro: body,
      bodyHtml: '',
      footerNote: ar
        ? 'يمكنك إدارة جلساتك من تطبيق كوتشلي جو.'
        : 'You can manage your sessions in the CoachlyJo app.',
      dir: ar ? 'rtl' : 'ltr',
    }),
  });
}

module.exports = { sendMail, smtpConfigured, sendCodeEmail, sendNotificationEmail, emailShell };
