-- =============================================================================
-- Fitness Coaching Platform — Schema migration v0.4 -> v0.5
-- Idempotent. migrate.js applies baseline + v0_2..v0_5 in order as needed.
--
-- v0.5 items covered here:
--   (1) Forgot password: one-time reset codes for members & coaches
--   (5) Weekly recurring availability (per-day toggle + time ranges) replacing
--       the coach-facing slot-template flow; sessions are auto-generated and
--       carry provenance so edits can clean up unbooked future sessions.
-- =============================================================================

-- ---- (1) Password reset codes ------------------------------------------------
-- 6-char alphanumeric code, stored hashed. 10-minute expiry, single use,
-- max 5 wrong attempts. Requesting a new code consumes previous ones.
CREATE TABLE IF NOT EXISTS password_resets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash   TEXT NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    attempts    INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pwreset_user ON password_resets(user_id, created_at DESC);

-- ---- (5) Coach weekly availability -------------------------------------------
-- Per-coach schedule settings: one session duration applied to all ranges
-- (default 50 min, confirmed for v0.5) + generation bookkeeping.
CREATE TABLE IF NOT EXISTS coach_schedule_settings (
    coach_id          UUID PRIMARY KEY REFERENCES coach_profiles(user_id) ON DELETE CASCADE,
    session_minutes   INTEGER NOT NULL DEFAULT 50
                      CHECK (session_minutes IN (30, 45, 50, 60, 90)),
    last_generated_at TIMESTAMPTZ,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Day on/off toggle (screenshot UI). No row = day disabled.
CREATE TABLE IF NOT EXISTS coach_day_settings (
    coach_id UUID NOT NULL REFERENCES coach_profiles(user_id) ON DELETE CASCADE,
    dow      SMALLINT NOT NULL CHECK (dow BETWEEN 0 AND 6),  -- 0=Sun..6=Sat
    enabled  BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (coach_id, dow)
);

-- Time ranges within a day ("8:00 PM - 11:00 PM", "Add more" adds rows).
CREATE TABLE IF NOT EXISTS coach_availability_ranges (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id   UUID NOT NULL REFERENCES coach_profiles(user_id) ON DELETE CASCADE,
    dow        SMALLINT NOT NULL CHECK (dow BETWEEN 0 AND 6),
    start_time TIME NOT NULL,
    end_time   TIME NOT NULL,
    delivery   delivery_mode NOT NULL DEFAULT 'online',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_time > start_time)
);
CREATE INDEX IF NOT EXISTS idx_avail_coach_dow ON coach_availability_ranges(coach_id, dow);

-- Sessions generated from a range carry provenance so that deleting/toggling
-- availability can remove FUTURE, UNBOOKED sessions from that source while
-- always keeping booked ones. Manual/legacy sessions have NULL here.
ALTER TABLE coach_sessions
    ADD COLUMN IF NOT EXISTS generated_from_range UUID
        REFERENCES coach_availability_ranges(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_session_gen_range ON coach_sessions(generated_from_range);

-- NOTE: slot_templates and its admin endpoints remain in the database as
-- legacy (existing sessions may reference template_id) but the coach and
-- admin UIs no longer use them as of v0.5.

-- ---- Schema version marker ---------------------------------------------------
INSERT INTO schema_meta (id, version) VALUES (1, 5)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 5);
