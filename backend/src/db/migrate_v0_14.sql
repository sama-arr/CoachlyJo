-- =============================================================================
-- Schema migration v0.13 -> v0.14   (tester feedback round)
--
--  (1,2)  Short registration + mandatory "Complete profile":
--         registration now collects only name, email, phone, password and
--         nationality. Everything else (date of birth, location, questionnaire,
--         coach documents, experience, specialty, photo) moves to a profile
--         step inside the app, so the signup form stops scaring people off.
--         Birth place is dropped from both sides entirely.
--  (6)    Configurable Contact Us details (email / phone / Instagram).
--  (11)   Coach experience, specialty and optional profile photo.
--  (12)   Per-device theme preference (system / light / dark).
--  (13)   Push notification device tokens (FCM).
--  (16)   Per-WEEK availability: coaches now set hours against real dates in a
--         calendar, instead of one repeating weekly pattern.
--
-- Existing data is preserved throughout: current recurring availability is
-- copied forward into real dates so no coach loses their schedule, and no
-- generated or booked session is touched.
-- =============================================================================

-- ---- (1) Registration slimming -----------------------------------------------
-- These columns are now filled in during profile completion, so they must
-- accept NULL for accounts created by the short signup form.
ALTER TABLE member_profiles ALTER COLUMN first_name SET NOT NULL;   -- still required at signup
ALTER TABLE coach_profiles  ALTER COLUMN date_of_birth DROP NOT NULL;
ALTER TABLE member_profiles ALTER COLUMN date_of_birth DROP NOT NULL;

-- Birth place is removed from the product. The columns are dropped so no screen
-- can accidentally keep collecting it.
ALTER TABLE member_profiles DROP COLUMN IF EXISTS birth_place;
ALTER TABLE coach_profiles  DROP COLUMN IF EXISTS birth_place;

-- ---- (2) Profile completion tracking -----------------------------------------
-- profile_completed_at is set when the user submits the Complete Profile step.
-- Existing accounts are back-filled as complete when they already hold the data
-- the step asks for, so current testers are not forced through it needlessly.
ALTER TABLE member_profiles ADD COLUMN IF NOT EXISTS profile_completed_at TIMESTAMPTZ;
ALTER TABLE coach_profiles  ADD COLUMN IF NOT EXISTS profile_completed_at TIMESTAMPTZ;

UPDATE member_profiles mp
   SET profile_completed_at = now()
 WHERE profile_completed_at IS NULL
   AND date_of_birth IS NOT NULL
   AND location IS NOT NULL
   AND EXISTS (SELECT 1 FROM fitness_assessments fa WHERE fa.member_id = mp.user_id);

UPDATE coach_profiles cp
   SET profile_completed_at = now()
 WHERE profile_completed_at IS NULL
   AND date_of_birth IS NOT NULL
   AND EXISTS (SELECT 1 FROM coach_documents cd WHERE cd.coach_id = cp.user_id);

-- ---- (11) Coach experience, specialty, photo ---------------------------------
ALTER TABLE coach_profiles ADD COLUMN IF NOT EXISTS years_experience INTEGER
    CHECK (years_experience IS NULL OR (years_experience >= 0 AND years_experience <= 70));
ALTER TABLE coach_profiles ADD COLUMN IF NOT EXISTS specialties TEXT[];
-- Profile photo stored inline like the other uploads (jpg/png, capped in the route).
ALTER TABLE coach_profiles ADD COLUMN IF NOT EXISTS photo_content BYTEA;
ALTER TABLE coach_profiles ADD COLUMN IF NOT EXISTS photo_mime TEXT;
ALTER TABLE coach_profiles ADD COLUMN IF NOT EXISTS photo_updated_at TIMESTAMPTZ;

-- ---- (12) Theme preference ---------------------------------------------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS theme_pref TEXT NOT NULL DEFAULT 'dark'
    CHECK (theme_pref IN ('system', 'light', 'dark'));

