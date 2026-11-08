const express = require('express');
const { pool } = require('../db/pool_v0_13');
const { authenticate, requireRole } = require('../middleware/auth_v0_13');
const schedule = require('../services/schedule.service_v0_13');

// (v0.14 item 3) A coach can do nothing but complete their profile until an
// admin approves them. Enforced here so it cannot be bypassed by the client.
async function requireApprovedCoach(req, res, next) {
  const r = await pool.query(
    `SELECT status, rejection_reason FROM coach_profiles WHERE user_id = $1`, [req.user.id]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'Coach profile not found' });
  const { status, rejection_reason: reason } = r.rows[0];
  if (status === 'approved') return next();
  return res.status(403).json({
    error: status === 'rejected'
      ? `Your application was not approved${reason ? `: ${reason}` : '.'}`
      : 'Awaiting admin approval. You can set your availability once your account is approved.',
    approvalStatus: status,
  });
}

const router = express.Router();

// Upload a verification document reference (spec §4.3).
router.post('/documents', authenticate, requireRole('coach'), async (req, res) => {
  const { docType, fileUrl } = req.body || {};
  const allowed = ['degree_certificate', 'additional_certification', 'experience_proof'];
  if (!allowed.includes(docType) || !fileUrl)
    return res.status(400).json({ error: `docType in ${allowed.join('|')} and fileUrl required` });
  const r = await pool.query(
    `INSERT INTO coach_documents (coach_id, doc_type, file_url) VALUES ($1,$2,$3) RETURNING *`,
    [req.user.id, docType, fileUrl]
  );
  res.status(201).json(r.rows[0]);
});

// =============================================================================
// (v0.5 item 5) Weekly recurring availability — replaces the slot-template
// flow. Coaches toggle days on/off and add time ranges; sessions are generated
// automatically on a rolling 4-week horizon (see schedule.service.js).
// =============================================================================

// =============================================================================
// (v0.14 item 16) Per-WEEK availability, laid out like a calendar.
//
// A coach opens a week, paints the hours they are available on each real date,
// and the bookable sessions for that week are generated from those blocks.
// "Copy last week" exists because most weeks repeat — it is one tap instead of
// re-entering the whole grid.
// =============================================================================

// Monday-based week start for any date (the calendar grid runs Mon..Sun).
function weekStart(dateStr) {
  const d = new Date(`${dateStr}T00:00:00Z`);
  const dow = d.getUTCDay();                 // 0=Sun..6=Sat
  const diff = dow === 0 ? -6 : 1 - dow;     // shift back to Monday
  d.setUTCDate(d.getUTCDate() + diff);
  return d.toISOString().slice(0, 10);
}

