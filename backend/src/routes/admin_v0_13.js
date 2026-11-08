const express = require('express');
const { pool } = require('../db/pool_v0_13');
const { authenticate, authenticateAllowQueryToken, requireRole } = require('../middleware/auth_v0_13');
const { regenerateForCoach } = require('../services/schedule.service_v0_13');
const { notify } = require('../services/notification.service_v0_13');
const { deleteAccount, DeletionError } = require('../services/account.service_v0_13');

const router = express.Router();

// ---- Binary downloads (mounted BEFORE the global header-auth middleware) ----
// These accept ?token= in addition to the Authorization header so the Flutter
// client can hand the URL to an external viewer (PDF/doc apps, browser) that
// cannot set headers. Still admin-only.

// (item 1) Download/view a coach's uploaded document (binary).
router.get('/documents/:docId/download', authenticateAllowQueryToken, requireRole('admin'), async (req, res) => {
  const r = await pool.query(`SELECT content, mime_type, file_name FROM coach_documents WHERE id=$1`, [req.params.docId]);
  if (r.rowCount === 0 || !r.rows[0].content) return res.status(404).json({ error: 'Document not found' });
  res.setHeader('Content-Type', r.rows[0].mime_type || 'application/octet-stream');
  res.setHeader('Content-Disposition', `inline; filename="${r.rows[0].file_name || 'document'}"`);
  res.send(r.rows[0].content);
});

router.use(authenticate, requireRole('admin'));

// ---- Coach approval (spec §4.4, §7.1) ----
router.get('/coaches/pending', async (req, res) => {
  const r = await pool.query(
    `SELECT cp.*, u.email, u.phone,
            (SELECT json_agg(json_build_object('id',cd.id,'docType',cd.doc_type,'fileName',cd.file_name,'mimeType',cd.mime_type,'byteSize',cd.byte_size))
               FROM coach_documents cd WHERE cd.coach_id=cp.user_id) AS documents
       FROM coach_profiles cp JOIN users u ON u.id=cp.user_id
      WHERE cp.status='pending' ORDER BY cp.created_at`
  );
  res.json(r.rows);
});

router.post('/coaches/:id/approve', async (req, res) => {
  await pool.query(`UPDATE coach_documents SET verified=TRUE WHERE coach_id=$1`, [req.params.id]);
  const r = await pool.query(
    `UPDATE coach_profiles SET status='approved', approved_by=$2, approved_at=now() WHERE user_id=$1 RETURNING *`,
    [req.params.id, req.user.id]
  );
  // v0.5: availability saved before approval materializes into sessions now.
  await regenerateForCoach(req.params.id);
  await notify({
    userId: req.params.id,
    type: 'coach_approved',
    titleEn: 'Your coach account is approved',
    titleAr: 'تمت الموافقة على حسابك كمدرب',
    bodyEn: 'Welcome to CoachlyJo. Set your weekly hours in the Availability tab so members can book you.',
    bodyAr: 'أهلاً بك في كوتشلي جو. حدّد ساعاتك الأسبوعية في صفحة الأوقات المتاحة ليتمكن الأعضاء من الحجز معك.',
    email: true,
  });
  res.json(r.rows[0]);
});

router.post('/coaches/:id/reject', async (req, res) => {
  const { reason } = req.body || {};
  if (!reason) return res.status(400).json({ error: 'reason required' });
  const r = await pool.query(
    `UPDATE coach_profiles SET status='rejected', rejection_reason=$2 WHERE user_id=$1 RETURNING *`,
    [req.params.id, reason]
  );
  await notify({
    userId: req.params.id,
    type: 'coach_rejected',
    titleEn: 'Your coach application was not approved',
    titleAr: 'لم تتم الموافقة على طلبك كمدرب',
    bodyEn: `Reason: ${reason}`,
    bodyAr: `السبب: ${reason}`,
    email: true,
  });
  res.json(r.rows[0]);
});

// ---- Session grid config (spec §5.1) ----
router.get('/settings', async (req, res) => {
  const r = await pool.query(`SELECT * FROM platform_settings WHERE id=1`);
  res.json(r.rows[0]);
});

router.put('/settings', async (req, res) => {
  const { weekStartDow, dayStartTime, dayEndTime, timezone, currency } = req.body || {};
  const r = await pool.query(
    `UPDATE platform_settings SET
       week_start_dow=COALESCE($1,week_start_dow),
       day_start_time=COALESCE($2,day_start_time),
       day_end_time=COALESCE($3,day_end_time),
       timezone=COALESCE($4,timezone),
       currency=COALESCE($5,currency),
       updated_at=now() WHERE id=1 RETURNING *`,
    [weekStartDow, dayStartTime, dayEndTime, timezone, currency]
  );
  res.json(r.rows[0]);
});

