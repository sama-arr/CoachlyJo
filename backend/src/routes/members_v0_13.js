const express = require('express');
const { pool } = require('../db/pool_v0_13');
const { authenticate, requireRole } = require('../middleware/auth_v0_13');
const { notifyAdmins } = require('../services/notification.service_v0_13');

const router = express.Router();

// Search approved coaches (spec §3.3, §4.1). Optional ?q= name filter.
router.get('/coaches', authenticate, async (req, res) => {
  const q = `%${(req.query.q || '').toLowerCase()}%`;
  const r = await pool.query(
    `SELECT user_id, first_name, last_name, nationality, bio_en, bio_ar, avg_rating, rating_count
       FROM coach_profiles
      WHERE status='approved'
        AND (LOWER(first_name) LIKE $1 OR LOWER(last_name) LIKE $1)
      ORDER BY avg_rating DESC`,
    [q]
  );
  res.json(r.rows);
});

// Public-ish coach profile + reviews for the member's Coaches tab (item 6).
router.get('/coaches/:coachId/profile', authenticate, async (req, res) => {
  const c = await pool.query(
    `SELECT user_id, first_name, last_name, nationality, bio_en, bio_ar, avg_rating, rating_count
       FROM coach_profiles WHERE user_id=$1 AND status='approved'`,
    [req.params.coachId]
  );
  if (c.rowCount === 0) return res.status(404).json({ error: 'Coach not found' });
  const reviews = await pool.query(
    `SELECT r.rating, r.comment, r.created_at, mp.first_name AS member_first
       FROM reviews r JOIN member_profiles mp ON mp.user_id=r.member_id
      WHERE r.coach_id=$1 ORDER BY r.created_at DESC LIMIT 50`,
    [req.params.coachId]
  );
  res.json({ coach: c.rows[0], reviews: reviews.rows });
});

// Available upcoming sessions for a coach.
// If the member has a usable active package with this coach,
// only show sessions that match the package mode:
// online package -> online sessions only
// in-person package -> in-person sessions only.
router.get('/coaches/:coachId/sessions', authenticate, async (req, res) => {
  const coachId = req.params.coachId;

  // Find the member's currently usable package with this coach.
  const pkg = await pool.query(
    `SELECT mode
       FROM member_packages
      WHERE member_id = $1
        AND coach_id = $2
        AND status = 'active'
        AND (expires_at IS NULL OR expires_at > now())
        AND (classes_total - classes_consumed - classes_pending) > 0
      ORDER BY is_single DESC, expires_at ASC NULLS LAST
      LIMIT 1`,
    [req.user.id, coachId]
  );

  // If there is no usable package yet, show both session types.
  // Once a package is active, only show the matching delivery mode.
  const packageMode = pkg.rowCount > 0 ? pkg.rows[0].mode : null;

  const r = await pool.query(
    `SELECT cs.*,
            (
              SELECT COUNT(*)
                FROM bookings b
               WHERE b.session_id = cs.id
                 AND b.status IN ('pending', 'accepted', 'completed')
            ) AS booked
       FROM coach_sessions cs
      WHERE cs.coach_id = $1
        AND cs.start_at > now()
        AND ($2::text IS NULL OR cs.delivery::text = $2::text)
        AND NOT EXISTS (
              SELECT 1
                FROM bookings b
               WHERE b.session_id = cs.id
                 AND b.status IN ('pending', 'accepted', 'completed')
            )
      ORDER BY cs.start_at`,
    [coachId, packageMode]
  );

  res.json(
    r.rows.map((s) => ({
      ...s,
      seats_left: s.capacity - Number(s.booked),
    }))
  );
});

// The catalogue of packages the member can request (spec §9.1) — split by mode (item 8).
router.get('/packages/catalogue', authenticate, async (req, res) => {
  const r = await pool.query(
    `SELECT * FROM package_definitions
      WHERE is_active = TRUE AND is_archived = FALSE
      ORDER BY is_single DESC, mode, class_count`
  );
  res.json(r.rows);
});