function addDays(dateStr, n) {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// GET /availability/week?start=YYYY-MM-DD  (any date inside the wanted week)
router.get('/availability/week', authenticate, requireRole('coach'), requireApprovedCoach, requireApprovedCoach, async (req, res) => {
  const today = new Date().toISOString().slice(0, 10);
  const start = weekStart(req.query.start || today);
  const end = addDays(start, 6);

  const settings = await pool.query(
    `INSERT INTO coach_schedule_settings (coach_id) VALUES ($1)
     ON CONFLICT (coach_id) DO UPDATE SET coach_id = EXCLUDED.coach_id
     RETURNING session_minutes`, [req.user.id]);

  const blocks = await pool.query(
    `SELECT id, on_date::text AS on_date, start_time, end_time, delivery
       FROM coach_availability_days
      WHERE coach_id=$1 AND on_date BETWEEN $2::date AND $3::date
      ORDER BY on_date, start_time`,
    [req.user.id, start, end]);

  // Sessions already generated for this week, so the grid can show which
  // blocks are booked and must not be removed.
  const sessions = await pool.query(
    `SELECT cs.id, cs.start_at, cs.end_at, cs.delivery, cs.generated_from_day,
            (SELECT COUNT(*)::int FROM bookings b
              WHERE b.session_id=cs.id AND b.status IN ('pending','accepted','completed')) AS booked
       FROM coach_sessions cs
      WHERE cs.coach_id=$1
        AND cs.start_at >= $2::date
        AND cs.start_at <  ($3::date + interval '1 day')
      ORDER BY cs.start_at`,
    [req.user.id, start, end]);

  res.json({
    weekStart: start,
    weekEnd: end,
    sessionMinutes: settings.rows[0].session_minutes,
    days: [0, 1, 2, 3, 4, 5, 6].map((i) => {
      const date = addDays(start, i);
      return {
        date,
        isPast: date < today,
        blocks: blocks.rows.filter((b) => b.on_date === date),
      };
    }),
    sessions: sessions.rows,
  });
});

// Add one block of hours on one date.
router.post('/availability/day', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  const { date, startTime, endTime, delivery } = req.body || {};
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date || ''))
    return res.status(400).json({ error: 'date must be YYYY-MM-DD' });
  if (!/^\d{2}:\d{2}$/.test(startTime || '') || !/^\d{2}:\d{2}$/.test(endTime || ''))
    return res.status(400).json({ error: 'startTime and endTime must be HH:MM' });
  if (endTime <= startTime)
    return res.status(400).json({ error: 'End time must be after the start time' });
  if (!['online', 'in_person'].includes(delivery || 'online'))
    return res.status(400).json({ error: 'delivery must be online or in_person' });
  if (date < new Date().toISOString().slice(0, 10))
    return res.status(400).json({ error: 'That date has already passed' });

  const overlap = await pool.query(
    `SELECT 1 FROM coach_availability_days
      WHERE coach_id=$1 AND on_date=$2::date
        AND start_time < $4::time AND end_time > $3::time LIMIT 1`,
    [req.user.id, date, startTime, endTime]);
  if (overlap.rowCount > 0)
    return res.status(409).json({ error: 'These hours overlap hours you already set for that day' });

  const ins = await pool.query(
    `INSERT INTO coach_availability_days (coach_id, on_date, start_time, end_time, delivery)
     VALUES ($1,$2::date,$3,$4,$5) RETURNING id, on_date::text AS on_date, start_time, end_time, delivery`,
    [req.user.id, date, startTime, endTime, delivery || 'online']);
  const gen = await schedule.regenerateForCoach(req.user.id);
  res.status(201).json({ block: ins.rows[0], generated: gen.generated });
});

// Edit one block (drag its edges in the calendar, or flip online/in-person).
router.put('/availability/day/:id', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  const cur = await pool.query(
    `SELECT * FROM coach_availability_days WHERE id=$1 AND coach_id=$2`,
    [req.params.id, req.user.id]);
  if (cur.rowCount === 0) return res.status(404).json({ error: 'Those hours were not found' });
  const b = cur.rows[0];
  const startTime = req.body?.startTime ?? String(b.start_time).slice(0, 5);
  const endTime = req.body?.endTime ?? String(b.end_time).slice(0, 5);
  const delivery = req.body?.delivery ?? b.delivery;
  if (endTime <= startTime)
    return res.status(400).json({ error: 'End time must be after the start time' });

  const overlap = await pool.query(
    `SELECT 1 FROM coach_availability_days
      WHERE coach_id=$1 AND on_date=$2 AND id<>$5
        AND start_time < $4::time AND end_time > $3::time LIMIT 1`,
    [req.user.id, b.on_date, startTime, endTime, b.id]);
  if (overlap.rowCount > 0)
    return res.status(409).json({ error: 'These hours overlap hours you already set for that day' });

  const upd = await pool.query(
    `UPDATE coach_availability_days SET start_time=$3, end_time=$4, delivery=$5
      WHERE id=$1 AND coach_id=$2
      RETURNING id, on_date::text AS on_date, start_time, end_time, delivery`,
    [b.id, req.user.id, startTime, endTime, delivery]);
  const cleanup = await schedule.cleanupDays(req.user.id, [b.id]);
  const gen = await schedule.regenerateForCoach(req.user.id);
  res.json({ block: upd.rows[0], ...cleanup, generated: gen.generated });
});

router.delete('/availability/day/:id', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  const cur = await pool.query(
    `SELECT id FROM coach_availability_days WHERE id=$1 AND coach_id=$2`,
    [req.params.id, req.user.id]);
  if (cur.rowCount === 0) return res.status(404).json({ error: 'Those hours were not found' });
  const cleanup = await schedule.cleanupDays(req.user.id, [req.params.id]);
  await pool.query(`DELETE FROM coach_availability_days WHERE id=$1`, [req.params.id]);
  res.json({ deleted: req.params.id, ...cleanup });
});