router.post('/slot-templates', async (req, res) => {
  const { dayOfWeek, startTime, duration, capacity, delivery } = req.body || {};
  if (dayOfWeek == null || !startTime || !duration || !capacity || !delivery)
    return res.status(400).json({ error: 'dayOfWeek, startTime, duration, capacity, delivery required' });
  const r = await pool.query(
    `INSERT INTO slot_templates (day_of_week, start_time, duration, capacity, delivery)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [dayOfWeek, startTime, String(duration), capacity, delivery]
  );
  res.status(201).json(r.rows[0]);
});

router.get('/slot-templates', async (req, res) => {
  const r = await pool.query(`SELECT * FROM slot_templates ORDER BY day_of_week, start_time`);
  res.json(r.rows);
});

// Toggle a template active/inactive (keeps history; existing sessions unaffected).
router.patch('/slot-templates/:id', async (req, res) => {
  const { isActive } = req.body || {};
  if (typeof isActive !== 'boolean') return res.status(400).json({ error: 'isActive (boolean) required' });
  const r = await pool.query(
    `UPDATE slot_templates SET is_active=$2 WHERE id=$1 RETURNING *`,
    [req.params.id, isActive]
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'Template not found' });
  res.json(r.rows[0]);
});

// Hard-delete a template only if no coach session has ever used it.
router.delete('/slot-templates/:id', async (req, res) => {
  const used = await pool.query(`SELECT 1 FROM coach_sessions WHERE template_id=$1 LIMIT 1`, [req.params.id]);
  if (used.rowCount > 0)
    return res.status(409).json({ error: 'Template is in use by sessions; deactivate it instead' });
  const r = await pool.query(`DELETE FROM slot_templates WHERE id=$1 RETURNING id`, [req.params.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Template not found' });
  res.json({ deleted: req.params.id });
});

// ---- Package config (spec §9.1, §9.2) — full CRUD (item 4) ----
router.get('/packages', async (req, res) => {
  const r = await pool.query(
    `SELECT pd.*,
            (SELECT COUNT(*)::int FROM member_packages mp WHERE mp.package_def_id = pd.id) AS purchases
       FROM package_definitions pd
      ORDER BY pd.is_archived, pd.is_single DESC, pd.mode, pd.class_count`);
  res.json(r.rows);
});

// (v0.11 item 1) Delete a package definition.
//   * never purchased -> deleted outright;
//   * has purchases   -> refused, with a hint to archive instead (archiving
//     hides it from the catalogue while existing purchases keep working).
// ?force=archive performs the archive in the same call, so the app can offer
// one button that always does the safe thing.
router.delete('/packages/:id', async (req, res) => {
  const used = await pool.query(
    `SELECT COUNT(*)::int AS n FROM member_packages WHERE package_def_id = $1`, [req.params.id]);
  const purchases = used.rows[0].n;

  if (purchases > 0) {
    if (req.query.force === 'archive') {
      const arch = await pool.query(
        `UPDATE package_definitions SET is_archived = TRUE, is_active = FALSE
          WHERE id = $1 RETURNING *`, [req.params.id]);
      if (arch.rowCount === 0) return res.status(404).json({ error: 'Package not found' });
      return res.json({ archived: true, purchases, package: arch.rows[0] });
    }
    return res.status(409).json({
      error: `This package has been purchased ${purchases} time(s), so it cannot be deleted — archiving hides it from members while their existing packages keep working.`,
      purchases,
      canArchive: true,
    });
  }

  const del = await pool.query(`DELETE FROM package_definitions WHERE id=$1 RETURNING id`, [req.params.id]);
  if (del.rowCount === 0) return res.status(404).json({ error: 'Package not found' });
  res.json({ deleted: del.rows[0].id, purchases: 0 });
});

// Restore an archived definition to the catalogue.
router.post('/packages/:id/restore', async (req, res) => {
  const r = await pool.query(
    `UPDATE package_definitions SET is_archived = FALSE, is_active = TRUE
      WHERE id=$1 RETURNING *`, [req.params.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Package not found' });
  res.json(r.rows[0]);
});

router.post('/packages', async (req, res) => {
  const { nameEn, nameAr, classCount, price, validityWeeks, currency, mode, isSingle } = req.body || {};
  if (!nameEn || !nameAr || !classCount || price == null || !validityWeeks)
    return res.status(400).json({ error: 'nameEn, nameAr, classCount, price, validityWeeks required' });
  const r = await pool.query(
    // (v0.11 fix) `mode` is the package_mode enum — the parameter arrives as
    // text and must be cast explicitly, otherwise every create failed with
    // "column mode is of type package_mode but expression is of type text".
    `INSERT INTO package_definitions (name_en,name_ar,class_count,price,validity_weeks,currency,mode,is_single)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6,'JOD'),COALESCE($7,'online')::package_mode,COALESCE($8,FALSE))
     RETURNING *`,
    [nameEn, nameAr, classCount, price, validityWeeks, currency, mode, isSingle]
  );
  res.status(201).json(r.rows[0]);
});

// Edit price / classes / validity / mode / active. Does NOT affect already-purchased
// member packages (those snapshot their values) — confirmed in v0.3 scope.
router.put('/packages/:id', async (req, res) => {
  const { nameEn, nameAr, classCount, price, validityWeeks, mode, isActive } = req.body || {};
  const r = await pool.query(
    `UPDATE package_definitions SET
       name_en=COALESCE($2,name_en), name_ar=COALESCE($3,name_ar),
       class_count=COALESCE($4,class_count), price=COALESCE($5,price),
       validity_weeks=COALESCE($6,validity_weeks), mode=COALESCE($7::package_mode,mode),
       is_active=COALESCE($8,is_active)
     WHERE id=$1 RETURNING *`,
    [req.params.id, nameEn, nameAr, classCount, price, validityWeeks, mode, isActive]
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'Package not found' });
  res.json(r.rows[0]);
});

// ---- Offline payment: activate a member's package (spec §10.5) ----
// v0.4 (items 6, 7): includes proof-of-payment metadata (never the bytes — the
// image is fetched via /payment-proof below), member name, and the coach the
// package was purchased for.
router.get('/packages/pending', async (req, res) => {
  const r = await pool.query(
    `SELECT mp.id, mp.member_id, mp.coach_id, mp.status, mp.classes_total, mp.validity_weeks,
            mp.price, mp.currency, mp.mode, mp.is_single, mp.requested_at,
            (mp.proof_content IS NOT NULL) AS has_proof,
            mp.proof_mime, mp.proof_file_name, mp.proof_uploaded_at,
            mp.payment_rejection_reason, mp.payment_rejected_at,
            u.email, m.first_name AS member_first, m.last_name AS member_last,
            pd.name_en, cp.first_name AS coach_first, cp.last_name AS coach_last
       FROM member_packages mp
       JOIN users u ON u.id=mp.member_id
       JOIN member_profiles m ON m.user_id=mp.member_id
       JOIN package_definitions pd ON pd.id=mp.package_def_id
       LEFT JOIN coach_profiles cp ON cp.user_id=mp.coach_id
      WHERE mp.status='pending_payment' ORDER BY mp.requested_at`
  );
  res.json(r.rows);
});

// (item 6) View the proof-of-payment image for a package request.
router.get('/packages/:id/payment-proof', async (req, res) => {
  const r = await pool.query(
    `SELECT proof_content, proof_mime, proof_file_name FROM member_packages WHERE id=$1`,
    [req.params.id]
  );
  if (r.rowCount === 0 || !r.rows[0].proof_content)
    return res.status(404).json({ error: 'No proof uploaded for this package' });
  res.setHeader('Content-Type', r.rows[0].proof_mime || 'application/octet-stream');
  res.setHeader('Content-Disposition', `inline; filename="${r.rows[0].proof_file_name || 'proof'}"`);
  res.send(r.rows[0].proof_content);
});

// (item 6) Reject the SUBMITTED PROOF with a reason. The request stays
// pending_payment; the member sees the reason and can re-upload.
router.post('/packages/:id/reject-payment', async (req, res) => {
  const { reason } = req.body || {};
  if (!reason || !reason.trim()) return res.status(400).json({ error: 'reason required' });
  const r = await pool.query(
    `UPDATE member_packages
        SET payment_rejection_reason=$2, payment_rejected_at=now()
      WHERE id=$1 AND status='pending_payment' RETURNING id, payment_rejection_reason`,
    [req.params.id, reason.trim()]
  );
  if (r.rowCount === 0) return res.status(409).json({ error: 'Package not pending or not found' });
  const owner = await pool.query(`SELECT member_id FROM member_packages WHERE id=$1`, [req.params.id]);
  await notify({
    userId: owner.rows[0].member_id,
    type: 'package_payment_rejected',
    titleEn: 'Payment proof needs attention',
    titleAr: 'إثبات الدفع بحاجة إلى مراجعة',
    bodyEn: `Your proof of payment was not accepted: ${reason.trim()}. Please upload a new one from the Packages tab.`,
    bodyAr: `لم يتم قبول إثبات الدفع: ${reason.trim()}. يرجى رفع إثبات جديد من صفحة الباقات.`,
    relatedId: req.params.id,
    email: true,
  });
  res.json(r.rows[0]);
});

// (item 7) Reassign an active package to another coach — for the exceptional
// case where a coach leaves/is suspended while members hold remaining classes.
// =============================================================================
// (v0.9 items 3-5) Admin package management.
// Every mutation is written to package_adjustments with the admin, the
// before/after values and a required reason — packages are money, so the
// paper trail matters.
// =============================================================================

async function logAdjustment(client, { packageId, adminId, action, before, after, reason }) {
  await client.query(
    `INSERT INTO package_adjustments (package_id, admin_id, action, before_value, after_value, reason)
     VALUES ($1,$2,$3,$4,$5,$6)`,
    [packageId, adminId, action, before == null ? null : String(before), after == null ? null : String(after), reason]);
}

// Move a package to another coach. Kept deliberately simple (client decision):
// the admin can always move it — used when a member complains or a coach
// leaves. Any UPCOMING bookings with the previous coach are released
// (cancelled without deducting a class) so the package and its bookings can
// never point at two different coaches.
router.post('/member-packages/:id/reassign', async (req, res) => {
  const { coachId, reason } = req.body || {};
  if (!coachId) return res.status(400).json({ error: 'coachId required' });
  if (!reason || !String(reason).trim()) return res.status(400).json({ error: 'reason required' });
  const coach = await pool.query(`SELECT status FROM coach_profiles WHERE user_id=$1`, [coachId]);
  if (coach.rowCount === 0 || coach.rows[0].status !== 'approved')
    return res.status(404).json({ error: 'Target coach not found or not approved' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const cur = await client.query(
      `SELECT mp.*, cp.first_name, cp.last_name FROM member_packages mp
         LEFT JOIN coach_profiles cp ON cp.user_id=mp.coach_id
        WHERE mp.id=$1 FOR UPDATE OF mp`, [req.params.id]);
    if (cur.rowCount === 0) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Package not found' }); }
    const pkg = cur.rows[0];
    if (!['pending_payment', 'active'].includes(pkg.status)) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Only pending or active packages can be moved' });
    }
    if (pkg.coach_id === coachId) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'Package is already with that coach' }); }

    // Release upcoming bookings tied to this package with the old coach.
    const released = await client.query(
      `UPDATE bookings b
          SET status='cancelled', cancelled_at=now(), cancel_kind='early',
              rejection_reason='Package moved to another coach by admin'
         FROM coach_sessions cs
        WHERE cs.id=b.session_id AND b.member_package_id=$1
          AND b.status IN ('pending','accepted') AND cs.start_at > now()
        RETURNING b.id`, [req.params.id]);
    if (released.rowCount > 0) {
      await client.query(
        `UPDATE member_packages SET classes_pending = GREATEST(classes_pending - $2, 0) WHERE id=$1`,
        [req.params.id, released.rowCount]);
    }

    let moved;
    try {
      moved = await client.query(
        `UPDATE member_packages SET coach_id=$2 WHERE id=$1 RETURNING id, coach_id, status`,
        [req.params.id, coachId]);
    } catch (err) {
      await client.query('ROLLBACK');
      if (err.code === '23505')
        return res.status(409).json({ error: 'The member already has a pending/active package or used trial with that coach' });
      throw err;
    }
    await logAdjustment(client, {
      packageId: req.params.id, adminId: req.user.id, action: 'move_coach',
      before: `${pkg.first_name || ''} ${pkg.last_name || ''}`.trim() || pkg.coach_id,
      after: coachId, reason,
    });
    await client.query('COMMIT');
    const newCoach = await pool.query(`SELECT first_name, last_name FROM coach_profiles WHERE user_id=$1`, [coachId]);
    const nc = newCoach.rows[0] || {};
    await notify({
      userId: pkg.member_id,
      type: 'package_moved',
      titleEn: 'Your package moved to a new coach',
      titleAr: 'تم نقل باقتك إلى مدرب جديد',
      bodyEn: `Your package is now with ${nc.first_name} ${nc.last_name}. Reason: ${reason}.`
        + (released.rowCount > 0 ? ` ${released.rowCount} upcoming session(s) were released — no class was deducted.` : ''),
      bodyAr: `أصبحت باقتك الآن مع ${nc.first_name} ${nc.last_name}. السبب: ${reason}.`,
      relatedId: req.params.id,
      email: true,
    });
    res.json({ ...moved.rows[0], releasedBookings: released.rowCount });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
});

// Add or deduct classes on a package.
//   * add    -> classes_total += n (optionally set a new expiry at the same time)
//   * deduct -> classes_total -= n, never below classes already consumed or
//               held by pending bookings.
router.post('/member-packages/:id/adjust-classes', async (req, res) => {
  const { delta, reason, expiresAt } = req.body || {};
  const n = parseInt(delta, 10);
  if (!Number.isInteger(n) || n === 0) return res.status(400).json({ error: 'delta must be a non-zero integer' });
  if (!reason || !String(reason).trim()) return res.status(400).json({ error: 'reason required' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const cur = await client.query(`SELECT * FROM member_packages WHERE id=$1 FOR UPDATE`, [req.params.id]);
    if (cur.rowCount === 0) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Package not found' }); }
    const pkg = cur.rows[0];
    if (pkg.status === 'cancelled') { await client.query('ROLLBACK'); return res.status(409).json({ error: 'Package is cancelled' }); }

    const floor = pkg.classes_consumed + pkg.classes_pending;
    const newTotal = pkg.classes_total + n;
    if (newTotal < floor) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: `Cannot go below ${floor} classes — ${pkg.classes_consumed} already used and ${pkg.classes_pending} held by upcoming bookings`,
      });
    }
    if (newTotal < 1) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'A package must keep at least 1 class' }); }

    const upd = await client.query(
      `UPDATE member_packages SET classes_total=$2 WHERE id=$1 RETURNING *`, [req.params.id, newTotal]);
    await logAdjustment(client, {
      packageId: req.params.id, adminId: req.user.id,
      action: n > 0 ? 'add_classes' : 'deduct_classes',
      before: pkg.classes_total, after: newTotal, reason,
    });

    let row = upd.rows[0];
    if (expiresAt) {
      const ext = await client.query(
        `UPDATE member_packages SET expires_at=$2::timestamptz WHERE id=$1 RETURNING *`,
        [req.params.id, expiresAt]);
      await logAdjustment(client, {
        packageId: req.params.id, adminId: req.user.id, action: 'extend_expiry',
        before: pkg.expires_at, after: expiresAt, reason,
      });
      row = ext.rows[0];
    }
    await client.query('COMMIT');
    await notify({
      userId: row.member_id,
      type: 'package_adjusted',
      titleEn: n > 0 ? 'Classes added to your package' : 'Your package was adjusted',
      titleAr: n > 0 ? 'تمت إضافة حصص إلى باقتك' : 'تم تعديل باقتك',
      bodyEn: `${n > 0 ? 'Added' : 'Removed'} ${Math.abs(n)} class(es). Reason: ${reason}`,
      bodyAr: `${n > 0 ? 'تمت إضافة' : 'تم خصم'} ${Math.abs(n)} حصة. السبب: ${reason}`,
      relatedId: row.id,
      email: true,
    });
    res.json(row);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
});

// Cancel a member's package. Blocked while upcoming bookings exist (client
// decision (a)) so nothing disappears silently — the admin handles those first.
router.post('/member-packages/:id/cancel', async (req, res) => {
  const { reason } = req.body || {};
  if (!reason || !String(reason).trim()) return res.status(400).json({ error: 'reason required' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const cur = await client.query(`SELECT * FROM member_packages WHERE id=$1 FOR UPDATE`, [req.params.id]);
    if (cur.rowCount === 0) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Package not found' }); }
    const pkg = cur.rows[0];
    if (pkg.status === 'cancelled') { await client.query('ROLLBACK'); return res.status(409).json({ error: 'Package is already cancelled' }); }

    const upcoming = await client.query(
      `SELECT COUNT(*)::int n FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
        WHERE b.member_package_id=$1 AND b.status IN ('pending','accepted') AND cs.start_at > now()`,
      [req.params.id]);
    if (upcoming.rows[0].n > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: `This package has ${upcoming.rows[0].n} upcoming booking(s). Cancel or complete them first, then cancel the package.`,
        upcomingBookings: upcoming.rows[0].n,
      });
    }

    const upd = await client.query(
      `UPDATE member_packages SET status='cancelled' WHERE id=$1 RETURNING *`, [req.params.id]);
    await logAdjustment(client, {
      packageId: req.params.id, adminId: req.user.id, action: 'cancel',
      before: pkg.status, after: 'cancelled', reason,
    });
    await client.query('COMMIT');
    await notify({
      userId: upd.rows[0].member_id,
      type: 'package_cancelled',
      titleEn: 'Your package was cancelled',
      titleAr: 'تم إلغاء باقتك',
      bodyEn: `Reason: ${reason}. Please contact the CoachlyJo team if you have questions.`,
      bodyAr: `السبب: ${reason}. يرجى التواصل مع فريق كوتشلي جو لأي استفسار.`,
      relatedId: upd.rows[0].id,
      email: true,
    });
    res.json(upd.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
});

// Adjustment history for one package.
router.get('/member-packages/:id/history', async (req, res) => {
  const r = await pool.query(
    `SELECT pa.action, pa.before_value, pa.after_value, pa.reason, pa.created_at,
            u.email AS admin_email
       FROM package_adjustments pa JOIN users u ON u.id=pa.admin_id
      WHERE pa.package_id=$1 ORDER BY pa.created_at DESC`, [req.params.id]);
  res.json(r.rows);
});

// (item 5) Master list of every package in the system with full detail.
// Filters: ?status=&coachId=&mode=&q= (member or coach name / email).
router.get('/member-packages', async (req, res) => {
  const { status, coachId, mode, q } = req.query;
  const where = ['1=1'];
  const params = [];
  if (status) { params.push(status); where.push(`mp.status = $${params.length}`); }
  if (coachId) { params.push(coachId); where.push(`mp.coach_id = $${params.length}`); }
  if (mode) { params.push(mode); where.push(`mp.mode = $${params.length}`); }
  if (q) {
    params.push(`%${q}%`);
    const i = params.length;
    where.push(`(m.first_name ILIKE $${i} OR m.last_name ILIKE $${i} OR um.email ILIKE $${i}
                 OR cp.first_name ILIKE $${i} OR cp.last_name ILIKE $${i})`);
  }
  const r = await pool.query(
    `SELECT mp.id, mp.status, mp.mode, mp.is_single, mp.price, mp.currency,
            mp.classes_total, mp.classes_consumed, mp.classes_pending,
            (mp.classes_total - mp.classes_consumed) AS remaining,
            mp.requested_at, mp.activated_at, mp.expires_at,
            (mp.proof_content IS NOT NULL) AS has_proof,
            mp.payment_rejection_reason,
            pd.name_en AS package_name,
            m.user_id AS member_id, m.first_name AS member_first, m.last_name AS member_last,
            um.email AS member_email, um.phone AS member_phone,
            mp.coach_id, cp.first_name AS coach_first, cp.last_name AS coach_last,
            (SELECT COUNT(*)::int FROM package_adjustments pa WHERE pa.package_id=mp.id) AS adjustments,
            (SELECT COUNT(*)::int FROM bookings b WHERE b.member_package_id=mp.id AND b.status='completed') AS sessions_done
       FROM member_packages mp
       JOIN package_definitions pd ON pd.id=mp.package_def_id
       JOIN member_profiles m ON m.user_id=mp.member_id
       JOIN users um ON um.id=mp.member_id
       LEFT JOIN coach_profiles cp ON cp.user_id=mp.coach_id
      WHERE ${where.join(' AND ')}
      ORDER BY mp.requested_at DESC
      LIMIT 300`, params);
  res.json(r.rows);
});

// (item 4) Every member who bought a package with this coach.
router.get('/coaches/:coachId/members', async (req, res) => {
  const r = await pool.query(
    `SELECT m.user_id AS member_id, m.first_name, m.last_name, m.location,
            u.email, u.phone,
            COUNT(mp.id)::int AS packages,
            COALESCE(SUM(mp.classes_total), 0)::int AS classes_bought,
            COALESCE(SUM(mp.classes_consumed), 0)::int AS classes_used,
            COALESCE(SUM(CASE WHEN mp.status <> 'cancelled' THEN mp.price ELSE 0 END), 0) AS revenue,
            MAX(mp.requested_at) AS last_purchase,
            BOOL_OR(mp.status='active' AND mp.classes_consumed < mp.classes_total) AS has_active
       FROM member_packages mp
       JOIN member_profiles m ON m.user_id=mp.member_id
       JOIN users u ON u.id=mp.member_id
      WHERE mp.coach_id=$1
      GROUP BY m.user_id, m.first_name, m.last_name, m.location, u.email, u.phone
      ORDER BY MAX(mp.requested_at) DESC`, [req.params.coachId]);
  res.json(r.rows);
});

router.post('/packages/:id/activate', async (req, res) => {
  // Trigger fn_set_package_expiry computes expires_at from activated_at (spec §9.3).
  const r = await pool.query(
    `UPDATE member_packages
        SET status='active', activated_at=now(), activated_by=$2
      WHERE id=$1 AND status='pending_payment' RETURNING *`,
    [req.params.id, req.user.id]
  );
  if (r.rowCount === 0) return res.status(409).json({ error: 'Package not pending or not found' });
  const pkg = r.rows[0];
  const meta = await pool.query(
    `SELECT pd.name_en, pd.name_ar, mp2.first_name AS member_first, mp2.last_name AS member_last
       FROM member_packages mp
       JOIN package_definitions pd ON pd.id = mp.package_def_id
       JOIN member_profiles mp2 ON mp2.user_id = mp.member_id
      WHERE mp.id = $1`, [req.params.id]);
  const m = meta.rows[0] || {};
  await notify({
    userId: pkg.member_id,
    type: 'package_activated',
    titleEn: 'Your package is active',
    titleAr: 'باقتك مفعّلة الآن',
    bodyEn: `${m.name_en} is ready — you can book your sessions now.`,
    bodyAr: `${m.name_ar || m.name_en} جاهزة — يمكنك حجز جلساتك الآن.`,
    relatedId: pkg.id,
    email: true,
  });
  if (pkg.coach_id) {
    await notify({
      userId: pkg.coach_id,
      type: 'new_client',
      titleEn: 'New client',
      titleAr: 'عميل جديد',
      bodyEn: `${m.member_first} ${m.member_last} bought ${m.name_en} with you.`,
      bodyAr: `اشترى ${m.member_first} ${m.member_last} ${m.name_ar || m.name_en} معك.`,
      relatedId: pkg.id,
      email: true,
    });
  }
  res.json(pkg);
});

// (item 14) Reject a pending package when payment did not arrive.
router.post('/packages/:id/reject', async (req, res) => {
  const r = await pool.query(
    `UPDATE member_packages SET status='cancelled'
      WHERE id=$1 AND status='pending_payment' RETURNING *`,
    [req.params.id]
  );
  if (r.rowCount === 0) return res.status(409).json({ error: 'Package not pending or not found' });
  res.json(r.rows[0]);
});

// ---- Payment note config (spec §10.3) ----
router.put('/payment-note', async (req, res) => {
  const { bodyEn, bodyAr } = req.body || {};
  const r = await pool.query(
    `UPDATE payment_notes SET body_en=COALESCE($1,body_en), body_ar=COALESCE($2,body_ar),
       updated_by=$3, updated_at=now() WHERE id=1 RETURNING *`,
    [bodyEn, bodyAr, req.user.id]
  );
  res.json(r.rows[0]);
});

// ---- Reporting dashboard (spec §8, §13.7) ----
router.get('/reports/overview', async (req, res) => {
  const [coaches, bookings, subs, topCoaches] = await Promise.all([
    pool.query(`SELECT status, COUNT(*)::int n FROM coach_profiles GROUP BY status`),
    pool.query(`SELECT status, COUNT(*)::int n FROM bookings GROUP BY status`),
    pool.query(`SELECT status, COUNT(*)::int n, COALESCE(SUM(price),0) revenue FROM member_packages GROUP BY status`),
    pool.query(`SELECT first_name, last_name, avg_rating, rating_count FROM coach_profiles
                 WHERE rating_count>0 ORDER BY avg_rating DESC LIMIT 5`),
  ]);
  res.json({
    coachesByStatus: coaches.rows,
    bookingsByStatus: bookings.rows,
    subscriptions: subs.rows,
    topCoaches: topCoaches.rows,
  });
});

// (v0.4 item 8) Detailed dashboard. ?days=7|30|90 window.
// Revenue counts packages ACTIVATED in the window (payment confirmed = revenue
// recognized); sessions count bookings COMPLETED in the window.
router.get('/reports/detailed', async (req, res) => {
  const days = [7, 30, 90].includes(parseInt(req.query.days, 10)) ? parseInt(req.query.days, 10) : 30;
  const d = String(days);
  const [totals, revenueSeries, sessionSeries, salesByPackage, leaderboard] = await Promise.all([
    pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM member_profiles) AS total_members,
         (SELECT COUNT(DISTINCT member_id)::int FROM member_packages
           WHERE status='active' AND (expires_at IS NULL OR expires_at > now())
             AND classes_consumed < classes_total) AS active_members,
         (SELECT COUNT(*)::int FROM coach_profiles WHERE status='approved') AS approved_coaches,
         (SELECT COUNT(*)::int FROM coach_profiles WHERE status='pending') AS pending_coaches,
         (SELECT COUNT(*)::int FROM member_packages WHERE status='pending_payment') AS pending_payments,
         (SELECT COALESCE(SUM(price),0) FROM member_packages
           WHERE status IN ('active','expired') AND activated_at > now() - ($1 || ' days')::interval) AS revenue_in_range,
         (SELECT COUNT(*)::int FROM bookings
           WHERE status='completed' AND completed_at > now() - ($1 || ' days')::interval) AS sessions_in_range`,
      [d]),
    pool.query(
      `SELECT to_char(date_trunc('week', activated_at), 'DD Mon') AS week,
              date_trunc('week', activated_at) AS week_start,
              COALESCE(SUM(price),0) AS revenue, COUNT(*)::int AS purchases
         FROM member_packages
        WHERE status IN ('active','expired') AND activated_at > now() - ($1 || ' days')::interval
        GROUP BY 1, 2 ORDER BY 2`, [d]),
    pool.query(
      `SELECT to_char(date_trunc('week', completed_at), 'DD Mon') AS week,
              date_trunc('week', completed_at) AS week_start,
              COUNT(*)::int AS completed
         FROM bookings
        WHERE status='completed' AND completed_at > now() - ($1 || ' days')::interval
        GROUP BY 1, 2 ORDER BY 2`, [d]),
    pool.query(
      `SELECT pd.name_en, COUNT(*)::int AS sold, COALESCE(SUM(mp.price),0) AS revenue
         FROM member_packages mp JOIN package_definitions pd ON pd.id=mp.package_def_id
        WHERE mp.status IN ('active','expired') AND mp.activated_at > now() - ($1 || ' days')::interval
        GROUP BY pd.name_en ORDER BY revenue DESC`, [d]),
    pool.query(
      `SELECT cp.user_id, cp.first_name, cp.last_name, cp.avg_rating, cp.rating_count,
              COUNT(b.id) FILTER (WHERE b.status='completed' AND b.completed_at > now() - ($1 || ' days')::interval)::int AS completed_in_range,
              COUNT(b.id) FILTER (WHERE b.status='cancelled' AND b.cancelled_at > now() - ($1 || ' days')::interval)::int AS cancelled_in_range,
              (SELECT COUNT(*)::int FROM member_packages mp
                WHERE mp.coach_id=cp.user_id AND mp.status='active'
                  AND mp.classes_consumed < mp.classes_total
                  AND (mp.expires_at IS NULL OR mp.expires_at > now())) AS active_clients
         FROM coach_profiles cp
         LEFT JOIN coach_sessions cs ON cs.coach_id=cp.user_id
         LEFT JOIN bookings b ON b.session_id=cs.id
        WHERE cp.status='approved'
        GROUP BY cp.user_id, cp.first_name, cp.last_name, cp.avg_rating, cp.rating_count
        ORDER BY completed_in_range DESC, active_clients DESC
        LIMIT 20`, [d]),
  ]);
  res.json({
    days,
    totals: totals.rows[0],
    revenueByWeek: revenueSeries.rows,
    sessionsByWeek: sessionSeries.rows,
    salesByPackage: salesByPackage.rows,
    coachLeaderboard: leaderboard.rows,
  });
});

