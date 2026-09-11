// =============================================================================
// Notification centre API (v0.11 item 2).
// Any signed-in user reads their own notifications; nobody can read another's.
// =============================================================================
const express = require('express');
const { pool } = require('../db/pool_v0_13');
const { authenticate } = require('../middleware/auth_v0_13');

const router = express.Router();

// List notifications, newest first. ?unread=true for the badge list only.
router.get('/', authenticate, async (req, res) => {
  const unreadOnly = req.query.unread === 'true';
  const limit = Math.min(parseInt(req.query.limit || '50', 10), 100);
  const r = await pool.query(
    `SELECT id, type, title_en, title_ar, body_en, body_ar, related_id,
            created_at, read_at
       FROM notifications
      WHERE user_id = $1 ${unreadOnly ? 'AND read_at IS NULL' : ''}
      ORDER BY created_at DESC
      LIMIT ${limit}`,
    [req.user.id]
  );
  const unread = await pool.query(
    `SELECT COUNT(*)::int AS n FROM notifications WHERE user_id=$1 AND read_at IS NULL`,
    [req.user.id]
  );
  res.json({ unread: unread.rows[0].n, items: r.rows });
});

// Unread badge count only (cheap, polled by the app).
router.get('/unread-count', authenticate, async (req, res) => {
  const r = await pool.query(
    `SELECT COUNT(*)::int AS n FROM notifications WHERE user_id=$1 AND read_at IS NULL`,
    [req.user.id]
  );
  res.json({ unread: r.rows[0].n });
});

router.post('/:id/read', authenticate, async (req, res) => {
  const r = await pool.query(
    `UPDATE notifications SET read_at = now()
      WHERE id = $1 AND user_id = $2 AND read_at IS NULL RETURNING id`,
    [req.params.id, req.user.id]
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'Notification not found or already read' });
  res.json({ read: r.rows[0].id });
});

router.post('/read-all', authenticate, async (req, res) => {
  const r = await pool.query(
    `UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL RETURNING id`,
    [req.user.id]
  );
  res.json({ read: r.rowCount });
});

router.delete('/:id', authenticate, async (req, res) => {
  const r = await pool.query(
    `DELETE FROM notifications WHERE id=$1 AND user_id=$2 RETURNING id`,
    [req.params.id, req.user.id]
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'Notification not found' });
  res.json({ deleted: r.rows[0].id });
});

module.exports = router;
