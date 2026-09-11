-- =============================================================================
-- Fitness Coaching Platform — Schema migration v0.3 -> v0.4
-- Idempotent. migrate.js applies schema.sql + v0_2 + v0_3 + this in order.
--
-- v0.4 items covered here:
--   (7)  Packages are bought for a specific coach  -> member_packages.coach_id
--   (7)  Max ONE concurrent (pending/active) package per member per coach
--   (3)  The paid single session: max ONE per member PER COACH, permanent
--   (6)  Proof-of-payment image on the package request + reject-with-reason
-- =============================================================================

-- ---- (7) Coach-bound packages ----------------------------------------------
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS coach_id UUID REFERENCES coach_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_mpkg_coach ON member_packages(coach_id);

-- Enforce NOT NULL only when no legacy NULL rows exist (fresh-state confirmed
-- for v0.4, but keep the migration safe to run on any database).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM member_packages WHERE coach_id IS NULL) THEN
        ALTER TABLE member_packages ALTER COLUMN coach_id SET NOT NULL;
    ELSE
        RAISE NOTICE 'member_packages has legacy rows without coach_id; column left nullable (app enforces it for new purchases).';
    END IF;
EXCEPTION WHEN others THEN NULL; -- already NOT NULL on re-run
END $$;

-- ---- (7) One concurrent package per member per coach ------------------------
-- A member may hold packages with several coaches at once, but never two
-- USABLE (pending/active AND not exhausted) purchases with the SAME coach.
-- An exhausted package (all classes consumed) no longer blocks a new purchase
-- even before its expiry date passes. DB-level backstop.
DROP INDEX IF EXISTS uq_concurrent_pkg_per_coach;
CREATE UNIQUE INDEX uq_concurrent_pkg_per_coach
    ON member_packages(member_id, coach_id)
    WHERE status IN ('pending_payment', 'active')
      AND classes_consumed < classes_total;

-- ---- (3) Single session: one per member per coach, permanent ----------------
-- Counts every non-cancelled single (pending, active, expired). A request the
-- admin rejected/cancelled does NOT consume the allowance.
CREATE UNIQUE INDEX IF NOT EXISTS uq_single_per_coach
    ON member_packages(member_id, coach_id)
    WHERE is_single = TRUE AND status <> 'cancelled';

-- ---- (6) Proof of payment ----------------------------------------------------
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS proof_content   BYTEA;
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS proof_mime      TEXT;
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS proof_file_name TEXT;
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS proof_uploaded_at TIMESTAMPTZ;
-- Set when admin rejects the submitted proof; cleared when member re-uploads.
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS payment_rejection_reason TEXT;
ALTER TABLE member_packages ADD COLUMN IF NOT EXISTS payment_rejected_at      TIMESTAMPTZ;

-- ---- Schema version marker ---------------------------------------------------
INSERT INTO schema_meta (id, version) VALUES (1, 4)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 4);
