// =============================================================================
// Booking service — implements the credit-counter contract from spec §7, §8, §9.
//
// Counter moves (all inside one transaction per event):
//   book            -> classes_pending += 1
//   coach accept    -> (no counter change; roster/booking flips to accepted)
//   coach reject    -> classes_pending -= 1                       (no deduction)
//   complete        -> classes_pending -= 1, classes_consumed += 1 (deduction)
//   same-day cancel -> classes_pending -= 1, classes_consumed += 1 (deduction)
//   early cancel    -> classes_pending -= 1                       (no deduction)
//
// Bookability: classes_total - classes_consumed - classes_pending > 0
//              AND session.start_at <= package.expires_at   (spec §9.5)
// The DB CHECK (consumed + pending <= total) is the final backstop.
// =============================================================================

const { withTransaction, pool } = require('../db/pool_v0_13');

// ---- v0.10 policy limits (published on the in-app Rules page) --------------
const CLIENT_CANCEL_LIMIT = 3;   // member cancellations allowed per package
const COACH_REJECT_LIMIT = 3;    // coach rejections allowed per client package
const LATE_CANCEL_HOURS = 24;    // inside this window a cancellation deducts

class BookingError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

// Returns true if `whenTs` falls on the same calendar day as now, in platform tz.
function isSameDay(whenTs, tz = 'Asia/Amman') {
  const fmt = (d) =>
    new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
  return fmt(new Date(whenTs)) === fmt(new Date());
}

async function createBooking({ memberId, sessionId }) {
  return withTransaction(async (client) => {
    // Lock the session row to safely check capacity.
    const sRes = await client.query(
      `SELECT cs.*, cp.status AS coach_status
         FROM coach_sessions cs
         JOIN coach_profiles cp ON cp.user_id = cs.coach_id
        WHERE cs.id = $1 FOR UPDATE OF cs`,
      [sessionId]
    );
    if (sRes.rowCount === 0) throw new BookingError('Session not found', 404);
    const session = sRes.rows[0];
    if (session.coach_status !== 'approved') throw new BookingError('Coach is not approved', 403);

    if (new Date(session.start_at) < new Date())
      throw new BookingError('Session is in the past', 400);

    // Capacity check (1-on-1 => cap 1; group => cap>1) — spec §5.2.
    const countRes = await client.query(
      `SELECT COUNT(*)::int AS n FROM bookings
        WHERE session_id = $1 AND status IN ('pending','accepted','completed')`,
      [sessionId]
    );
    if (countRes.rows[0].n >= session.capacity)
      throw new BookingError('Session is full', 409);

    // Prevent double-booking the same session.
    const dupe = await client.query(
      `SELECT 1 FROM bookings WHERE member_id = $1 AND session_id = $2
         AND status IN ('pending','accepted','completed')`,
      [memberId, sessionId]
    );
    if (dupe.rowCount > 0) throw new BookingError('Already booked this session', 409);

    // (item 11) Pre-booking cap: at most 3 concurrent upcoming bookings
    // (pending or accepted), regardless of package size.
    const upcoming = await client.query(
      `SELECT COUNT(*)::int n FROM bookings b
         JOIN coach_sessions cs ON cs.id = b.session_id
        WHERE b.member_id = $1 AND b.status IN ('pending','accepted')
          AND cs.start_at > now()`,
      [memberId]
    );
    if (upcoming.rows[0].n >= 3)
      throw new BookingError('You can have at most 3 upcoming bookings at a time', 409);

    // (v0.4 item 7) Packages are coach-bound: the booking must consume a package
    // purchased FOR THIS COACH. Find an active, non-expired package for this
    // coach whose mode matches the session, and lock it.
    const pkg = await client.query(
      `SELECT * FROM member_packages
        WHERE member_id = $1 AND status = 'active'
          AND coach_id = $2
          AND (expires_at IS NULL OR expires_at > now())
          AND (classes_total - classes_consumed - classes_pending) > 0
          AND mode = $3
        ORDER BY is_single DESC, expires_at ASC NULLS LAST
        LIMIT 1 FOR UPDATE`,
      [memberId, session.coach_id, session.delivery]
    );

    if (pkg.rowCount === 0) {
      // Layered friendly errors (items 5, 7):
      // 1) Package with this coach exists but wrong mode -> mode-mismatch message.
      const sameCoach = await client.query(
        `SELECT mode FROM member_packages
          WHERE member_id = $1 AND status = 'active' AND coach_id = $2
            AND (expires_at IS NULL OR expires_at > now())
            AND (classes_total - classes_consumed - classes_pending) > 0
          LIMIT 1`,
        [memberId, session.coach_id]
      );
      if (sameCoach.rowCount > 0) {
        const m = sameCoach.rows[0].mode;
        throw new BookingError(
          m === 'online' ? 'You can only book an online session' : 'You can only book an in-person session',
          409
        );
      }
      // 2) Active package(s) exist but with a different coach.
      const otherCoach = await client.query(
        `SELECT 1 FROM member_packages
          WHERE member_id = $1 AND status = 'active'
            AND (expires_at IS NULL OR expires_at > now())
            AND (classes_total - classes_consumed - classes_pending) > 0
          LIMIT 1`,
        [memberId]
      );
      if (otherCoach.rowCount > 0)
        throw new BookingError(
          'Your active package is with a different coach. Packages are purchased per coach — buy a package with this coach to book their sessions.',
          409
        );
      // 3) No usable package at all.
      throw new BookingError('No active package with this coach. Please purchase a package for this coach first.', 402);
    }

    const p = pkg.rows[0];
    // Cannot book a session dated after the package expiry (spec §9.5).
    if (p.expires_at && new Date(session.start_at) > new Date(p.expires_at))
      throw new BookingError('Session is after your package expires', 400);

    const memberPackageId = p.id;
    // Place the hold: classes_pending += 1. The DB CHECK backstops overbooking.
    await client.query(
      `UPDATE member_packages SET classes_pending = classes_pending + 1 WHERE id = $1`,
      [memberPackageId]
    );

    const ins = await client.query(
      `INSERT INTO bookings (member_id, session_id, member_package_id, is_trial, status)
       VALUES ($1, $2, $3, FALSE, 'pending') RETURNING *`,
      [memberId, sessionId, memberPackageId]
    );
    return ins.rows[0];
  });
}

