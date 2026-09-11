const express = require('express');
const bcrypt = require('bcryptjs');
const { pool, withTransaction } = require('../db/pool_v0_13');
const { sign, authenticate } = require('../middleware/auth_v0_13');
const { sendMail } = require('../services/mail.service_v0_13');
const { notifyAdmins } = require('../services/notification.service_v0_13');

const router = express.Router();
const DEV_OTP = process.env.OTP_DEV_MODE !== 'false';

function validPassword(pw) {
  return typeof pw === 'string' && pw.length >= 8; // spec §15.1
}

// (item 12) Email must look like example@abc.com
function validEmail(e) {
  return typeof e === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);
}

// (item 12) User types 07XXXXXXXX (exactly 10 digits, leading 0).
// Stored normalized as 009627XXXXXXXX (strip leading 0, prepend 009627).
function normalizePhone(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  if (!/^0\d{9}$/.test(digits)) return null; // must be 10 digits starting with 0
  return '009627' + digits.slice(2); // drop leading "07", keep subscriber number
}

// --- Member registration (spec §3) — v0.2: + location ---
router.post('/register/member', async (req, res) => {
  const { email, phone, password, firstName, lastName, location,
          dateOfBirth, birthPlace, nationality, assessment } = req.body || {};
  if (!email || !phone || !validPassword(password) || !firstName || !lastName)
    return res.status(400).json({ error: 'email, phone, firstName, lastName and password (min 8) required' });
  if (!validEmail(email)) return res.status(400).json({ error: 'Invalid email format' });
  const normPhone = normalizePhone(phone);
  if (!normPhone) return res.status(400).json({ error: 'Phone must be 10 digits starting with 0 (e.g. 0791234567)' });

  try {
    const result = await withTransaction(async (client) => {
      const hash = await bcrypt.hash(password, 10);
      const u = await client.query(
        `INSERT INTO users (role, email, phone, password_hash) VALUES ('member',$1,$2,$3) RETURNING id, role, email`,
        [email, normPhone, hash]
      );
      const user = u.rows[0];
      await client.query(
        `INSERT INTO member_profiles (user_id, first_name, last_name, location, date_of_birth, birth_place, nationality)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [user.id, firstName, lastName, location || null, dateOfBirth || null, birthPlace || null, nationality || null]
      );
      if (assessment) {
        await client.query(
          `INSERT INTO fitness_assessments (member_id, responses) VALUES ($1,$2)`,
          [user.id, assessment]
        );
      }
      return user;
    });
    const otp = await issueOtp(result.id);
    res.status(201).json({ user: result, devOtp: DEV_OTP ? otp : undefined });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Email or phone already registered' });
    res.status(500).json({ error: err.message });
  }
});

// --- Coach registration (spec §4) — v0.2: documents uploaded at signup ---
// documents: [{ docType, fileName, mimeType, dataBase64 }]
const ALLOWED_DOC_MIME = {
  'application/pdf': true,
  'application/msword': true,
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': true,
  'image/jpeg': true,
  'image/png': true,
};
const MAX_DOC_BYTES = 10 * 1024 * 1024; // 10 MB cap (item 1)

router.post('/register/coach', async (req, res) => {
  const { email, phone, password, firstName, lastName, dateOfBirth, nationality,
          birthPlace, location, bio, documents } = req.body || {};
  if (!email || !phone || !validPassword(password) || !firstName || !lastName || !dateOfBirth || !nationality)
    return res.status(400).json({ error: 'All coach fields and password (min 8) required' });
  if (!validEmail(email)) return res.status(400).json({ error: 'Invalid email format' });
  const normPhone = normalizePhone(phone);
  if (!normPhone) return res.status(400).json({ error: 'Phone must be 10 digits starting with 0 (e.g. 0791234567)' });

  const docs = Array.isArray(documents) ? documents : [];
  for (const d of docs) {
    if (!ALLOWED_DOC_MIME[d.mimeType])
      return res.status(400).json({ error: `Unsupported file type ${d.mimeType}. Allowed: pdf, doc, docx, jpg, png` });
    const size = Buffer.byteLength(d.dataBase64 || '', 'base64');
    if (size > MAX_DOC_BYTES) return res.status(400).json({ error: `File ${d.fileName} exceeds 10MB` });
  }

  try {
    const result = await withTransaction(async (client) => {
      const hash = await bcrypt.hash(password, 10);
      const u = await client.query(
        `INSERT INTO users (role, email, phone, password_hash) VALUES ('coach',$1,$2,$3) RETURNING id, role, email`,
        [email, normPhone, hash]
      );
      const user = u.rows[0];
      await client.query(
        `INSERT INTO coach_profiles (user_id, first_name, last_name, date_of_birth, nationality, birth_place, location, bio_en)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [user.id, firstName, lastName, dateOfBirth, nationality, birthPlace || null, location || null, bio || null]
      );
      for (const d of docs) {
        await client.query(
          `INSERT INTO coach_documents (coach_id, doc_type, content, mime_type, file_name, byte_size)
           VALUES ($1,$2,$3,$4,$5,$6)`,
          [user.id, d.docType, Buffer.from(d.dataBase64, 'base64'), d.mimeType, d.fileName,
           Buffer.byteLength(d.dataBase64 || '', 'base64')]
        );
      }
      return user;
    });
    const otp = await issueOtp(result.id);
    // (v0.11) Admins are told a coach application is waiting for review.
    await notifyAdmins({
      type: 'admin_new_coach',
      titleEn: 'New coach application',
      titleAr: 'طلب انضمام مدرب جديد',
      bodyEn: `${firstName} ${lastName} applied to join as a coach.`,
      bodyAr: `تقدّم ${firstName} ${lastName} بطلب الانضمام كمدرب.`,
      relatedId: result.id,
      email: true,
    });
    res.status(201).json({
      user: result,
      note: 'Account created with documents. Await admin approval before becoming visible.',
      devOtp: DEV_OTP ? otp : undefined,
    });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Email or phone already registered' });
    res.status(500).json({ error: err.message });
  }
});

