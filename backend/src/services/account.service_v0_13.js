// =============================================================================
// Account deletion (v0.13 — App Store / Play Store compliance).
//
// Apple requires an in-app way to delete the account; Google requires the same
// plus a web route that works without the app installed. Both require that the
// associated DATA is deleted, not merely that the account is disabled.
//
// What this does:
//   * erases every identifying field on the user (name, email, phone, DOB,
//     nationality, location, bio) and the password hash;
//   * deletes the personal artefacts outright: questionnaire answers, uploaded
//     coach documents, payment-proof images, notifications, OTP and reset codes,
//     reviews' free-text comments;
//   * cancels upcoming bookings so nobody is left waiting for a no-show, with
//     no class deducted, notifying the other side;
//   * for coaches: removes future unbooked slots and availability, and tells
//     the admins so remaining member packages can be reassigned.
//
// What it deliberately keeps:
//   * the member_packages / bookings rows themselves, now pointing at an
//     anonymised user. These are financial records (money received against a
//     package) that Jordanian accounting rules require us to retain. Both
//     stores accept this when it is disclosed — our seeded privacy policy says
//     so explicitly, in both languages.
//
// The operation is transactional: it either completes or changes nothing.
// =============================================================================
const { pool } = require('../db/pool_v0_13');
const { notify, notifyAdmins } = require('./notification.service_v0_13');
const { invalidateAccount } = require('../middleware/auth_v0_13');

class DeletionError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

/**
 * Delete (anonymise) an account.
 * @param {string} userId
 * @param {'user'|'admin'|'web'} requestedBy
 * @param {string} [reason] optional free text kept in the audit row
 */