// ---- (item 1) View a coach's uploaded document (binary) ----
router.get('/coaches/:coachId/documents', async (req, res) => {
  const r = await pool.query(
    `SELECT id, doc_type, mime_type, file_name, byte_size, verified, uploaded_at
       FROM coach_documents WHERE coach_id=$1 ORDER BY uploaded_at`,
    [req.params.coachId]
  );
  res.json(r.rows);
});



// ---- (item 7) People directories ----
router.get('/coaches', async (req, res) => {
  const r = await pool.query(
    `SELECT cp.user_id, cp.first_name, cp.last_name, cp.status, cp.avg_rating, cp.rating_count,
            u.email, u.phone
       FROM coach_profiles cp JOIN users u ON u.id=cp.user_id
      ORDER BY cp.created_at DESC`
  );
  res.json(r.rows);
});

router.get('/members', async (req, res) => {
  const r = await pool.query(
    `SELECT mp.user_id, mp.first_name, mp.last_name, mp.location, u.email, u.phone,
            (SELECT COUNT(*) FROM bookings b WHERE b.member_id=mp.user_id) AS bookings_count
       FROM member_profiles mp JOIN users u ON u.id=mp.user_id
      ORDER BY u.created_at DESC`
  );
  res.json(r.rows);
});

// (item 3 & 7) Per-coach profile + today summary + reviews.
router.get('/coaches/:coachId/summary', async (req, res) => {
  const id = req.params.coachId;
  const [profile, today, reviews] = await Promise.all([
    pool.query(`SELECT cp.*, u.email, u.phone FROM coach_profiles cp JOIN users u ON u.id=cp.user_id WHERE cp.user_id=$1`, [id]),
    pool.query(
      `SELECT b.status, COUNT(*)::int n FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
        WHERE cs.coach_id=$1 AND (cs.start_at AT TIME ZONE 'Asia/Amman')::date = (now() AT TIME ZONE 'Asia/Amman')::date
        GROUP BY b.status`, [id]),
    pool.query(
      `SELECT r.rating, r.comment, r.created_at, mp.first_name AS member_first,
              cs.start_at AS session_at, cs.delivery AS session_delivery
         FROM reviews r
         JOIN member_profiles mp ON mp.user_id=r.member_id
         JOIN bookings b ON b.id=r.booking_id
         JOIN coach_sessions cs ON cs.id=b.session_id
        WHERE r.coach_id=$1 ORDER BY r.created_at DESC LIMIT 50`, [id]),
  ]);
  if (profile.rowCount === 0) return res.status(404).json({ error: 'Coach not found' });
  const todaySessions = await pool.query(
    `SELECT COUNT(*)::int n FROM coach_sessions
      WHERE coach_id=$1 AND (start_at AT TIME ZONE 'Asia/Amman')::date = (now() AT TIME ZONE 'Asia/Amman')::date`, [id]);
  // (v0.4 item 1) Documents are viewable from the coach profile, not only the
  // pending-approval card.
  const documents = await pool.query(
    `SELECT id, doc_type, mime_type, file_name, byte_size, verified, uploaded_at
       FROM coach_documents WHERE coach_id=$1 ORDER BY uploaded_at`, [id]);
  res.json({
    profile: profile.rows[0],
    today: { sessions: todaySessions.rows[0].n, bookingsByStatus: today.rows },
    reviews: reviews.rows,
    documents: documents.rows,
  });
});

