// =============================================================================
// Schedule service (v0.5 item 5).
//
// Coaches define weekly availability: per-day on/off + time ranges, with ONE
// per-coach session duration (default 50 min). This service turns that into
// concrete bookable coach_sessions rows on a rolling HORIZON_DAYS window:
//   range 20:00-23:00 @ 50 min => sessions at 20:00, 20:50, 21:40 (22:30+50
//   would end past 23:00, so it is excluded).
//
// Rules:
//   * Generated sessions are 1-on-1 (capacity 1) — confirmed for v0.5.
//   * Only APPROVED coaches generate sessions.
//   * Duplicate protection via the UNIQUE (coach_id, start_at) constraint.
//   * Past start times are never inserted.
//   * Cleanup (range deleted / day toggled off / duration changed) removes
//     FUTURE sessions generated from the affected ranges ONLY if they have no
//     pending/accepted/completed booking; booked sessions are always kept and
//     the caller is told how many were kept.
//   * Regeneration runs on every availability edit, at server startup, and on
//     a 6-hour interval so the horizon keeps rolling forward.
// =============================================================================
const { pool } = require('../db/pool_v0_13');

const HORIZON_DAYS = 28;

async function platformTz() {
  const r = await pool.query(`SELECT timezone FROM platform_settings WHERE id=1`);
  return r.rows[0]?.timezone || 'Asia/Amman';
}

// Calendar date + weekday of (now + i days) as seen in the given timezone.
function localDateInfo(offsetDays, tz) {
  const d = new Date(Date.now() + offsetDays * 86400000);
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short',
  }).formatToParts(d);
  const get = (t) => parts.find((p) => p.type === t)?.value;
  const dowMap = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  return { date: `${get('year')}-${get('month')}-${get('day')}`, dow: dowMap[get('weekday')] };
}

// "HH:MM[:SS]" -> minutes since midnight
function toMinutes(t) {
  const [h, m] = String(t).split(':');
  return parseInt(h, 10) * 60 + parseInt(m, 10);
}
function toHHMM(mins) {
  const h = Math.floor(mins / 60), m = mins % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/** (Re)generate the coach's sessions over the horizon. No-op unless approved. */
async function regenerateForCoach(coachId) {
  const status = await pool.query(`SELECT status FROM coach_profiles WHERE user_id=$1`, [coachId]);
  if (status.rowCount === 0 || status.rows[0].status !== 'approved') return { generated: 0 };

  const tz = await platformTz();
  const settings = await pool.query(
    `INSERT INTO coach_schedule_settings (coach_id) VALUES ($1)
     ON CONFLICT (coach_id) DO UPDATE SET coach_id = EXCLUDED.coach_id
     RETURNING session_minutes`, [coachId]);
  const minutes = settings.rows[0].session_minutes;

  const ranges = await pool.query(
    `SELECT r.id, r.dow, r.start_time, r.end_time, r.delivery
       FROM coach_availability_ranges r
       JOIN coach_day_settings d ON d.coach_id=r.coach_id AND d.dow=r.dow AND d.enabled=TRUE
      WHERE r.coach_id=$1`, [coachId]);
  if (ranges.rowCount === 0) {
    await pool.query(`UPDATE coach_schedule_settings SET last_generated_at=now() WHERE coach_id=$1`, [coachId]);
    return { generated: 0 };
  }

  const byDow = new Map();
  for (const r of ranges.rows) {
    if (!byDow.has(r.dow)) byDow.set(r.dow, []);
    byDow.get(r.dow).push(r);
  }

  let generated = 0;
  for (let i = 0; i <= HORIZON_DAYS; i++) {
    const { date, dow } = localDateInfo(i, tz);
    const todays = byDow.get(dow);
    if (!todays) continue;
    for (const r of todays) {
      const startM = toMinutes(r.start_time);
      const endM = toMinutes(r.end_time);
      for (let m = startM; m + minutes <= endM; m += minutes) {
        const localStart = `${date} ${toHHMM(m)}:00`;
        const ins = await pool.query(
          `INSERT INTO coach_sessions
             (coach_id, template_id, session_date, start_at, end_at, capacity, delivery, generated_from_range)
           SELECT $1, NULL, $2::date, ($3::timestamp AT TIME ZONE $4),
                  ($3::timestamp AT TIME ZONE $4) + ($5 || ' minutes')::interval,
                  1, $6, $7
            WHERE ($3::timestamp AT TIME ZONE $4) > now()
           ON CONFLICT (coach_id, start_at) DO NOTHING
           RETURNING id`,
          [coachId, date, localStart, tz, String(minutes), r.delivery, r.id]
        );
        generated += ins.rowCount;
      }
    }
  }
  await pool.query(`UPDATE coach_schedule_settings SET last_generated_at=now() WHERE coach_id=$1`, [coachId]);
  return { generated };
}

/**
 * Remove FUTURE, UNBOOKED sessions generated from the given range ids.
 * Returns { removed, keptBooked } so the UI can inform the coach.
 */
async function cleanupRanges(coachId, rangeIds) {
  if (!rangeIds.length) return { removed: 0, keptBooked: 0 };
  const kept = await pool.query(
    `SELECT COUNT(*)::int n FROM coach_sessions cs
      WHERE cs.coach_id=$1 AND cs.generated_from_range = ANY($2::uuid[])
        AND cs.start_at > now()
        AND EXISTS (SELECT 1 FROM bookings b WHERE b.session_id=cs.id
                     AND b.status IN ('pending','accepted','completed'))`,
    [coachId, rangeIds]);
  const del = await pool.query(
    `DELETE FROM coach_sessions cs
      WHERE cs.coach_id=$1 AND cs.generated_from_range = ANY($2::uuid[])
        AND cs.start_at > now()
        AND NOT EXISTS (SELECT 1 FROM bookings b WHERE b.session_id=cs.id
                         AND b.status IN ('pending','accepted','completed'))
      RETURNING cs.id`,
    [coachId, rangeIds]);
  return { removed: del.rowCount, keptBooked: kept.rows[0].n };
}

/** All range ids of a coach (optionally one weekday). */
async function rangeIdsFor(coachId, dow = null) {
  const r = dow == null
    ? await pool.query(`SELECT id FROM coach_availability_ranges WHERE coach_id=$1`, [coachId])
    : await pool.query(`SELECT id FROM coach_availability_ranges WHERE coach_id=$1 AND dow=$2`, [coachId, dow]);
  return r.rows.map((x) => x.id);
}

/** Rolling-horizon upkeep: regenerate every approved coach. */
async function regenerateAllApproved() {
  const coaches = await pool.query(`SELECT user_id FROM coach_profiles WHERE status='approved'`);
  let total = 0;
  for (const c of coaches.rows) {
    try {
      const { generated } = await regenerateForCoach(c.user_id);
      total += generated;
    } catch (err) {
      console.error(`[schedule] regenerate failed for coach ${c.user_id}: ${err.message}`);
    }
  }
  return total;
}

module.exports = { regenerateForCoach, regenerateAllApproved, cleanupRanges, rangeIdsFor, HORIZON_DAYS };
