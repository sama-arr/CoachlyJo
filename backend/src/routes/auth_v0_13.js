const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { pool, withTransaction } = require('../db/pool_v0_13');
const { sign, authenticate } = require('../middleware/auth_v0_13');
const { sendCodeEmail } = require('../services/mail.service_v0_13');
const { notifyAdmins } = require('../services/notification.service_v0_13');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';
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

// --- Member registration ---
// (v0.14 item 1) Short signup: name, email, phone, password, nationality.
// Date of birth, location and the fitness questionnaire now belong to the
// Complete Profile step inside the app (item 2). Birth place is gone for good.
// `location`, `dateOfBirth` and `assessment` are still accepted so that older
// app builds already in testers' hands keep working.
router.post('/register/member', async (req, res) => {
  const { email, phone, password, firstName, lastName, nationality,
          location, dateOfBirth, assessment } = req.body || {};
  if (!email || !phone || !validPassword(password) || !firstName || !lastName || !nationality)
    return res.status(400).json({ error: 'firstName, lastName, email, phone, password (min 8) and nationality are required' });
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
        `INSERT INTO member_profiles (user_id, first_name, last_name, location, date_of_birth, nationality)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [user.id, firstName, lastName, location || null, dateOfBirth || null, nationality]
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
  // (v0.14 item 1) Short signup for coaches too. Date of birth, bio, specialty,
  // experience, photo and the verification DOCUMENTS all move to Complete
  // Profile (items 2 and 4) — documents are required there before an admin can
  // approve the coach. `documents` is still accepted here for older builds.
  const { email, phone, password, firstName, lastName, nationality, documents } = req.body || {};
  if (!email || !phone || !validPassword(password) || !firstName || !lastName || !nationality)
    return res.status(400).json({ error: 'firstName, lastName, email, phone, password (min 8) and nationality are required' });
  if (!validEmail(email)) return res.status(400).json({ error: 'Invalid email format' });
  const normPhone = normalizePhone(phone);
  if (!normPhone) return res.status(400).json({ error: 'Phone must be 10 digits starting with 0 (e.g. 0791234567)' });

  const docs = Array.isArray(documents) ? documents : [];
  for (const d of docs) {
    if (!d || !d.dataBase64 || !ALLOWED_DOC_MIME[d.mimeType])
      return res.status(400).json({ error: 'Documents must be PDF, Word, JPG or PNG' });
    if (Buffer.from(d.dataBase64, 'base64').length > MAX_DOC_BYTES)
      return res.status(400).json({ error: 'Each document must be 10 MB or smaller' });
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
        `INSERT INTO coach_profiles (user_id, first_name, last_name, nationality)
         VALUES ($1,$2,$3,$4)`,
        [user.id, firstName, lastName, nationality]
      );
      // Optional at signup now (item 1): documents are collected and REQUIRED
      // during Complete Profile (items 2, 4). Older app builds still post them
      // here, so they are accepted and validated.
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

// --- Resend email verification OTP ---
router.post('/resend-verification', async (req, res) => {
  const { userId } = req.body || {};

  if (!userId) {
    return res.status(400).json({ error: 'userId required' });
  }

  try {
    const u = await pool.query(
      `SELECT id, email, email_verified
         FROM users
        WHERE id=$1
          AND role IN ('member', 'coach')`,
      [userId]
    );

    if (u.rowCount === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (u.rows[0].email_verified) {
      return res.json({
        message: 'Email is already verified.'
      });
    }

    // Invalidate all previous unused verification codes.
    await pool.query(
      `UPDATE otp_verifications
          SET consumed_at=now()
        WHERE user_id=$1
          AND consumed_at IS NULL`,
      [userId]
    );

    // Generate and email a fresh OTP.
    const otp = await issueOtp(userId);

    res.json({
      message: 'A new verification code has been sent to your email.',
      devOtp: DEV_OTP ? otp : undefined,
    });
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

// (v0.14 item 6) Contact details for the Contact Us screen. Public so the
// screen works before sign-in; the admin edits these from Setup.
router.get('/contact', async (req, res) => {
  const r = await pool.query(
    `SELECT contact_email, contact_phone, contact_instagram, contact_whatsapp
       FROM platform_settings WHERE id=1`);
  const c = r.rows[0] || {};
  res.json({
    email: c.contact_email || '',
    phone: c.contact_phone || '',
    instagram: c.contact_instagram || '',
    whatsapp: c.contact_whatsapp || '',
  });
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

  // (v0.14 item 10) Branded HTML email with a plain-text fallback.
  await sendCodeEmail({ to: user.email, code, kind: 'reset', minutes: RESET_TTL_MIN });
  if (DEV_OTP) console.log(`[DEV RESET] ${user.email} code = ${code}`);
  res.json({ message: RESET_NEUTRAL, devCode: DEV_OTP ? code : undefined });
});

// Step 2 of forgot-password flow:
// verify the OTP first, then issue a short-lived reset token.
router.post('/verify-reset-code', async (req, res) => {
  const { email, code } = req.body || {};
  const INVALID = { error: 'Invalid or expired code' };

  if (!email || !code || !validEmail(email)) {
    return res.status(400).json(INVALID);
  }

  try {
    const u = await pool.query(
      `SELECT id
         FROM users
        WHERE email=$1
          AND role IN ('member','coach')`,
      [email]
    );

    if (u.rowCount === 0) {
      return res.status(400).json(INVALID);
    }

    const r = await pool.query(
      `SELECT *
         FROM password_resets
        WHERE user_id=$1
          AND consumed_at IS NULL
          AND expires_at > now()
        ORDER BY created_at DESC
        LIMIT 1`,
      [u.rows[0].id]
    );

    if (r.rowCount === 0) {
      return res.status(400).json(INVALID);
    }

    const reset = r.rows[0];

    if (reset.attempts >= RESET_MAX_ATTEMPTS) {
      return res.status(400).json(INVALID);
    }

    const ok = await bcrypt.compare(
      String(code).toUpperCase(),
      reset.code_hash
    );

    if (!ok) {
      await pool.query(
        `UPDATE password_resets
            SET attempts = attempts + 1
          WHERE id=$1`,
        [reset.id]
      );

      return res.status(400).json(INVALID);
    }

    // Code is correct. Do NOT change the password yet.
    // Give the app a short-lived token allowing the next step.
    const resetToken = jwt.sign(
      {
        purpose: 'password-reset',
        userId: u.rows[0].id,
        resetId: reset.id,
      },
      JWT_SECRET,
      { expiresIn: '10m' }
    );

    res.json({
      verified: true,
      resetToken,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});


// Step 3 of forgot-password flow:
// password can only be changed after OTP verification.
router.post('/reset-password', async (req, res) => {
  const { resetToken, newPassword, confirmPassword } = req.body || {};

  if (!resetToken || !newPassword || !confirmPassword) {
    return res.status(400).json({
      error: 'resetToken, newPassword and confirmPassword required'
    });
  }

  if (newPassword !== confirmPassword) {
    return res.status(400).json({
      error: 'New password and confirmation do not match'
    });
  }

  if (!validPassword(newPassword)) {
    return res.status(400).json({
      error: 'New password must be at least 8 characters'
    });
  }

  let payload;

  try {
    payload = jwt.verify(resetToken, JWT_SECRET);
  } catch (_) {
    return res.status(400).json({
      error: 'Reset session expired. Please request a new code.'
    });
  }

  if (
    payload.purpose !== 'password-reset' ||
    !payload.userId ||
    !payload.resetId
  ) {
    return res.status(400).json({
      error: 'Invalid reset session'
    });
  }

  try {
    // Make sure this reset request is still valid and unused.
    const r = await pool.query(
      `SELECT id
         FROM password_resets
        WHERE id=$1
          AND user_id=$2
          AND consumed_at IS NULL
          AND expires_at > now()`,
      [payload.resetId, payload.userId]
    );

    if (r.rowCount === 0) {
      return res.status(400).json({
        error: 'Reset session expired. Please request a new code.'
      });
    }

    const hash = await bcrypt.hash(newPassword, 10);

    await withTransaction(async (client) => {
      await client.query(
        `UPDATE users
            SET password_hash=$2,
                updated_at=now()
          WHERE id=$1`,
        [payload.userId, hash]
      );

      await client.query(
        `UPDATE password_resets
            SET consumed_at=now()
          WHERE id=$1`,
        [payload.resetId]
      );
    });

    res.json({ reset: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
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
    sendCodeEmail({ to: u.rows[0].email, code, kind: 'verify' });
  }
  return code;
}

module.exports = router;
