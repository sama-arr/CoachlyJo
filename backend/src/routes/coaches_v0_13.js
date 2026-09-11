const express = require('express');
const { pool } = require('../db/pool_v0_13');
const { authenticate, requireRole } = require('../middleware/auth_v0_13');
const schedule = require('../services/schedule.service_v0_13');

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

// Full availability state for the Availability screen.
router.get('/availability', authenticate, requireRole('coach'), async (req, res) => {
  const settings = await pool.query(
    `INSERT INTO coach_schedule_settings (coach_id) VALUES ($1)
     ON CONFLICT (coach_id) DO UPDATE SET coach_id = EXCLUDED.coach_id
     RETURNING session_minutes`, [req.user.id]);
  const days = await pool.query(
    `SELECT dow, enabled FROM coach_day_settings WHERE coach_id=$1`, [req.user.id]);
  const ranges = await pool.query(
    `SELECT id, dow, start_time, end_time, delivery
       FROM coach_availability_ranges WHERE coach_id=$1 ORDER BY dow, start_time`, [req.user.id]);
  const enabledMap = new Map(days.rows.map((d) => [d.dow, d.enabled]));
  res.json({
    sessionMinutes: settings.rows[0].session_minutes,
    days: [0, 1, 2, 3, 4, 5, 6].map((dow) => ({
      dow,
      enabled: enabledMap.get(dow) === true,
      ranges: ranges.rows.filter((r) => r.dow === dow),
    })),
  });
});

// Change the per-coach session duration (30/45/50/60/90, default 50).
// Future unbooked generated sessions are rebuilt on the new grid.
router.put('/availability/settings', authenticate, requireRole('coach'), async (req, res) => {
  const { sessionMinutes } = req.body || {};
  if (![30, 45, 50, 60, 90].includes(sessionMinutes))
    return res.status(400).json({ error: 'sessionMinutes must be one of 30, 45, 50, 60, 90' });
  await pool.query(
    `INSERT INTO coach_schedule_settings (coach_id, session_minutes)
     VALUES ($1, $2)
     ON CONFLICT (coach_id) DO UPDATE SET session_minutes=$2, updated_at=now()`,
    [req.user.id, sessionMinutes]);
  const ids = await schedule.rangeIdsFor(req.user.id);
  const cleanup = await schedule.cleanupRanges(req.user.id, ids);
  const gen = await schedule.regenerateForCoach(req.user.id);
  res.json({ sessionMinutes, ...cleanup, generated: gen.generated });
});

// Toggle a weekday on/off. Turning OFF removes future unbooked sessions of
// that day (booked ones are kept and reported); turning ON regenerates.
router.put('/availability/days/:dow', authenticate, requireRole('coach'), async (req, res) => {
  const dow = parseInt(req.params.dow, 10);
  const { enabled } = req.body || {};
  if (!(dow >= 0 && dow <= 6)) return res.status(400).json({ error: 'dow must be 0..6' });
  if (typeof enabled !== 'boolean') return res.status(400).json({ error: 'enabled (boolean) required' });
  await pool.query(
    `INSERT INTO coach_day_settings (coach_id, dow, enabled) VALUES ($1,$2,$3)
     ON CONFLICT (coach_id, dow) DO UPDATE SET enabled=$3`,
    [req.user.id, dow, enabled]);
  let result = { removed: 0, keptBooked: 0, generated: 0 };
  if (enabled) {
    const gen = await schedule.regenerateForCoach(req.user.id);
    result.generated = gen.generated;
  } else {
    const ids = await schedule.rangeIdsFor(req.user.id, dow);
    const cleanup = await schedule.cleanupRanges(req.user.id, ids);
    result = { ...result, ...cleanup };
  }
  res.json({ dow, enabled, ...result });
});