// Member's own packages with derived counters, coach, proof status (items 6, 7, 9).
router.get('/packages/mine', authenticate, requireRole('member'), async (req, res) => {
  // (v0.6 item 1) ?scope=active|past — packages are never deleted; the app
  // shows Active up front and Past (exhausted / expired / cancelled) in a
  // collapsed history section. A package is "past" when it is cancelled,
  // fully consumed, or its expiry date has passed. No scope returns all.
  const scope = req.query.scope;
  const PAST = `(mp.status = 'cancelled'
                 OR mp.classes_consumed >= mp.classes_total
                 OR (mp.expires_at IS NOT NULL AND mp.expires_at <= now()))`;
  const scopeSql = scope === 'active' ? `AND NOT ${PAST}`
                 : scope === 'past' ? `AND ${PAST}`
                 : '';
  const r = await pool.query(
    `SELECT mp.id, mp.status, mp.mode, mp.is_single, mp.classes_total, mp.classes_pending,
            mp.price, mp.currency, mp.requested_at, mp.activated_at, mp.expires_at,
            pd.name_en, pd.name_ar,
            (mp.classes_total - mp.classes_consumed) AS remaining,
            mp.classes_pending AS pending,
            mp.coach_id, cp.first_name AS coach_first, cp.last_name AS coach_last,
            (mp.proof_content IS NOT NULL) AS has_proof,
            mp.proof_uploaded_at, mp.payment_rejection_reason
       FROM member_packages mp
       JOIN package_definitions pd ON pd.id=mp.package_def_id
       LEFT JOIN coach_profiles cp ON cp.user_id=mp.coach_id
      WHERE mp.member_id=$1 ${scopeSql} ORDER BY mp.requested_at DESC`,
    [req.user.id]
  );
  res.json(r.rows);
});

// (v0.5 item 2) Bank/payment details shown BEFORE the proof upload.
router.get('/payment-note', authenticate, async (req, res) => {
  const r = await pool.query(`SELECT body_en, body_ar FROM payment_notes WHERE id=1`);
  res.json(r.rows[0] || { body_en: '', body_ar: '' });
});

// (item 6) Proof-of-payment images: jpg/png only, 10MB cap.
const ALLOWED_PROOF_MIME = { 'image/jpeg': true, 'image/png': true };
const MAX_PROOF_BYTES = 10 * 1024 * 1024;

function validateProof(proof) {
  if (!proof || !proof.dataBase64 || !proof.mimeType)
    return 'Proof of payment image is required (mimeType + dataBase64)';
  if (!ALLOWED_PROOF_MIME[proof.mimeType])
    return `Unsupported proof type ${proof.mimeType}. Allowed: jpg, png`;
  if (Buffer.byteLength(proof.dataBase64, 'base64') > MAX_PROOF_BYTES)
    return 'Proof image exceeds 10MB';
  return null;
}

// Member requests a package FOR A SPECIFIC COACH (item 7), attaching proof of
// payment (item 6) -> creates pending_payment row, returns payment note.
router.post('/packages/request', authenticate, requireRole('member'), async (req, res) => {
  const { packageDefId, coachId, proof } = req.body || {};
  if (!packageDefId) return res.status(400).json({ error: 'packageDefId required' });
  if (!coachId) return res.status(400).json({ error: 'coachId required — packages are purchased for a specific coach' });
  const proofErr = validateProof(proof);
  if (proofErr) return res.status(400).json({ error: proofErr });

  const def = await pool.query(`SELECT * FROM package_definitions WHERE id=$1 AND is_active=TRUE`, [packageDefId]);
  if (def.rowCount === 0) return res.status(404).json({ error: 'Package not found' });
  const d = def.rows[0];

  const coach = await pool.query(`SELECT status FROM coach_profiles WHERE user_id=$1`, [coachId]);
  if (coach.rowCount === 0 || coach.rows[0].status !== 'approved')
    return res.status(404).json({ error: 'Coach not found or not approved' });

  // (item 3) The paid single session is a one-time trial PER COACH, permanent.
  // A cancelled/rejected request does not consume the allowance.
  if (d.is_single) {
    const had = await pool.query(
      `SELECT 1 FROM member_packages
        WHERE member_id=$1 AND coach_id=$2 AND is_single=TRUE AND status <> 'cancelled' LIMIT 1`,
      [req.user.id, coachId]
    );
    if (had.rowCount > 0)
      return res.status(409).json({ error: 'You already used your single trial session with this coach. Please choose a package.' });
  }

  // (item 7) One concurrent USABLE purchase per coach: pending/active and not
  // yet exhausted. A finished package doesn't block buying the next one.
  const concurrent = await pool.query(
    `SELECT 1 FROM member_packages
      WHERE member_id=$1 AND coach_id=$2 AND status IN ('pending_payment','active')
        AND classes_consumed < classes_total LIMIT 1`,
    [req.user.id, coachId]
  );
  if (concurrent.rowCount > 0)
    return res.status(409).json({ error: 'You already have a pending or active package with this coach. Finish or wait for it before buying another.' });

  try {
    const ins = await pool.query(
      `INSERT INTO member_packages
         (member_id, package_def_id, coach_id, status, classes_total, validity_weeks, price, currency, mode, is_single,
          proof_content, proof_mime, proof_file_name, proof_uploaded_at)
       VALUES ($1,$2,$3,'pending_payment',$4,$5,$6,$7,$8,$9,$10,$11,$12,now())
       RETURNING id, member_id, package_def_id, coach_id, status, classes_total, validity_weeks,
                 price, currency, mode, is_single, requested_at, proof_uploaded_at`,
      [req.user.id, d.id, coachId, d.class_count, d.validity_weeks, d.price, d.currency, d.mode, d.is_single,
       Buffer.from(proof.dataBase64, 'base64'), proof.mimeType, proof.fileName || 'proof', ]
    );
    const note = await pool.query(`SELECT body_en, body_ar FROM payment_notes WHERE id=1`);
    // (v0.11) Admins see the new payment awaiting approval.
    const who = await pool.query(
      `SELECT first_name, last_name FROM member_profiles WHERE user_id=$1`, [req.user.id]);
    const w = who.rows[0] || {};
    await notifyAdmins({
      type: 'admin_new_package_request',
      titleEn: 'New package awaiting payment approval',
      titleAr: 'باقة جديدة بانتظار تأكيد الدفع',
      bodyEn: `${w.first_name} ${w.last_name} submitted proof of payment.`,
      bodyAr: `أرسل ${w.first_name} ${w.last_name} إثبات الدفع.`,
      relatedId: ins.rows[0].id,
      email: true,
    });
    res.status(201).json({ package: ins.rows[0], paymentNote: note.rows[0] });
  } catch (err) {
    // Unique-index backstops (uq_single_per_coach / uq_concurrent_pkg_per_coach).
    if (err.code === '23505')
      return res.status(409).json({ error: 'You already have a package or trial with this coach.' });
    throw err;
  }
});