async function coachDecision({ bookingId, coachId, accept, rejectionReason }) {
  return withTransaction(async (client) => {
    const b = await lockBookingForCoach(client, bookingId, coachId, 'pending');

    if (accept) {
      const upd = await client.query(
        `UPDATE bookings SET status = 'accepted', decided_at = now()
          WHERE id = $1 RETURNING *`,
        [bookingId]
      );
      // For group sessions, also flag the roster as approved (spec §6.3).
      await client.query(
        `UPDATE coach_sessions SET roster_approved = TRUE
          WHERE id = $1 AND capacity > 1`,
        [upd.rows[0].session_id]
      );
      return upd.rows[0];
    }

    if (!rejectionReason || !rejectionReason.trim())
      throw new BookingError('Rejection reason is required', 400);

    // (v0.10 item 2) A coach may reject at most 3 requests per package for the
    // same client. After that they must accept or cancel the session (a
    // same-day cancellation carries a penalty).
    if (b.member_package_id) {
      const used = await client.query(
        `SELECT COUNT(*)::int AS n FROM bookings
          WHERE member_package_id = $1 AND status = 'rejected'`,
        [b.member_package_id]
      );
      if (used.rows[0].n >= COACH_REJECT_LIMIT) {
        throw new BookingError(
          `You have already rejected ${COACH_REJECT_LIMIT} requests on this client's package, which is the limit. Please accept the request, or cancel it with a reason.`,
          409
        );
      }
    }

    // Reject: release hold, no deduction (spec §6.4, §7.5).
    await releaseHold(client, b);
    const upd = await client.query(
      `UPDATE bookings SET status = 'rejected', rejection_reason = $2, decided_at = now()
        WHERE id = $1 RETURNING *`,
      [bookingId, rejectionReason.trim()]
    );
    return upd.rows[0];
  });
}