// --- Verify OTP (spec §3.1, §15.2) ---
router.post('/verify', async (req, res) => {
  const { userId, code, channel } = req.body || {};
  if (!userId || !code || !channel) return res.status(400).json({ error: 'userId, code, channel required' });
  try {
    const r = await pool.query(
      `SELECT * FROM otp_verifications
        WHERE user_id=$1 AND channel=$2 AND consumed_at IS NULL AND expires_at > now()
        ORDER BY created_at DESC LIMIT 1`,
      [userId, channel]
    );
    if (r.rowCount === 0) return res.status(400).json({ error: 'No valid OTP; request a new one' });
    const ok = await bcrypt.compare(String(code), r.rows[0].code_hash);
    if (!ok) return res.status(400).json({ error: 'Incorrect code' });

    await pool.query(`UPDATE otp_verifications SET consumed_at=now() WHERE id=$1`, [r.rows[0].id]);
    const col = channel === 'email' ? 'email_verified' : 'phone_verified';
    await pool.query(`UPDATE users SET ${col}=TRUE WHERE id=$1`, [userId]);
    res.json({ verified: true, channel });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- Login ---
router.post('/login', async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  try {
    const r = await pool.query(`SELECT * FROM users WHERE email=$1`, [email]);
    if (r.rowCount === 0) return res.status(401).json({ error: 'Invalid credentials' });
    const user = r.rows[0];
    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) return res.status(401).json({ error: 'Invalid credentials' });
    res.json({
      token: sign(user),
      user: { id: user.id, role: user.role, email: user.email,
              emailVerified: user.email_verified, phoneVerified: user.phone_verified },
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- Change password (item 4) — all roles ---
router.post('/change-password', authenticate, async (req, res) => {
  const { oldPassword, newPassword, confirmPassword } = req.body || {};
  if (!oldPassword || !newPassword || !confirmPassword)
    return res.status(400).json({ error: 'oldPassword, newPassword, confirmPassword required' });
  if (newPassword !== confirmPassword)
    return res.status(400).json({ error: 'New password and confirmation do not match' });
  if (!validPassword(newPassword))
    return res.status(400).json({ error: 'New password must be at least 8 characters' });
  const r = await pool.query(`SELECT password_hash FROM users WHERE id=$1`, [req.user.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'User not found' });
  const ok = await bcrypt.compare(oldPassword, r.rows[0].password_hash);
  if (!ok) return res.status(401).json({ error: 'Old password is incorrect' });
  const hash = await bcrypt.hash(newPassword, 10);
  await pool.query(`UPDATE users SET password_hash=$2, updated_at=now() WHERE id=$1`, [req.user.id, hash]);
  res.json({ changed: true });
});

// --- Public: active questionnaire definition (item 2b) ---
router.get('/questionnaire', async (req, res) => {
  const r = await pool.query(
    `SELECT key, label_en, label_ar, input_type, options, required, sort_order
       FROM questionnaire_questions WHERE is_active=TRUE ORDER BY sort_order, created_at`
  );
  res.json(r.rows);
});

// --- Public: active locations for the registration dropdown (items 10,11) ---
router.get('/locations', async (req, res) => {
  const r = await pool.query(
    `SELECT id, name_en, name_ar FROM locations WHERE is_active=TRUE ORDER BY sort_order, name_en`
  );
  res.json(r.rows);
});

router.get('/me', authenticate, async (req, res) => {
  const r = await pool.query(`SELECT id, role, email, phone, email_verified, phone_verified, preferred_lang FROM users WHERE id=$1`, [req.user.id]);
  res.json(r.rows[0] || null);
});

// --- (v0.5 item 1) Forgot password — members & coaches only -----------------
// Neutral response either way so the endpoint can't be used to probe which
// emails are registered (confirmed in v0.5 scope).
const RESET_NEUTRAL = 'If this email is registered, a reset code has been sent.';
const RESET_TTL_MIN = 10;
const RESET_MAX_ATTEMPTS = 5;

// 6-char alphanumeric, unambiguous alphabet (no 0/O/1/I/L).
function makeResetCode() {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < 6; i++) out += alphabet[Math.floor(Math.random() * alphabet.length)];
  return out;
}

router.post('/forgot-password', async (req, res) => {
  const { email } = req.body || {};
  if (!email || !validEmail(email)) return res.status(400).json({ error: 'A valid email is required' });

  const u = await pool.query(
    `SELECT id, email, role FROM users WHERE email=$1 AND role IN ('member','coach')`, [email]);
  if (u.rowCount === 0) {
    // Unknown email (or admin): identical response, no code issued.
    return res.json({ message: RESET_NEUTRAL });
  }
  const user = u.rows[0];
  const code = makeResetCode();
  const hash = await bcrypt.hash(code, 8);
  // A new request invalidates any previous outstanding code.
  await pool.query(`UPDATE password_resets SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL`, [user.id]);
  await pool.query(
    `INSERT INTO password_resets (user_id, code_hash, expires_at)
     VALUES ($1, $2, now() + ($3 || ' minutes')::interval)`,
    [user.id, hash, String(RESET_TTL_MIN)]);

  await sendMail({
    to: user.email,
    subject: 'Your password reset code',
    text: `Your password reset code is: ${code}\n\nIt expires in ${RESET_TTL_MIN} minutes. If you did not request this, you can ignore this email.`,
  });
  if (DEV_OTP) console.log(`[DEV RESET] ${user.email} code = ${code}`);
  res.json({ message: RESET_NEUTRAL, devCode: DEV_OTP ? code : undefined });
});

router.post('/reset-password', async (req, res) => {
  const { email, code, newPassword, confirmPassword } = req.body || {};
  if (!email || !code || !newPassword || !confirmPassword)
    return res.status(400).json({ error: 'email, code, newPassword, confirmPassword required' });
  if (newPassword !== confirmPassword)
    return res.status(400).json({ error: 'New password and confirmation do not match' });
  if (!validPassword(newPassword))
    return res.status(400).json({ error: 'New password must be at least 8 characters' });

  const u = await pool.query(
    `SELECT id FROM users WHERE email=$1 AND role IN ('member','coach')`, [email]);
  // Same message for unknown email / no code / wrong code: don't leak which.
  const INVALID = { error: 'Invalid or expired code' };
  if (u.rowCount === 0) return res.status(400).json(INVALID);

  const r = await pool.query(
    `SELECT * FROM password_resets
      WHERE user_id=$1 AND consumed_at IS NULL AND expires_at > now()
      ORDER BY created_at DESC LIMIT 1`, [u.rows[0].id]);
  if (r.rowCount === 0) return res.status(400).json(INVALID);
  const reset = r.rows[0];
  if (reset.attempts >= RESET_MAX_ATTEMPTS) return res.status(400).json(INVALID);

  const ok = await bcrypt.compare(String(code).toUpperCase(), reset.code_hash);
  if (!ok) {
    await pool.query(`UPDATE password_resets SET attempts = attempts + 1 WHERE id=$1`, [reset.id]);
    return res.status(400).json(INVALID);
  }

  const hash = await bcrypt.hash(newPassword, 10);
  await pool.query(`UPDATE users SET password_hash=$2, updated_at=now() WHERE id=$1`, [u.rows[0].id, hash]);
  await pool.query(`UPDATE password_resets SET consumed_at=now() WHERE id=$1`, [reset.id]);
  res.json({ reset: true });
});

// (v0.10 items 1-3) Home page content: intro, how-it-works steps and the
// rules, filtered by audience. Public so the home page can render before
// login if the app ever needs it.
router.get('/content', async (req, res) => {
  const audience = ['member', 'coach'].includes(req.query.audience) ? req.query.audience : 'member';
  const blocks = await pool.query(
    `SELECT key, audience, kind, title_en, title_ar, body_en, body_ar, sort_order
       FROM content_blocks
      WHERE is_active = TRUE AND audience IN ($1, 'both')
      ORDER BY kind, sort_order`, [audience]);
  const settings = await pool.query(`SELECT intro_video_url FROM platform_settings WHERE id=1`);
  res.json({
    videoUrl: settings.rows[0]?.intro_video_url || '',
    intro: blocks.rows.filter((b) => b.kind === 'intro'),
    steps: blocks.rows.filter((b) => b.kind === 'step'),
    rules: blocks.rows.filter((b) => b.kind === 'rule'),
  });
});

// Create a 6-digit OTP, store hashed, return plaintext in dev mode only.
async function issueOtp(userId) {
  const code = String(Math.floor(100000 + Math.random() * 900000));
  const hash = await bcrypt.hash(code, 8);
  for (const channel of ['email', 'phone']) {
    await pool.query(
      `INSERT INTO otp_verifications (user_id, channel, code_hash, expires_at)
       VALUES ($1,$2,$3, now() + interval '10 minutes')`,
      [userId, channel, hash]
    );
  }
  if (DEV_OTP) console.log(`[DEV OTP] user ${userId} code = ${code}`);
  // v0.5: also send by email when SMTP is configured (no-op in dev mode).
  const u = await pool.query(`SELECT email FROM users WHERE id=$1`, [userId]);
  if (u.rowCount > 0) {
    sendMail({
      to: u.rows[0].email,
      subject: 'Your verification code',
      text: `Your verification code is: ${code}\n\nIt expires in 10 minutes.`,
    });
  }
  return code;
}

module.exports = router;
