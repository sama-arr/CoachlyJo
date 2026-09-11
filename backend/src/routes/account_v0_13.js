// =============================================================================
// Account routes (v0.13) — store-compliance endpoints.
//   * DELETE /api/account            in-app account deletion (Apple + Google)
//   * POST   /api/account/request-deletion   public web request (Google)
//   * GET    /api/account/legal      privacy policy + terms, no login needed
// =============================================================================
const express = require('express');
const bcrypt = require('bcryptjs');
const { pool } = require('../db/pool_v0_13');
const { authenticate } = require('../middleware/auth_v0_13');
const { deleteAccount, DeletionError } = require('../services/account.service_v0_13');

const router = express.Router();

// Public: the privacy policy and terms, in both languages. Reviewers open this
// before signing in, and it backs the public policy URL on the store listing.
router.get('/legal', async (req, res) => {
  const r = await pool.query(
    `SELECT key, title_en, title_ar, body_en, body_ar, sort_order, updated_at
       FROM content_blocks
      WHERE kind = 'legal' AND is_active = TRUE
      ORDER BY sort_order`);
  res.json(r.rows);
});

// What deleting will cost the user — shown in the confirmation dialog so the
// decision is informed rather than a surprise.
router.get('/deletion-preview', authenticate, async (req, res) => {
  const upcoming = await pool.query(
    `SELECT COUNT(*)::int AS n FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
      WHERE b.status IN ('pending','accepted') AND cs.start_at > now()
        AND (b.member_id=$1 OR cs.coach_id=$1)`, [req.user.id]);
  const packages = await pool.query(
    `SELECT COALESCE(SUM(classes_total - classes_consumed), 0)::int AS classes,
            COUNT(*)::int AS n
       FROM member_packages
      WHERE member_id=$1 AND status='active' AND classes_consumed < classes_total`, [req.user.id]);
  res.json({
    role: req.user.role,
    upcomingSessions: upcoming.rows[0].n,
    activePackages: packages.rows[0].n,
    unusedClasses: packages.rows[0].classes,
  });
});

// In-app deletion. Password confirmation prevents someone wiping an account
// left unlocked on a phone.
router.delete('/', authenticate, async (req, res) => {
  const { password, reason } = req.body || {};
  if (!password) return res.status(400).json({ error: 'Your password is required to delete the account' });

  const u = await pool.query(`SELECT password_hash FROM users WHERE id=$1`, [req.user.id]);
  if (u.rowCount === 0) return res.status(404).json({ error: 'Account not found' });
  const ok = await bcrypt.compare(password, u.rows[0].password_hash);
  if (!ok) return res.status(401).json({ error: 'Incorrect password' });

  try {
    const result = await deleteAccount(req.user.id, 'user', reason || null);
    res.json({ ...result, message: 'Your account and personal data have been deleted.' });
  } catch (err) {
    if (err instanceof DeletionError) return res.status(err.status).json({ error: err.message });
    throw err;
  }
});

// Public web request (Google Play requires a route that works without the app).
// We never confirm whether the email exists — same neutral pattern as the
// password reset — and an admin completes the deletion after verifying.
router.post('/request-deletion', async (req, res) => {
  const { email, note } = req.body || {};
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))
    return res.status(400).json({ error: 'A valid email address is required' });
  await pool.query(
    `INSERT INTO deletion_requests (email, note) VALUES ($1, $2)`,
    [String(email).toLowerCase().trim(), (note || '').slice(0, 500)]);
  res.json({
    message: 'Your deletion request has been received. We will process it and confirm by email within 30 days.',
  });
});

module.exports = router;
