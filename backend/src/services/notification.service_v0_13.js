// =============================================================================
// Notification service (v0.11 item 2).
//
// Every notification is written to the `notifications` table (the in-app
// notification centre) in English AND Arabic, so the app renders whichever
// language the user is using. When SMTP is configured, notifications marked
// `email: true` are also emailed; without SMTP that is a silent no-op.
//
// Push notifications (FCM/APNs) are deliberately NOT here yet — they need the
// client's Firebase project and Apple certificates. `deliver()` is the single
// place a push call would be added later; nothing else would change.
//
// De-duplication: pass `dedupeKey` for anything that could be generated more
// than once (session reminders run every 15 minutes). A unique index makes a
// repeat insert a no-op.
// =============================================================================
const { pool } = require('../db/pool_v0_13');
const { sendNotificationEmail } = require('./mail.service_v0_13');
const { sendToUser } = require('./push.service_v0_13');

/**
 * Create one notification. Never throws — a failed notification must never
 * break the business action that triggered it.
 *
 * @param {object} n
 * @param {string} n.userId      recipient
 * @param {string} n.type        one of the types allowed by the DB CHECK
 * @param {string} n.titleEn     short title (English)
 * @param {string} n.titleAr     short title (Arabic)
 * @param {string} [n.bodyEn]    detail line (English)
 * @param {string} [n.bodyAr]    detail line (Arabic)
 * @param {string} [n.relatedId] booking / package id, for deep-linking
 * @param {string} [n.dedupeKey] unique logical key; repeat inserts are ignored
 * @param {Date}   [n.scheduledAt] when it becomes relevant (reminders)
 * @param {boolean}[n.email]     also send by email when SMTP is configured
 */
async function notify(n) {
  try {
    const res = await pool.query(
      `INSERT INTO notifications
         (user_id, type, title_en, title_ar, body_en, body_ar, related_id, dedupe_key, scheduled_at, sent_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9, now())
       -- The unique index is partial (dedupe_key IS NOT NULL), so the
       -- predicate must be repeated here for index inference to match.
       ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
       RETURNING id`,
      [n.userId, n.type, n.titleEn, n.titleAr, n.bodyEn || null, n.bodyAr || null,
       n.relatedId || null, n.dedupeKey || null, n.scheduledAt || null]
    );
    if (res.rowCount === 0) return null;   // duplicate — already delivered

    // (v0.14 item 13) Every notification is also an OS push. No-op until
    // Firebase credentials are configured; never blocks the caller.
    sendToUser(n.userId, {
      title: n.titleEn,
      body: n.bodyEn || '',
      type: n.type,
      relatedId: n.relatedId,
    }).catch((err) => console.error(`[notify:push] ${err.message}`));

    if (n.email) await emailNotification(res.rows[0].id, n);
    return res.rows[0].id;
  } catch (err) {
    console.error(`[notify] ${n.type} for ${n.userId}: ${err.message}`);
    return null;
  }
}

async function emailNotification(id, n) {
  try {
    const u = await pool.query(`SELECT email FROM users WHERE id=$1`, [n.userId]);
    if (u.rowCount === 0) return;
    const sent = await sendNotificationEmail({
      to: u.rows[0].email,
      title: n.titleEn,
      body: n.bodyEn || '',
    });
    if (sent.sent) await pool.query(`UPDATE notifications SET emailed_at=now() WHERE id=$1`, [id]);
  } catch (err) {
    console.error(`[notify:email] ${err.message}`);
  }
}

/** Notify every admin (used for new applications / payment requests). */
async function notifyAdmins(n) {
  const admins = await pool.query(`SELECT id FROM users WHERE role='admin'`);
  for (const a of admins.rows) {
    await notify({ ...n, userId: a.id });
  }
}

// ---------------------------------------------------------------------------
// Scheduled session reminders (v0.11): 24 hours and 1 hour before each
// confirmed session, to BOTH the member and the coach. Runs every 15 minutes;
// the dedupe key guarantees one reminder per booking per window.
// ---------------------------------------------------------------------------
const REMINDER_WINDOWS = [
  { key: '24h', hours: 24, labelEn: 'tomorrow', labelAr: 'غداً' },
  { key: '1h', hours: 1, labelEn: 'in 1 hour', labelAr: 'خلال ساعة' },
  // (v0.14 item 13) Final nudge just before the session starts.
  { key: '15m', hours: 0.25, labelEn: 'in 15 minutes', labelAr: 'خلال 15 دقيقة' },
];