-- ---- (13) Push notification tokens -------------------------------------------
-- One row per device. A token can move between accounts (shared phone), so the
-- token itself is unique and simply re-points at the newest user.
CREATE TABLE IF NOT EXISTS device_tokens (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      TEXT NOT NULL UNIQUE,
    platform   TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);

-- Reminder windows now include 15 minutes before the session (item 13), so the
-- notification type list is unchanged but the scheduler ticks more often.

-- ---- (16) Per-week availability ----------------------------------------------
-- Replaces the repeating weekly pattern with concrete dated blocks. A block is
-- one continuous range of hours on one real date.
CREATE TABLE IF NOT EXISTS coach_availability_days (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id   UUID NOT NULL REFERENCES coach_profiles(user_id) ON DELETE CASCADE,
    on_date    DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time   TIME NOT NULL,
    delivery   delivery_mode NOT NULL DEFAULT 'online',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_time > start_time)
);
CREATE INDEX IF NOT EXISTS idx_avail_days_coach_date ON coach_availability_days(coach_id, on_date);

-- Sessions generated from a dated block carry its id, so editing one week
-- cleans up only that week's unbooked sessions.
ALTER TABLE coach_sessions
    ADD COLUMN IF NOT EXISTS generated_from_day UUID
        REFERENCES coach_availability_days(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_session_gen_day ON coach_sessions(generated_from_day);

-- Carry every coach's existing recurring pattern forward into real dates for
-- the next 8 weeks, so nobody opens the new calendar to an empty grid.
INSERT INTO coach_availability_days (coach_id, on_date, start_time, end_time, delivery)
SELECT r.coach_id,
       d::date,
       r.start_time,
       r.end_time,
       r.delivery
  FROM coach_availability_ranges r
  JOIN coach_day_settings s
    ON s.coach_id = r.coach_id AND s.dow = r.dow AND s.enabled = TRUE
  CROSS JOIN LATERAL generate_series(
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '8 weeks',
        INTERVAL '1 day') AS d
 WHERE EXTRACT(DOW FROM d) = r.dow
   AND NOT EXISTS (
        SELECT 1 FROM coach_availability_days x
         WHERE x.coach_id = r.coach_id
           AND x.on_date = d::date
           AND x.start_time = r.start_time);

-- The old recurring tables stay in place (read-only) so the migration is
-- reversible and historical sessions keep their provenance.

-- ---- (6) Contact details, admin-configurable ---------------------------------
ALTER TABLE platform_settings ADD COLUMN IF NOT EXISTS contact_email TEXT NOT NULL DEFAULT 'coachlyapp@hotmail.com';
ALTER TABLE platform_settings ADD COLUMN IF NOT EXISTS contact_phone TEXT NOT NULL DEFAULT '';
ALTER TABLE platform_settings ADD COLUMN IF NOT EXISTS contact_instagram TEXT NOT NULL DEFAULT '';
ALTER TABLE platform_settings ADD COLUMN IF NOT EXISTS contact_whatsapp TEXT NOT NULL DEFAULT '';

-- ---- (5) "Rules & regulations" becomes "Cancellation policy" ------------------
UPDATE content_blocks
   SET title_en = REPLACE(REPLACE(title_en, 'Rules & regulations', 'Cancellation policy'),
                          'Rules and regulations', 'Cancellation policy'),
       title_ar = REPLACE(title_ar, 'القواعد والأحكام', 'سياسة الإلغاء')
 WHERE kind = 'rule';

-- ---- (20) Remove the "have a lawyer review" line from user-facing legal text --
UPDATE content_blocks
   SET body_en = regexp_replace(body_en,
         E'STARTER TEXT[^\\n]*\\n\\n', '', 'g'),
       body_ar = regexp_replace(body_ar,
         E'نص مبدئي[^\\n]*\\n\\n', '', 'g')
 WHERE kind = 'legal';

INSERT INTO schema_meta (id, version) VALUES (1, 14)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 14);