// Add a time range to a day ("Add more"). Rejects overlaps within the day.
router.post('/availability/ranges', authenticate, requireRole('coach'), async (req, res) => {
  const { dow, startTime, endTime, delivery } = req.body || {};
  const d = parseInt(dow, 10);
  if (!(d >= 0 && d <= 6)) return res.status(400).json({ error: 'dow must be 0..6' });
  if (!/^\d{2}:\d{2}$/.test(startTime || '') || !/^\d{2}:\d{2}$/.test(endTime || ''))
    return res.status(400).json({ error: 'startTime and endTime must be HH:MM' });
  if (endTime <= startTime) return res.status(400).json({ error: 'endTime must be after startTime' });
  if (!['online', 'in_person'].includes(delivery || 'online'))
    return res.status(400).json({ error: 'delivery must be online or in_person' });

  const overlap = await pool.query(
    `SELECT 1 FROM coach_availability_ranges
      WHERE coach_id=$1 AND dow=$2 AND start_time < $4::time AND end_time > $3::time LIMIT 1`,
    [req.user.id, d, startTime, endTime]);
  if (overlap.rowCount > 0)
    return res.status(409).json({ error: 'This range overlaps an existing range on that day' });

  const ins = await pool.query(
    `INSERT INTO coach_availability_ranges (coach_id, dow, start_time, end_time, delivery)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [req.user.id, d, startTime, endTime, delivery || 'online']);
  // Make sure the day exists as enabled the first time a range is added.
  await pool.query(
    `INSERT INTO coach_day_settings (coach_id, dow, enabled) VALUES ($1,$2,TRUE)
     ON CONFLICT (coach_id, dow) DO NOTHING`, [req.user.id, d]);
  const gen = await schedule.regenerateForCoach(req.user.id);
  res.status(201).json({ range: ins.rows[0], generated: gen.generated });
});

// Edit a range (tap a time pill / flip delivery). Rebuilds that range's
// future unbooked sessions on the new times.
router.put('/availability/ranges/:id', authenticate, requireRole('coach'), async (req, res) => {
  const cur = await pool.query(
    `SELECT * FROM coach_availability_ranges WHERE id=$1 AND coach_id=$2`,
    [req.params.id, req.user.id]);
  if (cur.rowCount === 0) return res.status(404).json({ error: 'Range not found' });
  const r = cur.rows[0];
  const startTime = req.body?.startTime ?? String(r.start_time).slice(0, 5);
  const endTime = req.body?.endTime ?? String(r.end_time).slice(0, 5);
  const delivery = req.body?.delivery ?? r.delivery;
  if (!/^\d{2}:\d{2}$/.test(startTime) || !/^\d{2}:\d{2}$/.test(endTime))
    return res.status(400).json({ error: 'startTime and endTime must be HH:MM' });
  if (endTime <= startTime) return res.status(400).json({ error: 'endTime must be after startTime' });
  if (!['online', 'in_person'].includes(delivery))
    return res.status(400).json({ error: 'delivery must be online or in_person' });
  const overlap = await pool.query(
    `SELECT 1 FROM coach_availability_ranges
      WHERE coach_id=$1 AND dow=$2 AND id<>$5 AND start_time < $4::time AND end_time > $3::time LIMIT 1`,
    [req.user.id, r.dow, startTime, endTime, r.id]);
  if (overlap.rowCount > 0)
    return res.status(409).json({ error: 'This range overlaps an existing range on that day' });

  const upd = await pool.query(
    `UPDATE coach_availability_ranges SET start_time=$3, end_time=$4, delivery=$5
      WHERE id=$1 AND coach_id=$2 RETURNING *`,
    [r.id, req.user.id, startTime, endTime, delivery]);
  const cleanup = await schedule.cleanupRanges(req.user.id, [r.id]);
  const gen = await schedule.regenerateForCoach(req.user.id);
  res.json({ range: upd.rows[0], ...cleanup, generated: gen.generated });
});

// Delete a range. Future unbooked sessions from it are removed; booked kept.
router.delete('/availability/ranges/:id', authenticate, requireRole('coach'), async (req, res) => {
  const cur = await pool.query(
    `SELECT id FROM coach_availability_ranges WHERE id=$1 AND coach_id=$2`,
    [req.params.id, req.user.id]);
  if (cur.rowCount === 0) return res.status(404).json({ error: 'Range not found' });
  const cleanup = await schedule.cleanupRanges(req.user.id, [req.params.id]);
  await pool.query(`DELETE FROM coach_availability_ranges WHERE id=$1`, [req.params.id]);
  res.json({ deleted: req.params.id, ...cleanup });
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
            m.birth_place, m.nationality, u.phone, u.email
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
router.get('/my-sessions', authenticate, requireRole('coach'), async (req, res) => {
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
router.get('/bookings', authenticate, requireRole('coach'), async (req, res) => {
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
router.get('/clients', authenticate, requireRole('coach'), async (req, res) => {
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
router.get('/dashboard', authenticate, requireRole('coach'), async (req, res) => {
  // (v0.10) Sessions owed from same-day cancellations, for the coach to see.
  const pen = await pool.query(
    `SELECT COALESCE(SUM(sessions), 0)::int AS n FROM coach_penalties
      WHERE coach_id = $1 AND settled_at IS NULL`, [req.user.id]);
  const days = [7, 30, 90].includes(parseInt(req.query.days, 10)) ? parseInt(req.query.days, 10) : 30;
  const id = req.user.id;
  const [upcoming, pendingReq, range, clients, rating, weekly] = await Promise.all([
    pool.query(`SELECT COUNT(*)::int n FROM coach_sessions WHERE coach_id=$1 AND start_at > now()`, [id]),
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
    upcomingSessions: upcoming.rows[0].n,
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
