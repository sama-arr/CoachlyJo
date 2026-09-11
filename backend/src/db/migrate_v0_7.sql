-- =============================================================================
-- Schema migration v0.6 -> v0.7
-- (item 2) Anti-fraud completion flow:
--   * completion_kind records HOW a booking reached 'completed':
--       'coach'   — coach pressed Completed after the session ended
--       'no_show' — coach reported the member did not show up (class is still
--                   deducted; the member reserved and wasted the slot)
--       'auto'    — neither was pressed within 48h of the session end; the
--                   system auto-completed it (periodic job)
--   * Completion before the session's end time is rejected in the service.
--   * Reviews are blocked for 'no_show' completions.
-- =============================================================================
ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS completion_kind TEXT
        CHECK (completion_kind IN ('coach', 'no_show', 'auto'));

-- (bug fix, root cause) The v0.1 UNIQUE (member_id, session_id) constraint
-- permanently blocked a member from re-booking a session after their earlier
-- booking was cancelled or rejected (raw duplicate-key error). Only LIVE
-- bookings should be unique per member+session.
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_member_id_session_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_live_booking_per_member_session
    ON bookings(member_id, session_id)
    WHERE status IN ('pending', 'accepted', 'completed');

INSERT INTO schema_meta (id, version) VALUES (1, 7)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 7);