// Copy the previous week's hours into the target week — most weeks repeat.
router.post('/availability/copy-week', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  const target = weekStart(req.body?.targetWeek || new Date().toISOString().slice(0, 10));
  const source = addDays(target, -7);
  const today = new Date().toISOString().slice(0, 10);

  const src = await pool.query(
    `SELECT on_date::text AS on_date, start_time, end_time, delivery
       FROM coach_availability_days
      WHERE coach_id=$1 AND on_date BETWEEN $2::date AND $3::date
      ORDER BY on_date, start_time`,
    [req.user.id, source, addDays(source, 6)]);
  if (src.rowCount === 0)
    return res.status(409).json({ error: 'There are no hours in the previous week to copy' });

  let copied = 0, skipped = 0;
  for (const b of src.rows) {
    const newDate = addDays(b.on_date, 7);
    if (newDate < today) { skipped++; continue; }
    const clash = await pool.query(
      `SELECT 1 FROM coach_availability_days
        WHERE coach_id=$1 AND on_date=$2::date
          AND start_time < $4::time AND end_time > $3::time LIMIT 1`,
      [req.user.id, newDate, String(b.start_time).slice(0, 5), String(b.end_time).slice(0, 5)]);
    if (clash.rowCount > 0) { skipped++; continue; }
    await pool.query(
      `INSERT INTO coach_availability_days (coach_id, on_date, start_time, end_time, delivery)
       VALUES ($1,$2::date,$3,$4,$5)`,
      [req.user.id, newDate, b.start_time, b.end_time, b.delivery]);
    copied++;
  }
  const gen = await schedule.regenerateForCoach(req.user.id);
  res.json({ copied, skipped, generated: gen.generated, weekStart: target });
});

// Clear every (unbooked) hour in a week — "I am away next week".
router.delete('/availability/week', authenticate, requireRole('coach'), requireApprovedCoach, requireApprovedCoach, async (req, res) => {
  const start = weekStart(req.query.start || new Date().toISOString().slice(0, 10));
  const ids = await pool.query(
    `SELECT id FROM coach_availability_days
      WHERE coach_id=$1 AND on_date BETWEEN $2::date AND $3::date`,
    [req.user.id, start, addDays(start, 6)]);
  const list = ids.rows.map((r) => r.id);
  const cleanup = await schedule.cleanupDays(req.user.id, list);
  if (list.length > 0) {
    await pool.query(`DELETE FROM coach_availability_days WHERE id = ANY($1::uuid[])`, [list]);
  }
  res.json({ cleared: list.length, ...cleanup });
});

// Session duration for generated sessions (30/45/50/60/90, default 50).
// Changing it rebuilds future UNBOOKED sessions on the new grid.
router.put('/availability/settings', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  const { sessionMinutes } = req.body || {};
  if (![30, 45, 50, 60, 90].includes(sessionMinutes))
    return res.status(400).json({ error: 'sessionMinutes must be one of 30, 45, 50, 60, 90' });
  await pool.query(
    `INSERT INTO coach_schedule_settings (coach_id, session_minutes)
     VALUES ($1, $2)
     ON CONFLICT (coach_id) DO UPDATE SET session_minutes=$2, updated_at=now()`,
    [req.user.id, sessionMinutes]);
  const ids = await pool.query(
    `SELECT id FROM coach_availability_days WHERE coach_id=$1 AND on_date >= CURRENT_DATE`, [req.user.id]);
  const cleanup = await schedule.cleanupDays(req.user.id, ids.rows.map((r) => r.id));
  const gen = await schedule.regenerateForCoach(req.user.id);
  res.json({ sessionMinutes, ...cleanup, generated: gen.generated });
});