// (item 7) Member profile + metrics.
router.get('/members/:memberId/summary', async (req, res) => {
  const id = req.params.memberId;
  const profile = await pool.query(
    `SELECT mp.*, u.email, u.phone FROM member_profiles mp JOIN users u ON u.id=mp.user_id WHERE mp.user_id=$1`, [id]);
  if (profile.rowCount === 0) return res.status(404).json({ error: 'Member not found' });
  const bookings = await pool.query(`SELECT status, COUNT(*)::int n FROM bookings WHERE member_id=$1 GROUP BY status`, [id]);
  const packages = await pool.query(`SELECT status, COUNT(*)::int n FROM member_packages WHERE member_id=$1 GROUP BY status`, [id]);
  // (v0.4 item 7) Concrete package list incl. the bound coach, for reassignment.
  const packageList = await pool.query(
    `SELECT mp.id, mp.status, mp.is_single, mp.mode,
            mp.classes_total, (mp.classes_total - mp.classes_consumed) AS remaining,
            mp.price, mp.currency, mp.expires_at,
            pd.name_en, cp.first_name AS coach_first, cp.last_name AS coach_last
       FROM member_packages mp
       JOIN package_definitions pd ON pd.id=mp.package_def_id
       LEFT JOIN coach_profiles cp ON cp.user_id=mp.coach_id
      WHERE mp.member_id=$1 ORDER BY mp.requested_at DESC`, [id]);
  const assessment = await pool.query(`SELECT responses, submitted_at FROM fitness_assessments WHERE member_id=$1 ORDER BY submitted_at DESC LIMIT 1`, [id]);
  res.json({ profile: profile.rows[0], bookingsByStatus: bookings.rows, packagesByStatus: packages.rows, packages: packageList.rows, assessment: assessment.rows[0] || null });
});

