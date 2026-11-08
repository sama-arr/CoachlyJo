// =============================================================================
// Profile completion (v0.14 items 2, 4, 11).
//
// Registration now asks only for name, email, phone, password and nationality.
// Everything else is collected here, in the app, where people have already
// committed to an account and are far less likely to abandon the form.
//
//   Members  -> date of birth, area of Amman, fitness questionnaire
//   Coaches  -> date of birth, years of experience, specialties, bio,
//               verification documents (REQUIRED, item 4) and an optional photo
//
// GET /status drives the "Complete profile" tab: it reports what is missing so
// the app can gate booking and purchasing until the profile is done, and tell
// the user exactly what is still needed rather than a vague "incomplete".
// =============================================================================
const express = require('express');
const { pool, withTransaction } = require('../db/pool_v0_13');
const { authenticate, requireRole } = require('../middleware/auth_v0_13');

const router = express.Router();

const ALLOWED_DOC_MIME = {
  'application/pdf': true,
  'application/msword': true,
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': true,
  'image/jpeg': true,
  'image/png': true,
};
const MAX_DOC_BYTES = 10 * 1024 * 1024;
const ALLOWED_PHOTO_MIME = { 'image/jpeg': true, 'image/png': true };
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

/**
 * What is still missing from this account's profile.
 * Returns { complete, missing: [...], ...context } for the app to act on.
 */
async function profileStatus(userId, role) {
  if (role === 'member') {
    const p = await pool.query(
      `SELECT first_name, last_name, date_of_birth, location, nationality, profile_completed_at
         FROM member_profiles WHERE user_id = $1`, [userId]);
    if (p.rowCount === 0) return { complete: false, missing: ['profile'] };
    const row = p.rows[0];
    const a = await pool.query(
      `SELECT COUNT(*)::int AS n FROM fitness_assessments WHERE member_id = $1`, [userId]);

    const missing = [];
    if (!row.date_of_birth) missing.push('dateOfBirth');
    if (!row.location) missing.push('location');
    if (!row.nationality) missing.push('nationality');
    if (a.rows[0].n === 0) missing.push('questionnaire');
    return {
      role: 'member',
      complete: missing.length === 0,
      missing,
      completedAt: row.profile_completed_at,
    };
  }

  const p = await pool.query(
    `SELECT first_name, last_name, date_of_birth, nationality, bio_en,
            years_experience, specialties, status, rejection_reason,
            (photo_content IS NOT NULL) AS has_photo, profile_completed_at
       FROM coach_profiles WHERE user_id = $1`, [userId]);
  if (p.rowCount === 0) return { complete: false, missing: ['profile'] };
  const row = p.rows[0];
  const docs = await pool.query(
    `SELECT COUNT(*)::int AS n FROM coach_documents WHERE coach_id = $1`, [userId]);

  const missing = [];
  if (!row.date_of_birth) missing.push('dateOfBirth');
  if (!row.nationality) missing.push('nationality');
  if (row.years_experience === null || row.years_experience === undefined) missing.push('yearsExperience');
  if (!row.specialties || row.specialties.length === 0) missing.push('specialties');
  if (docs.rows[0].n === 0) missing.push('documents');   // (item 4) required

  return {
    role: 'coach',
    complete: missing.length === 0,
    missing,
    completedAt: row.profile_completed_at,
    // (item 3) The app shows "Awaiting admin approval" and locks everything
    // else until this is 'approved'.
    approvalStatus: row.status,
    rejectionReason: row.rejection_reason,
    hasPhoto: row.has_photo,
    documentCount: docs.rows[0].n,
  };
}

router.get('/status', authenticate, async (req, res) => {
  res.json(await profileStatus(req.user.id, req.user.role));
});

// ---- Member completion -------------------------------------------------------
router.post('/member', authenticate, requireRole('member'), async (req, res) => {
  const { dateOfBirth, location, nationality, assessment } = req.body || {};
  if (!dateOfBirth) return res.status(400).json({ error: 'Date of birth is required' });
  if (!location) return res.status(400).json({ error: 'Please choose your area' });
  if (!assessment || Object.keys(assessment).length === 0)
    return res.status(400).json({ error: 'Please answer the fitness questions' });

  await withTransaction(async (client) => {
    await client.query(
      `UPDATE member_profiles
          SET date_of_birth = $2,
              location = $3,
              nationality = COALESCE($4, nationality),
              profile_completed_at = now()
        WHERE user_id = $1`,
      [req.user.id, dateOfBirth, location, nationality || null]);
    // Keep one assessment per member: the latest answers replace the old ones.
    await client.query(`DELETE FROM fitness_assessments WHERE member_id = $1`, [req.user.id]);
    await client.query(
      `INSERT INTO fitness_assessments (member_id, responses) VALUES ($1, $2)`,
      [req.user.id, assessment]);
  });

  res.json(await profileStatus(req.user.id, 'member'));
});

// ---- Coach completion --------------------------------------------------------
// (item 11) Experience and specialties are used to compose the bio automatically
// when the coach has not written one; they can edit it afterwards.
function composeBio({ firstName, years, specialties, existing }) {
  if (existing && existing.trim().length > 0) return existing;
  const spec = (specialties || []).filter(Boolean);
  const specText = spec.length === 0 ? ''
    : spec.length === 1 ? spec[0]
    : `${spec.slice(0, -1).join(', ')} and ${spec[spec.length - 1]}`;
  const yearText = years === 1 ? '1 year of experience' : `${years} years of experience`;
  if (specText) return `${firstName} is a certified coach with ${yearText}, specialising in ${specText}.`;
  return `${firstName} is a certified coach with ${yearText}.`;
}