async function sendDueReminders() {
  let created = 0;
  for (const w of REMINDER_WINDOWS) {
    // Sessions whose start falls inside [now + h - 15min, now + h].
    const due = await pool.query(
      `SELECT b.id AS booking_id, b.member_id, cs.start_at, cs.coach_id, cs.delivery,
              cp.first_name AS coach_first, cp.last_name AS coach_last,
              mp.first_name AS member_first, mp.last_name AS member_last
         FROM bookings b
         JOIN coach_sessions cs ON cs.id = b.session_id
         JOIN coach_profiles cp ON cp.user_id = cs.coach_id
         JOIN member_profiles mp ON mp.user_id = b.member_id
        WHERE b.status = 'accepted'
          AND cs.start_at > now()
          AND cs.start_at <= now() + ($1 || ' hours')::interval
          AND cs.start_at >  now() + ($1 || ' hours')::interval - ($2 || ' minutes')::interval`,
      [String(w.hours), w.key === '15m' ? '5' : '15']
    );
    for (const r of due.rows) {
      const when = new Date(r.start_at);
      const timeEn = when.toISOString().slice(11, 16) + ' UTC';
      const created1 = await notify({
        userId: r.member_id,
        type: 'session_reminder',
        titleEn: `Session ${w.labelEn}`,
        titleAr: `جلستك ${w.labelAr}`,
        bodyEn: `Your session with ${r.coach_first} ${r.coach_last} starts ${w.labelEn} (${timeEn}).`,
        bodyAr: `جلستك مع ${r.coach_first} ${r.coach_last} تبدأ ${w.labelAr}.`,
        relatedId: r.booking_id,
        dedupeKey: `reminder:${r.booking_id}:member:${w.key}`,
        scheduledAt: r.start_at,
        email: w.key === '24h',
      });
      const created2 = await notify({
        userId: r.coach_id,
        type: 'session_reminder',
        titleEn: `Session ${w.labelEn}`,
        titleAr: `جلستك ${w.labelAr}`,
        bodyEn: `Your session with ${r.member_first} ${r.member_last} starts ${w.labelEn} (${timeEn}).`,
        bodyAr: `جلستك مع ${r.member_first} ${r.member_last} تبدأ ${w.labelAr}.`,
        relatedId: r.booking_id,
        dedupeKey: `reminder:${r.booking_id}:coach:${w.key}`,
        scheduledAt: r.start_at,
        email: w.key === '24h',
      });
      if (created1) created++;
      if (created2) created++;
    }
  }
  if (created > 0) console.log(`[reminders] sent ${created} reminder(s)`);
  return created;
}

// ---------------------------------------------------------------------------
// Package lifecycle notices (v0.11): expiring in 3 days, and expired/finished.
// Runs on the same 15-minute tick; dedupe keys keep it to one per package.
// ---------------------------------------------------------------------------
async function sendPackageNotices() {
  let created = 0;

  const expiring = await pool.query(
    `SELECT mp.id, mp.member_id, mp.expires_at, pd.name_en, pd.name_ar,
            (mp.classes_total - mp.classes_consumed) AS remaining
       FROM member_packages mp JOIN package_definitions pd ON pd.id = mp.package_def_id
      WHERE mp.status='active'
        AND mp.classes_consumed < mp.classes_total
        AND mp.expires_at IS NOT NULL
        AND mp.expires_at > now()
        AND mp.expires_at <= now() + interval '3 days'`);
  for (const p of expiring.rows) {
    const id = await notify({
      userId: p.member_id,
      type: 'package_expiring',
      titleEn: 'Your package expires soon',
      titleAr: 'باقتك على وشك الانتهاء',
      bodyEn: `${p.remaining} class(es) left on ${p.name_en}. It expires on ${new Date(p.expires_at).toISOString().slice(0, 10)}.`,
      bodyAr: `تبقى ${p.remaining} حصة في ${p.name_ar || p.name_en}. تنتهي الصلاحية بتاريخ ${new Date(p.expires_at).toISOString().slice(0, 10)}.`,
      relatedId: p.id,
      dedupeKey: `pkg_expiring:${p.id}`,
      email: true,
    });
    if (id) created++;
  }

  const expired = await pool.query(
    `SELECT mp.id, mp.member_id, pd.name_en, pd.name_ar
       FROM member_packages mp JOIN package_definitions pd ON pd.id = mp.package_def_id
      WHERE mp.status='active' AND mp.expires_at IS NOT NULL AND mp.expires_at <= now()`);
  for (const p of expired.rows) {
    const id = await notify({
      userId: p.member_id,
      type: 'package_expired',
      titleEn: 'Your package has expired',
      titleAr: 'انتهت صلاحية باقتك',
      bodyEn: `${p.name_en} has reached its expiry date.`,
      bodyAr: `انتهت صلاحية ${p.name_ar || p.name_en}.`,
      relatedId: p.id,
      dedupeKey: `pkg_expired:${p.id}`,
    });
    if (id) created++;
  }
  return created;
}

/** One tick of the notification scheduler (called every 15 minutes). */
async function runScheduledNotifications() {
  let n = 0;
  try { n += await sendDueReminders(); } catch (e) { console.error('[reminders]', e.message); }
  try { n += await sendPackageNotices(); } catch (e) { console.error('[pkg-notices]', e.message); }
  return n;
}

module.exports = { notify, notifyAdmins, sendDueReminders, sendPackageNotices, runScheduledNotifications };