// ---- (item 2b) Questionnaire management ----
router.get('/questionnaire', async (req, res) => {
  const r = await pool.query(`SELECT * FROM questionnaire_questions ORDER BY sort_order, created_at`);
  res.json(r.rows);
});

router.post('/questionnaire', async (req, res) => {
  const { key, labelEn, labelAr, inputType, options, required, sortOrder } = req.body || {};
  if (!key || !labelEn || !inputType) return res.status(400).json({ error: 'key, labelEn, inputType required' });
  if (!['text', 'number', 'dropdown'].includes(inputType)) return res.status(400).json({ error: 'invalid inputType' });
  try {
    const r = await pool.query(
      `INSERT INTO questionnaire_questions (key,label_en,label_ar,input_type,options,required,sort_order)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [key, labelEn, labelAr || '', inputType, options ? JSON.stringify(options) : null, !!required, sortOrder || 0]
    );
    res.status(201).json(r.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'A question with that key already exists' });
    throw err;
  }
});

router.delete('/questionnaire/:id', async (req, res) => {
  // Soft-deactivate so existing answers remain meaningful.
  const r = await pool.query(`UPDATE questionnaire_questions SET is_active=FALSE WHERE id=$1 RETURNING id`, [req.params.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Question not found' });
  res.json({ deactivated: req.params.id });
});

// ---- (items 10,11) Location management ----
router.get('/locations', async (req, res) => {
  const r = await pool.query(`SELECT * FROM locations ORDER BY sort_order, name_en`);
  res.json(r.rows);
});

router.post('/locations', async (req, res) => {
  const { nameEn, nameAr, sortOrder } = req.body || {};
  if (!nameEn) return res.status(400).json({ error: 'nameEn required' });
  try {
    const r = await pool.query(
      `INSERT INTO locations (name_en, name_ar, sort_order) VALUES ($1,$2,$3) RETURNING *`,
      [nameEn, nameAr || '', sortOrder || 0]
    );
    res.status(201).json(r.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'A location with that name already exists' });
    throw err;
  }
});

router.patch('/locations/:id', async (req, res) => {
  const { isActive } = req.body || {};
  if (typeof isActive !== 'boolean') return res.status(400).json({ error: 'isActive (boolean) required' });
  const r = await pool.query(`UPDATE locations SET is_active=$2 WHERE id=$1 RETURNING *`, [req.params.id, isActive]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Location not found' });
  res.json(r.rows[0]);
});

router.delete('/locations/:id', async (req, res) => {
  const r = await pool.query(`DELETE FROM locations WHERE id=$1 RETURNING id`, [req.params.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Location not found' });
  res.json({ deleted: req.params.id });
});

// =============================================================================
// (v0.10) Home-page content management + coach penalties.
// =============================================================================

// All content blocks (including inactive) for editing.
router.get('/content', async (req, res) => {
  const r = await pool.query(
    `SELECT id, key, audience, kind, title_en, title_ar, body_en, body_ar, sort_order, is_active, updated_at
       FROM content_blocks ORDER BY audience, kind, sort_order`);
  const s = await pool.query(`SELECT intro_video_url FROM platform_settings WHERE id=1`);
  res.json({ videoUrl: s.rows[0]?.intro_video_url || '', blocks: r.rows });
});

// Edit one block (title/body in either language, order, active flag).
router.put('/content/:id', async (req, res) => {
  const { titleEn, titleAr, bodyEn, bodyAr, sortOrder, isActive } = req.body || {};
  const r = await pool.query(
    `UPDATE content_blocks
        SET title_en = COALESCE($2, title_en),
            title_ar = COALESCE($3, title_ar),
            body_en  = COALESCE($4, body_en),
            body_ar  = COALESCE($5, body_ar),
            sort_order = COALESCE($6, sort_order),
            is_active  = COALESCE($7, is_active),
            updated_at = now()
      WHERE id = $1 RETURNING *`,
    [req.params.id, titleEn ?? null, titleAr ?? null, bodyEn ?? null, bodyAr ?? null,
     sortOrder ?? null, typeof isActive === 'boolean' ? isActive : null]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Content block not found' });
  res.json(r.rows[0]);
});

// Add a new block (e.g. another rule or step).
router.post('/content', async (req, res) => {
  const { key, audience, kind, titleEn, titleAr, bodyEn, bodyAr, sortOrder } = req.body || {};
  if (!key || !audience || !kind) return res.status(400).json({ error: 'key, audience and kind are required' });
  if (!['member', 'coach', 'both'].includes(audience)) return res.status(400).json({ error: 'audience must be member, coach or both' });
  if (!['intro', 'step', 'rule'].includes(kind)) return res.status(400).json({ error: 'kind must be intro, step or rule' });
  try {
    const r = await pool.query(
      `INSERT INTO content_blocks (key, audience, kind, title_en, title_ar, body_en, body_ar, sort_order)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
      [key, audience, kind, titleEn || '', titleAr || '', bodyEn || '', bodyAr || '', sortOrder || 0]);
    res.status(201).json(r.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'That key already exists' });
    throw err;
  }
});

