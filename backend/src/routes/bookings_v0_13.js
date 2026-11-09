const express = require('express');
const { pool } = require('../db/pool_v0_13');
const { authenticate, requireRole } = require('../middleware/auth_v0_13');
const svc = require('../services/booking.service_v0_13');
const { generateZoomLink } = require('../services/zoom.service_v0_13');
const { notify, notifyAdmins } = require('../services/notification.service_v0_13');
const { profileStatus } = require('./profile_v0_13');

// (v0.14 item 2) Booking also requires a completed profile — the coach needs
// the questionnaire answers to run the session safely.
async function requireCompleteProfile(req, res, next) {
  const st = await profileStatus(req.user.id, 'member');
  if (st.complete) return next();
  return res.status(403).json({
    error: 'Please complete your profile first.',
    profileIncomplete: true,
    missing: st.missing,
  });
}

const router = express.Router();

function handle(res, err) {
  if (err instanceof svc.BookingError) return res.status(err.status).json({ error: err.message });
  console.error(err);
  return res.status(500).json({ error: err.message });
}

// Member books a session against an active package (v0.2 — no free trial) — spec §6.
router.post('/', authenticate, requireRole('member'), requireCompleteProfile, async (req, res) => {
  const { sessionId } = req.body || {};
  if (!sessionId) return res.status(400).json({ error: 'sessionId required' });
  try {
    const booking = await svc.createBooking({ memberId: req.user.id, sessionId });

    // For online sessions, create the Zoom meeting and attach it (spec §11).
    // v0.5: passes real meeting details (topic, start, duration) for the live
    // Zoom API; without credentials a placeholder is generated (see service).

    // (v0.11) Tell the coach a request is waiting.
    const info = await pool.query(
      `SELECT cs.coach_id, cs.start_at, mp.first_name, mp.last_name
         FROM coach_sessions cs, member_profiles mp
        WHERE cs.id = $1 AND mp.user_id = $2`, [sessionId, req.user.id]);
    if (info.rowCount > 0) {
      const i = info.rows[0];
      await notify({
        userId: i.coach_id,
        type: 'booking_requested',
        titleEn: 'New booking request',
        titleAr: 'طلب حجز جديد',
        bodyEn: `${i.first_name} ${i.last_name} requested the session on ${new Date(i.start_at).toISOString().slice(0, 16).replace('T', ' ')}.`,
        bodyAr: `طلب ${i.first_name} ${i.last_name} حجز جلسة.`,
        relatedId: booking.id,
        email: true,
      });
    }
    res.status(201).json(booking);
  } catch (err) { handle(res, err); }
});