// (v0.9 item 2) Member profile + fitness questionnaire for the coach.
// PRIVACY GATE (confirmed with the client): a coach may only open a member who
// has a package with them OR a booking request with them. Past clients stay
// visible so the coach keeps continuity; the wider member directory does not.
router.get('/members/:memberId', authenticate, requireRole('coach'), async (req, res) => {
  const allowed = await pool.query(
    `SELECT 1 WHERE EXISTS (SELECT 1 FROM member_packages mp
                             WHERE mp.member_id=$2 AND mp.coach_id=$1)
             OR EXISTS (SELECT 1 FROM bookings b
                          JOIN coach_sessions cs ON cs.id=b.session_id
                         WHERE b.member_id=$2 AND cs.coach_id=$1)`,
    [req.user.id, req.params.memberId]);
  if (allowed.rowCount === 0)
    return res.status(403).json({ error: 'This member is not one of your clients' });

  const profile = await pool.query(
    `SELECT m.user_id, m.first_name, m.last_name, m.location, m.date_of_birth,
            m.nationality, u.phone, u.email
       FROM member_profiles m JOIN users u ON u.id=m.user_id
      WHERE m.user_id=$1`, [req.params.memberId]);
  if (profile.rowCount === 0) return res.status(404).json({ error: 'Member not found' });

  // Questionnaire answers, paired with the question text (questions can be
  // edited by admin over time; answers keep their original question ids).
  const assess = await pool.query(
    `SELECT responses, submitted_at FROM fitness_assessments
      WHERE member_id=$1 ORDER BY submitted_at DESC LIMIT 1`, [req.params.memberId]);
  // Answers are stored keyed by the question's stable `key`.
  const questions = await pool.query(
    `SELECT key, label_en, label_ar FROM questionnaire_questions ORDER BY sort_order`);

  const responses = assess.rows[0]?.responses || {};
  const answers = questions.rows
    .map((q) => ({ key: q.key, labelEn: q.label_en, labelAr: q.label_ar, answer: responses[q.key] ?? null }))
    .filter((a) => a.answer !== null && `${a.answer}`.trim() !== '');
  // Answers whose question was later removed/renamed are still shown.
  const known = new Set(questions.rows.map((q) => q.key));
  for (const [k, v] of Object.entries(responses)) {
    if (!known.has(k) && v !== null && `${v}`.trim() !== '') {
      answers.push({ key: k, labelEn: k, labelAr: k, answer: v });
    }
  }

  const packages = await pool.query(
    `SELECT mp.id, mp.status, mp.mode, mp.is_single, mp.classes_total, mp.classes_consumed,
            (mp.classes_total - mp.classes_consumed) AS remaining, mp.expires_at,
            pd.name_en, pd.name_ar
       FROM member_packages mp JOIN package_definitions pd ON pd.id=mp.package_def_id
      WHERE mp.member_id=$1 AND mp.coach_id=$2
      ORDER BY mp.requested_at DESC`, [req.params.memberId, req.user.id]);

  res.json({
    profile: profile.rows[0],
    questionnaire: { submittedAt: assess.rows[0]?.submitted_at || null, answers },
    packages: packages.rows,
  });
});

// Coach views their own sessions + booking counts.
router.get('/my-sessions', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  // (v0.6 item 3) ?scope=open — only future slots with no pending/accepted/
  // completed booking. The Sessions tab shows these ("my open bookable
  // times"); actual appointments live in the Requests tab. No scope = all
  // (kept for compatibility and admin/debug use).
  const openOnly = req.query.scope === 'open';
  const r = await pool.query(
    `SELECT cs.*,
            (SELECT COUNT(*) FROM bookings b WHERE b.session_id=cs.id AND b.status IN ('pending','accepted','completed')) AS booked
       FROM coach_sessions cs WHERE cs.coach_id=$1
       ${openOnly ? `AND cs.start_at > now()
        AND NOT EXISTS (SELECT 1 FROM bookings b
                         WHERE b.session_id=cs.id AND b.status IN ('pending','accepted','completed'))` : ''}
       ORDER BY cs.start_at`,
    [req.user.id]
  );
  res.json(r.rows);
});