function composeBioAr({ firstName, years, specialties, existing }) {
  if (existing && existing.trim().length > 0) return existing;
  const spec = (specialties || []).filter(Boolean);
  const specText = spec.join('، ');
  const yearText = `${years} ${years === 1 ? 'سنة' : 'سنوات'} من الخبرة`;
  if (specText) return `${firstName} مدرب معتمد لديه ${yearText}، متخصص في ${specText}.`;
  return `${firstName} مدرب معتمد لديه ${yearText}.`;
}

router.post('/coach', authenticate, requireRole('coach'), async (req, res) => {
  const { dateOfBirth, nationality, yearsExperience, specialties, bio, bioAr, documents } = req.body || {};
  if (!dateOfBirth) return res.status(400).json({ error: 'Date of birth is required' });
  const years = parseInt(yearsExperience, 10);
  if (!Number.isInteger(years) || years < 0 || years > 70)
    return res.status(400).json({ error: 'Please enter your years of experience' });
  const specs = Array.isArray(specialties) ? specialties.map((x) => String(x).trim()).filter(Boolean) : [];
  if (specs.length === 0) return res.status(400).json({ error: 'Please choose at least one specialty' });

  const docs = Array.isArray(documents) ? documents : [];
  const existingDocs = await pool.query(
    `SELECT COUNT(*)::int AS n FROM coach_documents WHERE coach_id = $1`, [req.user.id]);
  // (item 4) Documents are mandatory — the admin cannot verify a coach without them.
  if (docs.length === 0 && existingDocs.rows[0].n === 0)
    return res.status(400).json({ error: 'Please upload at least one certificate or proof of experience' });

  for (const d of docs) {
    if (!d || !d.dataBase64 || !ALLOWED_DOC_MIME[d.mimeType])
      return res.status(400).json({ error: 'Documents must be PDF, Word, JPG or PNG' });
    if (Buffer.from(d.dataBase64, 'base64').length > MAX_DOC_BYTES)
      return res.status(400).json({ error: 'Each document must be 10 MB or smaller' });
  }

  const current = await pool.query(
    `SELECT first_name, bio_en, bio_ar FROM coach_profiles WHERE user_id = $1`, [req.user.id]);
  const firstName = current.rows[0]?.first_name || 'This coach';

  await withTransaction(async (client) => {
    await client.query(
      `UPDATE coach_profiles
          SET date_of_birth = $2,
              nationality = COALESCE($3, nationality),
              years_experience = $4,
              specialties = $5,
              bio_en = $6,
              bio_ar = $7,
              profile_completed_at = now()
        WHERE user_id = $1`,
      [
        req.user.id, dateOfBirth, nationality || null, years, specs,
        composeBio({ firstName, years, specialties: specs, existing: bio }),
        composeBioAr({ firstName, years, specialties: specs, existing: bioAr }),
      ]);
    for (const d of docs) {
      const buf = Buffer.from(d.dataBase64, 'base64');
      await client.query(
        `INSERT INTO coach_documents (coach_id, doc_type, content, mime_type, file_name, byte_size)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [req.user.id, d.docType || 'other', buf, d.mimeType, d.fileName || 'document', buf.length]);
    }
  });

  res.json(await profileStatus(req.user.id, 'coach'));
});

// ---- Coach profile photo (optional, item 11) ---------------------------------
router.post('/coach/photo', authenticate, requireRole('coach'), async (req, res) => {
  const { mimeType, dataBase64 } = req.body || {};
  if (!dataBase64 || !ALLOWED_PHOTO_MIME[mimeType])
    return res.status(400).json({ error: 'Photo must be a JPG or PNG image' });
  const buf = Buffer.from(dataBase64, 'base64');
  if (buf.length > MAX_PHOTO_BYTES)
    return res.status(400).json({ error: 'Photo must be 5 MB or smaller' });

  await pool.query(
    `UPDATE coach_profiles SET photo_content=$2, photo_mime=$3, photo_updated_at=now()
      WHERE user_id=$1`, [req.user.id, buf, mimeType]);
  res.json({ saved: true });
});

router.delete('/coach/photo', authenticate, requireRole('coach'), async (req, res) => {
  await pool.query(
    `UPDATE coach_profiles SET photo_content=NULL, photo_mime=NULL, photo_updated_at=NULL
      WHERE user_id=$1`, [req.user.id]);
  res.json({ removed: true });
});

// Public photo fetch — any signed-in user can see an approved coach's photo.
router.get('/coach/:coachId/photo', authenticate, async (req, res) => {
  const r = await pool.query(
    `SELECT photo_content, photo_mime FROM coach_profiles WHERE user_id=$1`, [req.params.coachId]);
  if (r.rowCount === 0 || !r.rows[0].photo_content)
    return res.status(404).json({ error: 'No photo' });
  res.setHeader('Content-Type', r.rows[0].photo_mime || 'image/jpeg');
  res.setHeader('Cache-Control', 'private, max-age=3600');
  res.send(r.rows[0].photo_content);
});

// ---- Theme preference (item 12) ----------------------------------------------
router.put('/theme', authenticate, async (req, res) => {
  const { theme } = req.body || {};
  if (!['system', 'light', 'dark'].includes(theme))
    return res.status(400).json({ error: 'theme must be system, light or dark' });
  await pool.query(`UPDATE users SET theme_pref=$2 WHERE id=$1`, [req.user.id, theme]);
  res.json({ theme });
});

module.exports = { router, profileStatus };