// (item 6) Re-upload proof after an admin rejection. Clears the rejection reason.
router.post('/packages/:id/proof', authenticate, requireRole('member'), async (req, res) => {
  const { proof } = req.body || {};
  const proofErr = validateProof(proof);
  if (proofErr) return res.status(400).json({ error: proofErr });
  const r = await pool.query(
    `UPDATE member_packages
        SET proof_content=$3, proof_mime=$4, proof_file_name=$5, proof_uploaded_at=now(),
            payment_rejection_reason=NULL, payment_rejected_at=NULL
      WHERE id=$1 AND member_id=$2 AND status='pending_payment'
      RETURNING id, status, proof_uploaded_at`,
    [req.params.id, req.user.id, Buffer.from(proof.dataBase64, 'base64'), proof.mimeType, proof.fileName || 'proof']
  );
  if (r.rowCount === 0) return res.status(409).json({ error: 'Package not found or no longer awaiting payment' });
  res.json(r.rows[0]);
});

// Member's profile + assessment.
router.get('/profile', authenticate, requireRole('member'), async (req, res) => {
  const p = await pool.query(`SELECT * FROM member_profiles WHERE user_id=$1`, [req.user.id]);
  const a = await pool.query(`SELECT responses, submitted_at FROM fitness_assessments WHERE member_id=$1 ORDER BY submitted_at DESC LIMIT 1`, [req.user.id]);
  res.json({ profile: p.rows[0] || null, assessment: a.rows[0] || null });
});

// Member's bookings — includes a reviewed flag so the UI can hide the button (item 5).
router.get('/bookings', authenticate, requireRole('member'), async (req, res) => {
  // (v0.6 item 2) ?scope=upcoming|history. Upcoming = pending/accepted with a
  // future start. History = everything else (completed, cancelled, rejected,
  // and past-dated) — kept forever, shown in a collapsed section in the app.
  const scope = req.query.scope;
  const UPCOMING = `(b.status IN ('pending','accepted') AND cs.start_at > now())`;
  const scopeSql = scope === 'upcoming' ? `AND ${UPCOMING}`
                 : scope === 'history' ? `AND NOT ${UPCOMING}`
                 : '';
  const r = await pool.query(
    `SELECT b.id, b.status, b.is_trial, b.rejection_reason, b.completion_kind,
            b.cancelled_by, b.member_package_id,
            (SELECT COUNT(*)::int FROM bookings x
              WHERE x.member_package_id = b.member_package_id AND x.status='cancelled'
                AND (x.cancelled_by='member' OR x.cancelled_by IS NULL)) AS pkg_cancels_used,
            cs.start_at, cs.delivery,
            CASE WHEN b.status='accepted' THEN cs.zoom_join_url END AS zoom_join_url,
            cp.first_name AS coach_first, cp.last_name AS coach_last,
            EXISTS (SELECT 1 FROM reviews r WHERE r.booking_id=b.id) AS reviewed
       FROM bookings b
       JOIN coach_sessions cs ON cs.id=b.session_id
       JOIN coach_profiles cp ON cp.user_id=cs.coach_id
      WHERE b.member_id=$1 ${scopeSql}
      ORDER BY cs.start_at ${scope === 'upcoming' ? 'ASC' : 'DESC'}`,
    [req.user.id]
  );
  res.json(r.rows);
});

module.exports = router;