// Coach views bookings to act on. Once accepted, the coach also sees the member's
// phone + location (item 12) and the Zoom link for online sessions (item 3).
router.get('/bookings', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  const r = await pool.query(
    `SELECT b.id, b.status, b.is_trial, b.rejection_reason, b.completion_kind,
            b.member_package_id,
            (SELECT COUNT(*)::int FROM bookings x
              WHERE x.member_package_id = b.member_package_id AND x.status='rejected') AS pkg_rejects_used,
            cs.start_at, cs.end_at, cs.delivery,
            b.member_id, mp.first_name AS member_first, mp.last_name AS member_last,
            CASE WHEN b.status IN ('accepted','completed') THEN u.phone END   AS member_phone,
            CASE WHEN b.status IN ('accepted','completed') THEN mp.location END AS member_location,
            CASE WHEN b.status IN ('accepted','completed') AND cs.delivery='online'
                 THEN cs.zoom_join_url END AS zoom_join_url
       FROM bookings b
       JOIN coach_sessions cs ON cs.id=b.session_id
       JOIN member_profiles mp ON mp.user_id=b.member_id
       JOIN users u ON u.id=b.member_id
      WHERE cs.coach_id=$1 ORDER BY cs.start_at`,
    [req.user.id]
  );
  res.json(r.rows);
});

// Coach removes a published session — only if it has no active bookings and is
// in the future. This is the "modify availability" action (spec §5.4 / §2.6).
router.delete('/availability/:id', authenticate, requireRole('coach'), async (req, res) => {
  const s = await pool.query(
    `SELECT * FROM coach_sessions WHERE id=$1 AND coach_id=$2`,
    [req.params.id, req.user.id]
  );
  if (s.rowCount === 0) return res.status(404).json({ error: 'Session not found' });
  if (new Date(s.rows[0].start_at) < new Date())
    return res.status(409).json({ error: 'Cannot remove a past session' });

  const booked = await pool.query(
    `SELECT COUNT(*)::int n FROM bookings
      WHERE session_id=$1 AND status IN ('pending','accepted','completed')`,
    [req.params.id]
  );
  if (booked.rows[0].n > 0)
    return res.status(409).json({ error: 'Session has bookings; cannot remove' });

  await pool.query(`DELETE FROM coach_sessions WHERE id=$1`, [req.params.id]);
  res.json({ removed: req.params.id });
});

// (v0.4 item 10) The coach's clients: members who purchased a package FOR this
// coach and had it activated. Split into 'active' and 'completed' (item 4):
// completed = all classes consumed, or the package expired. Contact details are
// visible — a subscriber has paid and been activated (confirmed in v0.4 scope).
router.get('/clients', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  const r = await pool.query(
    `SELECT mp.id AS package_id, mp.status, mp.is_single, mp.mode,
            mp.classes_total, mp.classes_consumed, mp.classes_pending,
            (mp.classes_total - mp.classes_consumed) AS remaining,
            mp.activated_at, mp.expires_at,
            pd.name_en AS package_name,
            m.user_id AS member_id, m.first_name, m.last_name, m.location,
            u.phone, u.email,
            (SELECT MIN(cs.start_at) FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
              WHERE b.member_package_id=mp.id AND b.status IN ('pending','accepted') AND cs.start_at > now()) AS next_session,
            (SELECT MAX(cs.start_at) FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
              WHERE b.member_package_id=mp.id AND b.status='completed') AS last_session,
            (mp.classes_consumed >= mp.classes_total
             OR mp.status='expired'
             OR (mp.expires_at IS NOT NULL AND mp.expires_at < now())) AS is_completed
       FROM member_packages mp
       JOIN member_profiles m ON m.user_id=mp.member_id
       JOIN users u ON u.id=mp.member_id
       JOIN package_definitions pd ON pd.id=mp.package_def_id
      WHERE mp.coach_id=$1 AND mp.status IN ('active','expired')
      ORDER BY (mp.classes_consumed >= mp.classes_total
                OR mp.status='expired'
                OR (mp.expires_at IS NOT NULL AND mp.expires_at < now())) ASC,
               mp.activated_at DESC`,
    [req.user.id]
  );
  res.json(r.rows);
});

