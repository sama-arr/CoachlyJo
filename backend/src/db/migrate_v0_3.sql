-- =============================================================================
-- Fitness Coaching Platform — Schema migration v0.2 -> v0.3
-- Idempotent. migrate.js applies schema.sql + migrate_v0_2.sql + this in order.
-- =============================================================================

-- ---- Schema version marker (startup staleness check) ----
CREATE TABLE IF NOT EXISTS schema_meta (
    id      INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    version INTEGER NOT NULL
);
INSERT INTO schema_meta (id, version) VALUES (1, 3)
ON CONFLICT (id) DO UPDATE SET version = 3;

-- ---- (10,11) Admin-configurable locations dropdown ----
CREATE TABLE IF NOT EXISTS locations (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_en    TEXT NOT NULL UNIQUE,
    name_ar    TEXT NOT NULL DEFAULT '',
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO locations (name_en, name_ar, sort_order)
SELECT * FROM (VALUES
    ('Amman','عمّان',1),('Zarqa','الزرقاء',2),('Irbid','إربد',3),('Aqaba','العقبة',4),
    ('Salt','السلط',5),('Madaba','مادبا',6),('Jerash','جرش',7),('Ajloun','عجلون',8),
    ('Karak','الكرك',9),('Mafraq','المفرق',10),('Tafilah','الطفيلة',11),('Maan','معان',12)
) AS v(name_en,name_ar,sort_order)
WHERE NOT EXISTS (SELECT 1 FROM locations);

-- ---- (10) Member: DOB, birth place, nationality, location ----
ALTER TABLE member_profiles ADD COLUMN IF NOT EXISTS date_of_birth DATE;
ALTER TABLE member_profiles ADD COLUMN IF NOT EXISTS birth_place   TEXT;
ALTER TABLE member_profiles ADD COLUMN IF NOT EXISTS nationality   TEXT;
ALTER TABLE member_profiles ADD COLUMN IF NOT EXISTS location TEXT;

-- ---- (11) Coach: birth place + location ----
ALTER TABLE coach_profiles ADD COLUMN IF NOT EXISTS birth_place TEXT;
ALTER TABLE coach_profiles ADD COLUMN IF NOT EXISTS location    TEXT;

-- ---- Safety net: ensure v0.2 columns exist even if v0.2 migration was skipped ----
ALTER TABLE coach_documents ADD COLUMN IF NOT EXISTS content   BYTEA;
ALTER TABLE coach_documents ADD COLUMN IF NOT EXISTS mime_type TEXT;
ALTER TABLE coach_documents ADD COLUMN IF NOT EXISTS file_name TEXT;
ALTER TABLE coach_documents ADD COLUMN IF NOT EXISTS byte_size INTEGER;
ALTER TABLE coach_documents ALTER COLUMN file_url DROP NOT NULL;

DO $$ BEGIN
    CREATE TYPE package_mode AS ENUM ('online','in_person');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
ALTER TABLE package_definitions ADD COLUMN IF NOT EXISTS mode package_mode NOT NULL DEFAULT 'online';
ALTER TABLE package_definitions ADD COLUMN IF NOT EXISTS is_single BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS mode package_mode NOT NULL DEFAULT 'online';
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS is_single BOOLEAN NOT NULL DEFAULT FALSE;