router.delete('/content/:id', async (req, res) => {
  const r = await pool.query(`DELETE FROM content_blocks WHERE id=$1 RETURNING id`, [req.params.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Content block not found' });
  res.json({ deleted: r.rows[0].id });
});

// Intro video URL (empty string hides the video block on the home page).
router.put('/content-video', async (req, res) => {
  const { videoUrl } = req.body || {};
  const r = await pool.query(
    `UPDATE platform_settings SET intro_video_url = $1, updated_at = now() WHERE id=1 RETURNING intro_video_url`,
    [String(videoUrl || '').trim()]);
  res.json(r.rows[0]);
});

// (v0.10 item 2) Coach penalties from same-day cancellations, for settlement.
router.get('/penalties', async (req, res) => {
  const onlyOpen = req.query.settled !== 'true';
  const r = await pool.query(
    `SELECT cp.id, cp.sessions, cp.reason, cp.created_at, cp.settled_at,
            cp.coach_id, c.first_name AS coach_first, c.last_name AS coach_last,
            cs.start_at AS session_at,
            m.first_name AS member_first, m.last_name AS member_last
       FROM coach_penalties cp
       JOIN coach_profiles c ON c.user_id = cp.coach_id
       LEFT JOIN bookings b ON b.id = cp.booking_id
       LEFT JOIN coach_sessions cs ON cs.id = b.session_id
       LEFT JOIN member_profiles m ON m.user_id = b.member_id
      WHERE ${onlyOpen ? 'cp.settled_at IS NULL' : 'TRUE'}
      ORDER BY cp.created_at DESC`);
  res.json(r.rows);
});

router.post('/penalties/:id/settle', async (req, res) => {
  const r = await pool.query(
    `UPDATE coach_penalties SET settled_at = now(), settled_by = $2
      WHERE id = $1 AND settled_at IS NULL RETURNING *`,
    [req.params.id, req.user.id]);
  if (r.rowCount === 0) return res.status(409).json({ error: 'Penalty not found or already settled' });
  res.json(r.rows[0]);
});

// =============================================================================
// (v0.13) Account-deletion requests received from the public web form, and
// admin-initiated deletion. Required by Google Play's account-deletion policy.
// =============================================================================
router.get('/deletion-requests', async (req, res) => {
  const status = ['open', 'done', 'rejected'].includes(req.query.status) ? req.query.status : 'open';
  const r = await pool.query(
    `SELECT dr.*, u.id AS matched_user_id, u.role AS matched_role, u.deleted_at
       FROM deletion_requests dr
       LEFT JOIN users u ON lower(u.email) = dr.email AND u.deleted_at IS NULL
      WHERE dr.status = $1
      ORDER BY dr.created_at DESC`, [status]);
  res.json(r.rows);
});

// Complete a request: deletes the matched account, then closes the request.
router.post('/deletion-requests/:id/complete', async (req, res) => {
  const r = await pool.query(`SELECT * FROM deletion_requests WHERE id=$1`, [req.params.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Request not found' });
  if (r.rows[0].status !== 'open') return res.status(409).json({ error: 'Request already handled' });

  const u = await pool.query(
    `SELECT id FROM users WHERE lower(email) = $1 AND deleted_at IS NULL`, [r.rows[0].email]);
  let result = { deleted: false, note: 'No active account matched this email' };
  if (u.rowCount > 0) {
    try {
      result = await deleteAccount(u.rows[0].id, 'web', 'Web deletion request');
    } catch (err) {
      if (err instanceof DeletionError) return res.status(err.status).json({ error: err.message });
      throw err;
    }
  }
  await pool.query(
    `UPDATE deletion_requests SET status='done', handled_by=$2, handled_at=now() WHERE id=$1`,
    [req.params.id, req.user.id]);
  res.json({ ...result, request: req.params.id });
});

router.post('/deletion-requests/:id/reject', async (req, res) => {
  const r = await pool.query(
    `UPDATE deletion_requests SET status='rejected', handled_by=$2, handled_at=now()
      WHERE id=$1 AND status='open' RETURNING *`, [req.params.id, req.user.id]);
  if (r.rowCount === 0) return res.status(409).json({ error: 'Request not found or already handled' });
  res.json(r.rows[0]);
});

// Admin deletes a member/coach account directly (support requests by phone).
router.delete('/users/:id', async (req, res) => {
  try {
    const result = await deleteAccount(req.params.id, 'admin', req.body?.reason || 'Deleted by admin');
    res.json(result);
  } catch (err) {
    if (err instanceof DeletionError) return res.status(err.status).json({ error: err.message });
    throw err;
  }
});

// (v0.14 item 6) Contact details shown on the Contact Us screen.
router.put('/contact', async (req, res) => {
  const { email, phone, instagram, whatsapp } = req.body || {};
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))
    return res.status(400).json({ error: 'Please enter a valid email address' });
  const r = await pool.query(
    `UPDATE platform_settings
        SET contact_email = COALESCE($1, contact_email),
            contact_phone = COALESCE($2, contact_phone),
            contact_instagram = COALESCE($3, contact_instagram),
            contact_whatsapp = COALESCE($4, contact_whatsapp),
            updated_at = now()
      WHERE id = 1
      RETURNING contact_email, contact_phone, contact_instagram, contact_whatsapp`,
    [email ?? null, phone ?? null, instagram ?? null, whatsapp ?? null]);
  res.json(r.rows[0]);
});

module.exports = router;