// (v0.4 item 9) Coach performance dashboard — activity only, no revenue
// (confirmed in v0.4 scope). ?days=7|30|90 window for the trend + range stats.
router.get('/dashboard', authenticate, requireRole('coach'), requireApprovedCoach, async (req, res) => {
  // (v0.10) Sessions owed from same-day cancellations, for the coach to see.
  const pen = await pool.query(
    `SELECT COALESCE(SUM(sessions), 0)::int AS n FROM coach_penalties
      WHERE coach_id = $1 AND settled_at IS NULL`, [req.user.id]);
  const days = [7, 30, 90].includes(parseInt(req.query.days, 10)) ? parseInt(req.query.days, 10) : 30;
  const id = req.user.id;
  const [upcoming, pendingReq, range, clients, rating, weekly] = await Promise.all([
    // (v0.14 item 17) "Upcoming sessions" means BOOKED appointments, not open
    // slots — a coach with a full week of availability and no clients was
    // seeing a large, meaningless number here.
    pool.query(
      `SELECT COUNT(*)::int n
         FROM bookings b JOIN coach_sessions cs ON cs.id = b.session_id
        WHERE cs.coach_id = $1 AND cs.start_at > now()
          AND b.status IN ('pending','accepted')`, [id]),
    pool.query(
      `SELECT COUNT(*)::int n FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
        WHERE cs.coach_id=$1 AND b.status='pending'`, [id]),
    pool.query(
      `SELECT
         COUNT(*) FILTER (WHERE b.status='completed' AND b.completed_at > now() - ($2 || ' days')::interval)::int AS completed,
         COUNT(*) FILTER (WHERE b.status='cancelled' AND b.cancelled_at > now() - ($2 || ' days')::interval)::int AS cancelled,
         COUNT(*) FILTER (WHERE b.status='rejected'  AND b.decided_at   > now() - ($2 || ' days')::interval)::int AS rejected
        FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
       WHERE cs.coach_id=$1`, [id, String(days)]),
    pool.query(
      `SELECT COUNT(*)::int n FROM member_packages
        WHERE coach_id=$1 AND status='active'
          AND classes_consumed < classes_total
          AND (expires_at IS NULL OR expires_at > now())`, [id]),
    pool.query(`SELECT avg_rating, rating_count FROM coach_profiles WHERE user_id=$1`, [id]),
    pool.query(
      `SELECT to_char(date_trunc('week', b.completed_at), 'DD Mon') AS week,
              date_trunc('week', b.completed_at) AS week_start,
              COUNT(*)::int AS completed
         FROM bookings b JOIN coach_sessions cs ON cs.id=b.session_id
        WHERE cs.coach_id=$1 AND b.status='completed'
          AND b.completed_at > now() - ($2 || ' days')::interval
        GROUP BY 1, 2 ORDER BY 2`, [id, String(days)]),
  ]);
  const r = range.rows[0];
  const decided = r.completed + r.cancelled + r.rejected;
  res.json({
    days,
    upcomingSessions: upcoming.rows[0].n,   // booked only, as of v0.14
    upcomingBooked: upcoming.rows[0].n,
    pendingRequests: pendingReq.rows[0].n,
    completed: r.completed,
    cancelled: r.cancelled,
    rejected: r.rejected,
    completionRate: decided > 0 ? Math.round((r.completed / decided) * 100) : null,
    activeClients: clients.rows[0].n,
    avgRating: rating.rows[0]?.avg_rating ?? 0,
    ratingCount: rating.rows[0]?.rating_count ?? 0,
    weeklyCompleted: weekly.rows,
    // (v0.10) Sessions owed from same-day cancellations, not yet settled.
    penaltySessions: pen.rows[0].n,
  });
});

// Coach reads/updates own profile (item 4 — "About for coaches").
router.get('/profile', authenticate, requireRole('coach'), async (req, res) => {
  const r = await pool.query(
    `SELECT user_id, first_name, last_name, nationality, bio_en, bio_ar, status, avg_rating, rating_count
       FROM coach_profiles WHERE user_id=$1`, [req.user.id]);
  res.json(r.rows[0] || null);
});

router.put('/profile', authenticate, requireRole('coach'), async (req, res) => {
  const { bioEn, bioAr } = req.body || {};
  const r = await pool.query(
    `UPDATE coach_profiles SET bio_en=COALESCE($2,bio_en), bio_ar=COALESCE($3,bio_ar)
      WHERE user_id=$1 RETURNING user_id, bio_en, bio_ar`,
    [req.user.id, bioEn, bioAr]
  );
  res.json(r.rows[0]);
});

module.exports = router;