async function deleteAccount(userId, requestedBy = 'user', reason = null) {
  const who = await pool.query(`SELECT id, role, deleted_at FROM users WHERE id = $1`, [userId]);
  if (who.rowCount === 0) throw new DeletionError('Account not found', 404);
  if (who.rows[0].deleted_at) throw new DeletionError('This account is already deleted', 409);
  const role = who.rows[0].role;

  // An admin deleting themselves would lock everyone out of the console.
  if (role === 'admin') {
    throw new DeletionError(
      'Administrator accounts cannot be deleted from the app. Contact CoachlyJo support to transfer ownership first.',
      409
    );
  }

  // Collect what we must notify about BEFORE the data is gone.
  const upcoming = await pool.query(
    `SELECT b.id, b.member_id, cs.coach_id, cs.start_at
       FROM bookings b JOIN coach_sessions cs ON cs.id = b.session_id
      WHERE b.status IN ('pending','accepted') AND cs.start_at > now()
        AND (b.member_id = $1 OR cs.coach_id = $1)`,
    [userId]
  );

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // --- cancel upcoming bookings, never charging anyone ---
    for (const b of upcoming.rows) {
      await client.query(
        `UPDATE bookings
            SET status='cancelled', cancelled_at=now(), cancel_kind='early',
                cancelled_by=$2,
                rejection_reason='Cancelled because the other party closed their account'
          WHERE id=$1`,
        [b.id, role === 'member' ? 'member' : 'coach']
      );
      if (b.member_id) {
        await client.query(
          `UPDATE member_packages mp
              SET classes_pending = GREATEST(mp.classes_pending - 1, 0)
            FROM bookings bk
           WHERE bk.id = $1 AND mp.id = bk.member_package_id`,
          [b.id]
        );
      }
    }

    // --- personal artefacts: delete outright ---
    await client.query(`DELETE FROM notifications WHERE user_id = $1`, [userId]);
    await client.query(`DELETE FROM otp_verifications WHERE user_id = $1`, [userId]);
    await client.query(`DELETE FROM password_resets WHERE user_id = $1`, [userId]);

    if (role === 'member') {
      await client.query(`DELETE FROM fitness_assessments WHERE member_id = $1`, [userId]);
      // Payment-proof images are personal documents; the package row stays.
      await client.query(
        `UPDATE member_packages
            SET proof_content = NULL, proof_mime = NULL, proof_file_name = NULL
          WHERE member_id = $1`,
        [userId]
      );
      // Reviews stay (they belong to the coach's rating) but lose the free text.
      await client.query(
        `UPDATE reviews SET comment = NULL WHERE member_id = $1`, [userId]);
      await client.query(
        `UPDATE member_profiles
            SET first_name='Deleted', last_name='user', location=NULL,
                date_of_birth=NULL, birth_place=NULL, nationality=NULL
          WHERE user_id = $1`,
        [userId]
      );
    }

    if (role === 'coach') {
      await client.query(`DELETE FROM coach_documents WHERE coach_id = $1`, [userId]);
      await client.query(`DELETE FROM coach_availability_ranges WHERE coach_id = $1`, [userId]);
      await client.query(`DELETE FROM coach_day_settings WHERE coach_id = $1`, [userId]);
      // Future slots nobody booked are pointless now; booked history stays.
      await client.query(
        `DELETE FROM coach_sessions cs
          WHERE cs.coach_id = $1 AND cs.start_at > now()
            AND NOT EXISTS (SELECT 1 FROM bookings b WHERE b.session_id = cs.id)`,
        [userId]
      );
      await client.query(
        `UPDATE coach_profiles
            SET first_name='Deleted', last_name='coach', bio_en=NULL, bio_ar=NULL,
                date_of_birth=NULL, nationality=NULL, birth_place=NULL, status='rejected',
                rejection_reason='Account deleted by the coach'
          WHERE user_id = $1`,
        [userId]
      );
    }

    // --- the user row: keep the id (financial rows reference it), erase the rest ---
    await client.query(
      `UPDATE users
          SET email = 'deleted+' || id || '@deleted.invalid',
              phone = NULL,
              password_hash = 'ACCOUNT_DELETED',
              email_verified = FALSE,
              phone_verified = FALSE,
              is_active = FALSE,
              deleted_at = now(),
              updated_at = now()
        WHERE id = $1`,
      [userId]
    );

    await client.query(
      `INSERT INTO account_deletions (user_id, role, requested_by, reason) VALUES ($1,$2,$3,$4)`,
      [userId, role, requestedBy, reason]
    );

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }

  // Any token issued for this account stops working immediately.
  invalidateAccount(userId);

  // --- notifications, outside the transaction ---
  for (const b of upcoming.rows) {
    const other = role === 'member' ? b.coach_id : b.member_id;
    if (!other || other === userId) continue;
    await notify({
      userId: other,
      type: role === 'member' ? 'booking_cancelled_by_member' : 'booking_cancelled_by_coach',
      titleEn: 'Session cancelled',
      titleAr: 'تم إلغاء الجلسة',
      bodyEn: 'A session was cancelled because the other party closed their CoachlyJo account. No class was deducted.',
      bodyAr: 'تم إلغاء جلسة لأن الطرف الآخر أغلق حسابه في كوتشلي جو. لم يتم خصم أي حصة.',
      relatedId: b.id,
      email: true,
    });
  }

  if (role === 'coach') {
    const stranded = await pool.query(
      `SELECT COUNT(*)::int AS n FROM member_packages
        WHERE coach_id = $1 AND status = 'active' AND classes_consumed < classes_total`,
      [userId]
    );
    if (stranded.rows[0].n > 0) {
      await notifyAdmins({
        type: 'admin_new_coach',
        titleEn: 'Coach deleted their account',
        titleAr: 'قام مدرب بحذف حسابه',
        bodyEn: `${stranded.rows[0].n} active package(s) still point at this coach — move them to another coach from the Packages screen.`,
        bodyAr: `ما زالت ${stranded.rows[0].n} باقة فعّالة مرتبطة بهذا المدرب — انقلها إلى مدرب آخر من شاشة الباقات.`,
        relatedId: userId,
        email: true,
      });
    }
  }

  return { deleted: true, cancelledBookings: upcoming.rowCount, role };
}

module.exports = { deleteAccount, DeletionError };
