-- =============================================================================
-- Fitness Coaching Platform — Schema migration v0.1 -> v0.2
-- Run AFTER schema.sql. Idempotent where practical (IF NOT EXISTS / DO blocks).
-- =============================================================================

-- ---- (2) Member location + questionnaire ----------------------------------
ALTER TABLE member_profiles ADD COLUMN IF NOT EXISTS location TEXT;

-- Admin-configurable questionnaire definition (add/remove questions).
CREATE TABLE IF NOT EXISTS questionnaire_questions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key         TEXT NOT NULL UNIQUE,          -- stable machine key, e.g. 'goal'
    label_en    TEXT NOT NULL,
    label_ar    TEXT NOT NULL DEFAULT '',
    input_type  TEXT NOT NULL CHECK (input_type IN ('text','number','dropdown')),
    options     JSONB,                          -- for dropdown: ["Lose weight",...]
    required    BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- (1) Coach documents stored as binary in the DB -----------------------
-- Keep the existing coach_documents table; add binary storage columns.
ALTER TABLE coach_documents ADD COLUMN IF NOT EXISTS content   BYTEA;
ALTER TABLE coach_documents ADD COLUMN IF NOT EXISTS mime_type TEXT;
ALTER TABLE coach_documents ADD COLUMN IF NOT EXISTS file_name TEXT;
ALTER TABLE coach_documents ADD COLUMN IF NOT EXISTS byte_size INTEGER;
-- file_url is now optional (legacy). Make it nullable if it was NOT NULL.
ALTER TABLE coach_documents ALTER COLUMN file_url DROP NOT NULL;

-- ---- (8,10) Package mode (online / in_person) + single-session product ----
DO $$ BEGIN
    CREATE TYPE package_mode AS ENUM ('online', 'in_person');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE package_definitions ADD COLUMN IF NOT EXISTS mode package_mode NOT NULL DEFAULT 'online';
ALTER TABLE package_definitions ADD COLUMN IF NOT EXISTS is_single BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS mode package_mode NOT NULL DEFAULT 'online';
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS is_single BOOLEAN NOT NULL DEFAULT FALSE;

-- ---- (4) Coach about/bio already exists (coach_profiles.bio_en/bio_ar) -----
-- no change needed.

-- ---- (5) Reviewed flag is derivable from reviews table; no column needed.

-- Helpful index for the 3-booking pre-book cap (11) and directories (7).
CREATE INDEX IF NOT EXISTS idx_booking_member_status ON bookings(member_id, status);

-- Seed default questionnaire (2b) if empty.
INSERT INTO questionnaire_questions (key,label_en,input_type,options,required,sort_order)
SELECT * FROM (VALUES
    ('goal','Your main goal','dropdown','["Lose weight","Tone/shape","Build muscle","General fitness","Rehab"]'::jsonb,TRUE,1),
    ('injuries','Any injuries or conditions?','text',NULL::jsonb,FALSE,2),
    ('weight_kg','Weight (kg)','number',NULL::jsonb,FALSE,3),
    ('height_cm','Height (cm)','number',NULL::jsonb,FALSE,4),
    ('activity_level','Activity level','dropdown','["Sedentary","Lightly active","Active","Very active"]'::jsonb,FALSE,5)
) AS v(key,label_en,input_type,options,required,sort_order)
WHERE NOT EXISTS (SELECT 1 FROM questionnaire_questions);