// Coach accepts or rejects (spec §6.3, §6.4).
// Coach accepts or rejects.
// For ONLINE sessions, a real Zoom meeting is created before acceptance.
// If Zoom creation fails, the booking stays pending rather than being
// accepted with a broken/fake meeting link.
router.post(
  '/:id/decision',
  authenticate,
  requireRole('coach'),
  async (req, res) => {
    const { accept, rejectionReason } = req.body || {};
    let zoomPending = false;

    try {
      if (accept) {
        // Only prepare Zoom for a valid pending booking belonging to this coach.
        const sessionResult = await pool.query(
          `SELECT
              b.id AS booking_id,
              b.status AS booking_status,
              cs.id AS session_id,
              cs.delivery,
              cs.zoom_join_url,
              cs.start_at,
              cs.end_at,
              cp.first_name AS coach_first,
              cp.last_name AS coach_last
           FROM bookings b
           JOIN coach_sessions cs
             ON cs.id = b.session_id
           JOIN coach_profiles cp
             ON cp.user_id = cs.coach_id
          WHERE b.id = $1
            AND cs.coach_id = $2
            AND b.status = 'pending'
          LIMIT 1`,
          [req.params.id, req.user.id]
        );

        // If no valid pending booking is found, let coachDecision()
        // return the normal booking error below.
        if (sessionResult.rowCount > 0) {
          const row = sessionResult.rows[0];

          if (
            row.delivery === 'online' &&
            !row.zoom_join_url
          ) {
            const durationMinutes = Math.max(
              15,
              Math.round(
                (new Date(row.end_at) -
                  new Date(row.start_at)) /
                  60000
              )
            );

            // (v0.14) Zoom failure must NOT block the booking.
            //
            // Creating the meeting first is right — we never show a fake link.
            // But throwing here meant a coach could not accept ANY online
            // session whenever Zoom was unconfigured or briefly down, which
            // stopped the core flow dead. Instead we accept the booking and
            // leave the link empty: the app shows "meeting link pending" and
            // the coach can add their own link, while this stays logged.
            try {
              const link = await generateZoomLink(
                row.session_id,
                {
                  topic:
                    `CoachlyJo session with ` +
                    `${row.coach_first} ${row.coach_last}`,
                  startAt: row.start_at,
                  durationMinutes,
                }
              );

              await pool.query(
                `UPDATE coach_sessions
                    SET zoom_meeting_id=$2,
                        zoom_join_url=$3,
                        zoom_start_url=$4
                  WHERE id=$1`,
                [
                  row.session_id,
                  link.meetingId,
                  link.joinUrl,
                  link.startUrl,
                ]
              );
            } catch (zoomErr) {
              console.error(
                `[ZOOM] Could not create a meeting for session ${row.session_id}: ` +
                `${zoomErr.message} — accepting the booking without a link.`
              );
              zoomPending = true;
            }
          }
        }
      }

      const b = await svc.coachDecision({
        bookingId: req.params.id,
        coachId: req.user.id,
        accept: !!accept,
        rejectionReason,
      });

      // Tell the member the outcome.
      const who = await pool.query(
        `SELECT
            cp.first_name,
            cp.last_name,
            cs.start_at
           FROM coach_sessions cs
           JOIN coach_profiles cp
             ON cp.user_id = cs.coach_id
          WHERE cs.id = $1`,
        [b.session_id]
      );

      const c = who.rows[0] || {};

      await notify({
        userId: b.member_id,
        type: accept
          ? 'booking_accepted'
          : 'booking_rejected',
        titleEn: accept
          ? 'Booking confirmed'
          : 'Booking declined',
        titleAr: accept
          ? 'تم تأكيد الحجز'
          : 'تم رفض الحجز',
        bodyEn: accept
          ? `${c.first_name} ${c.last_name} confirmed your session.`
          : `${c.first_name} ${c.last_name} declined your request: ${b.rejection_reason}`,
        bodyAr: accept
          ? `أكد ${c.first_name} ${c.last_name} جلستك.`
          : `رفض ${c.first_name} ${c.last_name} طلبك: ${b.rejection_reason}`,
        relatedId: b.id,
        email: true,
      });

      res.json({ ...b, zoomPending });
    } catch (err) {
      handle(res, err);
    }
  }
);