// (v0.7 item 2) Anti-fraud completion:
//   * A coach can only complete AFTER the session's end time (server-enforced,
//     cannot be bypassed by a modified client).
//   * noShow=true records a member no-show. The class is STILL deducted — the
//     member reserved and wasted the slot; releasing it would let members skip
//     sessions for free. Reviews are blocked for no-shows (route-level).
async function completeBooking({ bookingId, coachId, noShow = false, kind = null }) {
  return withTransaction(async (client) => {
    const b = await lockBookingForCoach(client, bookingId, coachId, 'accepted');
    const sess = await client.query(`SELECT end_at FROM coach_sessions WHERE id=$1`, [b.session_id]);
    if (new Date(sess.rows[0].end_at) > new Date()) {
      throw new BookingError('The session has not ended yet — it can be marked completed (or no-show) only after its end time', 409);
    }
    // Deduct: pending -= 1, consumed += 1 (spec §7.3) — same for no-show.
    if (b.member_package_id) {
      await client.query(
        `UPDATE member_packages
            SET classes_pending = classes_pending - 1,
                classes_consumed = classes_consumed + 1
          WHERE id = $1`,
        [b.member_package_id]
      );
    }
    const upd = await client.query(
      `UPDATE bookings SET status = 'completed', completed_at = now(), completion_kind = $2
        WHERE id = $1 RETURNING *`,
      [bookingId, kind || (noShow ? 'no_show' : 'coach')]
    );
    return upd.rows[0];
  });
}

// (v0.7 item 2) If the coach presses neither button, accepted bookings
// auto-complete 48 hours after the session end (run at startup + every 6h).
// The member presumably attended; disputes go to the admin.
const AUTO_COMPLETE_HOURS = 48;
async function autoCompleteOverdue() {
  const due = await pool.query(
    `SELECT b.id, cs.coach_id FROM bookings b
       JOIN coach_sessions cs ON cs.id = b.session_id
      WHERE b.status = 'accepted' AND cs.end_at < now() - interval '${AUTO_COMPLETE_HOURS} hours'`
  );
  let done = 0;
  for (const row of due.rows) {
    try {
      await completeBooking({ bookingId: row.id, coachId: row.coach_id, kind: 'auto' });
      done++;
    } catch (err) {
      console.error(`[auto-complete] booking ${row.id}: ${err.message}`);
    }
  }
  if (done > 0) console.log(`[auto-complete] completed ${done} overdue booking(s)`);
  return done;
}

// (v0.10 item 2) Client cancellation policy — published on the Rules page:
//   * more than 24 hours before the session  -> no class deducted
//   * within 24 hours of the session         -> class deducted
//   * at most 3 cancellations per package    -> the 4th is refused
// The 24-hour window replaces the old same-day rule so the app matches the
// rules the client publishes to members.

async function cancelBooking({ bookingId, memberId }) {
  return withTransaction(async (client) => {
    const res = await client.query(
      `SELECT b.*, cs.start_at FROM bookings b
         JOIN coach_sessions cs ON cs.id = b.session_id
        WHERE b.id = $1 AND b.member_id = $2 FOR UPDATE OF b`,
      [bookingId, memberId]
    );
    if (res.rowCount === 0) throw new BookingError('Booking not found', 404);
    const b = res.rows[0];
    if (!['pending', 'accepted'].includes(b.status))
      throw new BookingError(`Cannot cancel a ${b.status} booking`, 409);

    // Cap: only the member's OWN cancellations on this package count — coach
    // and admin cancellations never consume the member's allowance.
    if (b.member_package_id) {
      const used = await client.query(
        `SELECT COUNT(*)::int AS n FROM bookings
          WHERE member_package_id = $1 AND status = 'cancelled'
            AND (cancelled_by = 'member' OR cancelled_by IS NULL)`,
        [b.member_package_id]
      );
      if (used.rows[0].n >= CLIENT_CANCEL_LIMIT) {
        throw new BookingError(
          `You have already cancelled ${CLIENT_CANCEL_LIMIT} sessions on this package, which is the limit. Please contact your coach if you cannot attend.`,
          409
        );
      }
    }

    // Late = the session starts within the next 24 hours.
    const hoursUntil = (new Date(b.start_at) - new Date()) / 3600000;
    const late = hoursUntil < LATE_CANCEL_HOURS;

    if (b.member_package_id) {
      if (late) {
        // Within 24h: the class is consumed.
        await client.query(
          `UPDATE member_packages
              SET classes_pending = classes_pending - 1,
                  classes_consumed = classes_consumed + 1
            WHERE id = $1`,
          [b.member_package_id]
        );
      } else {
        // More than 24h ahead: release the hold, no deduction.
        await client.query(
          `UPDATE member_packages SET classes_pending = classes_pending - 1 WHERE id = $1`,
          [b.member_package_id]
        );
      }
    }

    const upd = await client.query(
      `UPDATE bookings SET status = 'cancelled', cancel_kind = $2, cancelled_at = now(),
                           cancelled_by = 'member'
        WHERE id = $1 RETURNING *`,
      [bookingId, late ? 'same_day' : 'early']
    );
    return upd.rows[0];
  });
}