// (v0.15) Retry automatic Zoom creation for a booking whose link is missing —
// used after fixing configuration, so a coach does not have to cancel and
// rebook to get a working link.
router.post('/:id/retry-meeting-link', authenticate, requireRole('coach'), async (req, res) => {
  const r = await pool.query(
    `SELECT cs.id AS session_id, cs.start_at, cs.end_at, cs.delivery, cs.zoom_join_url,
            b.member_id, cp.first_name, cp.last_name
       FROM bookings b
       JOIN coach_sessions cs ON cs.id = b.session_id
       JOIN coach_profiles cp ON cp.user_id = cs.coach_id
      WHERE b.id = $1 AND cs.coach_id = $2 AND b.status = 'accepted'`,
    [req.params.id, req.user.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Accepted booking not found' });
  const row = r.rows[0];
  if (row.delivery !== 'online')
    return res.status(409).json({ error: 'This is an in-person session' });
  if (row.zoom_join_url)
    return res.status(409).json({ error: 'This session already has a link' });

  const durationMinutes = Math.max(
    15, Math.round((new Date(row.end_at) - new Date(row.start_at)) / 60000));
  try {
    const link = await generateZoomLink(row.session_id, {
      topic: `CoachlyJo session with ${row.first_name} ${row.last_name}`,
      startAt: row.start_at,
      durationMinutes,
    });
    await pool.query(
      `UPDATE coach_sessions SET zoom_meeting_id=$2, zoom_join_url=$3, zoom_start_url=$4
        WHERE id=$1`,
      [row.session_id, link.meetingId, link.joinUrl, link.startUrl]);
    await notify({
      userId: row.member_id,
      type: 'zoom_link',
      titleEn: 'Your session link is ready',
      titleAr: 'رابط جلستك جاهز',
      bodyEn: 'The meeting link for your upcoming session is now available.',
      bodyAr: 'أصبح رابط الاجتماع لجلستك القادمة متاحاً.',
      relatedId: req.params.id,
      email: true,
    });
    res.json({ created: true, joinUrl: link.joinUrl, placeholder: link.placeholder === true });
  } catch (err) {
    // Surface the real reason so the coach knows to paste a link instead.
    res.status(502).json({
      error: 'Zoom could not create the meeting. Add your own link instead, and tell CoachlyJo support.',
      detail: err.message,
    });
  }
});

// (v0.14) Coach supplies their own meeting link when automatic creation failed,
// or wants to use Google Meet / their personal Zoom room instead.
router.put('/:id/meeting-link', authenticate, requireRole('coach'), async (req, res) => {
  const { joinUrl } = req.body || {};
  if (!joinUrl || !/^https?:\/\/[^\s]+$/i.test(joinUrl))
    return res.status(400).json({ error: 'Please paste a valid meeting link' });

  const r = await pool.query(
    `UPDATE coach_sessions cs
        SET zoom_join_url = $3, zoom_start_url = $3
       FROM bookings b
      WHERE b.id = $1 AND b.session_id = cs.id AND cs.coach_id = $2
      RETURNING cs.id, b.member_id`,
    [req.params.id, req.user.id, joinUrl.trim()]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Booking not found' });

  await notify({
    userId: r.rows[0].member_id,
    type: 'zoom_link',
    titleEn: 'Your session link is ready',
    titleAr: 'رابط جلستك جاهز',
    bodyEn: 'Your coach added the meeting link for your upcoming session.',
    bodyAr: 'أضاف مدربك رابط الاجتماع لجلستك القادمة.',
    relatedId: req.params.id,
    email: true,
  });
  res.json({ updated: true });
});
// Coach marks completed -> deduct a class (spec §6.6, §7.3).
router.post('/:id/complete', authenticate, requireRole('coach'), async (req, res) => {
  try {
    // (v0.7 item 2) Optional { noShow: true } — member did not attend.
    const b = await svc.completeBooking({
      bookingId: req.params.id, coachId: req.user.id, noShow: req.body?.noShow === true });
    if (b.completion_kind === 'no_show') {
      await notify({
        userId: b.member_id,
        type: 'no_show_recorded',
        titleEn: 'Session marked as no-show',
        titleAr: 'تم تسجيل عدم الحضور',
        bodyEn: 'Your coach reported that you did not attend. The class was deducted from your package.',
        bodyAr: 'أفاد مدربك بأنك لم تحضر. تم خصم الحصة من باقتك.',
        relatedId: b.id,
        email: true,
      });
    }
    res.json(b);
  } catch (err) { handle(res, err); }
});

// (v0.10 item 2) Coach cancels an accepted/pending session. The member is
// never charged; a same-day cancellation records a penalty on the coach.
router.post('/:id/coach-cancel', authenticate, requireRole('coach'), async (req, res) => {
  try {
    const b = await svc.coachCancelBooking({
      bookingId: req.params.id, coachId: req.user.id, reason: req.body?.reason });
    const c = await pool.query(`SELECT first_name, last_name FROM coach_profiles WHERE user_id=$1`, [req.user.id]);
    const cn = c.rows[0] || {};
    await notify({
      userId: b.member_id,
      type: 'booking_cancelled_by_coach',
      titleEn: 'Your coach cancelled a session',
      titleAr: 'ألغى مدربك الجلسة',
      bodyEn: `${cn.first_name} ${cn.last_name} cancelled your session: ${b.rejection_reason}. No class was deducted — you can book another slot.`,
      bodyAr: `ألغى ${cn.first_name} ${cn.last_name} جلستك: ${b.rejection_reason}. لم يتم خصم أي حصة — يمكنك حجز موعد آخر.`,
      relatedId: b.id,
      email: true,
    });
    if (b.penalty) {
      await notify({
        userId: req.user.id,
        type: 'penalty_recorded',
        titleEn: 'One session recorded against you',
        titleAr: 'تم تسجيل جلسة عليك',
        bodyEn: 'You cancelled a session on the same day, so one session was recorded against you as per the rules.',
        bodyAr: 'قمت بإلغاء جلسة في نفس اليوم، لذلك تم تسجيل جلسة واحدة عليك وفقاً للقواعد.',
        relatedId: b.id,
      });
      await notifyAdmins({
        type: 'admin_coach_same_day_cancel',
        titleEn: 'Coach cancelled on the same day',
        titleAr: 'إلغاء من المدرب في نفس اليوم',
        bodyEn: `${cn.first_name} ${cn.last_name} cancelled a session on the same day — one session owed.`,
        bodyAr: `ألغى ${cn.first_name} ${cn.last_name} جلسة في نفس اليوم — جلسة مستحقة.`,
        relatedId: b.id,
      });
    }
    res.json(b);
  } catch (err) { handle(res, err); }
});

// Member cancels (within 24h => deduction, max 3 per package) — v0.10 rules.
router.post('/:id/cancel', authenticate, requireRole('member'), async (req, res) => {
  try {
    const b = await svc.cancelBooking({ bookingId: req.params.id, memberId: req.user.id });
    const ctx = await pool.query(
      `SELECT cs.coach_id, cs.start_at, mp.first_name, mp.last_name
         FROM coach_sessions cs JOIN member_profiles mp ON mp.user_id = $2
        WHERE cs.id = $1`, [b.session_id, req.user.id]);
    if (ctx.rowCount > 0) {
      const i = ctx.rows[0];
      await notify({
        userId: i.coach_id,
        type: 'booking_cancelled_by_member',
        titleEn: 'Session cancelled by client',
        titleAr: 'ألغى العميل الجلسة',
        bodyEn: `${i.first_name} ${i.last_name} cancelled the session on ${new Date(i.start_at).toISOString().slice(0, 16).replace('T', ' ')}.`,
        bodyAr: `ألغى ${i.first_name} ${i.last_name} الجلسة.`,
        relatedId: b.id,
        email: true,
      });
    }
    res.json(b);
  } catch (err) { handle(res, err); }
});

// Member leaves a review — only after completed (spec §12).
router.post('/:id/review', authenticate, requireRole('member'), async (req, res) => {
  const { rating, comment } = req.body || {};
  if (!rating || rating < 1 || rating > 5) return res.status(400).json({ error: 'rating 1..5 required' });
  const b = await pool.query(
    `SELECT b.*, cs.coach_id FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
      WHERE b.id=$1 AND b.member_id=$2`,
    [req.params.id, req.user.id]
  );
  if (b.rowCount === 0) return res.status(404).json({ error: 'Booking not found' });
  if (b.rows[0].status !== 'completed')
    return res.status(409).json({ error: 'Can only review a completed session' });
  if (b.rows[0].completion_kind === 'no_show')
    return res.status(409).json({ error: 'This session was recorded as a no-show and cannot be reviewed' });
  try {
    const r = await pool.query(
      `INSERT INTO reviews (booking_id, member_id, coach_id, rating, comment) VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [req.params.id, req.user.id, b.rows[0].coach_id, rating, comment || null]
    );
    res.status(201).json(r.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Already reviewed this session' });
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