// (v0.10 item 2) Coach cancels an accepted/pending session.
//   * the member is NEVER charged a class (the hold is released);
//   * cancelling on the SAME DAY as the appointment records a penalty of one
//     session against the coach for the admin to settle (CoachlyJo has no payout
//     ledger yet, so this is the audit record the client asked for);
//   * a reason is required and is shown to the member.
async function coachCancelBooking({ bookingId, coachId, reason, tz = 'Asia/Amman' }) {
  if (!reason || !String(reason).trim()) throw new BookingError('A reason is required', 400);
  return withTransaction(async (client) => {
    const res = await client.query(
      `SELECT b.*, cs.start_at FROM bookings b
         JOIN coach_sessions cs ON cs.id = b.session_id
        WHERE b.id = $1 AND cs.coach_id = $2 FOR UPDATE OF b`,
      [bookingId, coachId]
    );
    if (res.rowCount === 0) throw new BookingError('Booking not found', 404);
    const b = res.rows[0];
    if (!['pending', 'accepted'].includes(b.status))
      throw new BookingError(`Cannot cancel a ${b.status} booking`, 409);

    // Member keeps the class in every case.
    if (b.member_package_id) {
      await client.query(
        `UPDATE member_packages SET classes_pending = GREATEST(classes_pending - 1, 0) WHERE id = $1`,
        [b.member_package_id]
      );
    }

    const sameDay = isSameDay(b.start_at, tz);
    const upd = await client.query(
      `UPDATE bookings SET status='cancelled', cancel_kind='coach', cancelled_at=now(),
                           cancelled_by='coach', rejection_reason=$2
        WHERE id=$1 RETURNING *`,
      [bookingId, String(reason).trim()]
    );
    if (sameDay) {
      await client.query(
        `INSERT INTO coach_penalties (coach_id, booking_id, sessions, reason)
         VALUES ($1, $2, 1, $3)`,
        [coachId, bookingId, `Same-day cancellation: ${String(reason).trim()}`]
      );
    }
    return { ...upd.rows[0], penalty: sameDay };
  });
}

// ---- helpers -------------------------------------------------------------

async function lockBookingForCoach(client, bookingId, coachId, expectedStatus) {
  const res = await client.query(
    `SELECT b.* FROM bookings b
       JOIN coach_sessions cs ON cs.id = b.session_id
      WHERE b.id = $1 AND cs.coach_id = $2 FOR UPDATE OF b`,
    [bookingId, coachId]
  );
  if (res.rowCount === 0) throw new BookingError('Booking not found for this coach', 404);
  const b = res.rows[0];
  if (b.status !== expectedStatus)
    throw new BookingError(`Booking is '${b.status}', expected '${expectedStatus}'`, 409);
  return b;
}

async function releaseHold(client, booking) {
  if (booking.member_package_id) {
    await client.query(
      `UPDATE member_packages SET classes_pending = classes_pending - 1 WHERE id = $1`,
      [booking.member_package_id]
    );
  }
}

module.exports = {
  BookingError,
  createBooking,
  coachDecision,
  completeBooking,
  autoCompleteOverdue,
  cancelBooking,
  coachCancelBooking,
  CLIENT_CANCEL_LIMIT,
  COACH_REJECT_LIMIT,
};
