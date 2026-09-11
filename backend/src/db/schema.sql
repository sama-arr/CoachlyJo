-- =============================================================================
-- Fitness Coaching Platform — PostgreSQL Schema
-- Baseline v1.0 — implements consolidated spec v1.0
--
-- Conventions:
--   * All timestamps are TIMESTAMPTZ, stored in UTC (spec §17).
--   * Display timezone (Asia/Amman) is an application/config concern, not stored per row.
--   * Money is NUMERIC(10,2); currency is JOD at launch (spec §9, §10).
--   * Soft domains use native ENUMs; admin-configurable data lives in tables.
--   * Counter invariants (spec §7) and expiry (spec §9) are enforced via
--     CHECK constraints + triggers so they cannot drift from app code.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;      -- case-insensitive email

-- =============================================================================
-- ENUM TYPES
-- =============================================================================

CREATE TYPE user_role           AS ENUM ('member', 'coach', 'admin');
CREATE TYPE coach_status        AS ENUM ('pending', 'approved', 'rejected', 'suspended');
CREATE TYPE delivery_mode       AS ENUM ('online', 'in_person');
CREATE TYPE slot_duration       AS ENUM ('30', '45', '60', '90');  -- minutes (spec §5.1)
CREATE TYPE booking_status      AS ENUM (
    'pending',     -- booked, awaiting coach acceptance (hold placed)
    'accepted',    -- coach accepted / roster approved
    'rejected',    -- coach rejected (reason required, no deduction)
    'completed',   -- coach marked done (deducts a class)
    'cancelled'    -- member cancelled (same-day => deduction)
);
CREATE TYPE cancel_kind         AS ENUM ('same_day', 'early', 'coach', 'no_show');
CREATE TYPE package_status      AS ENUM ('pending_payment', 'active', 'expired', 'cancelled');
CREATE TYPE doc_type            AS ENUM ('degree_certificate', 'additional_certification', 'experience_proof');
CREATE TYPE notification_type   AS ENUM (
    'booking_accepted', 'booking_rejected',
    'package_activated', 'package_expiring', 'package_expired',
    'session_reminder', 'zoom_link'
);

-- =============================================================================
-- USERS & AUTHENTICATION (spec §3, §4, §15)
-- =============================================================================

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role            user_role   NOT NULL,
    email           CITEXT      NOT NULL UNIQUE,
    phone           VARCHAR(20) NOT NULL UNIQUE,
    -- bcrypt/argon2 hash only; min 8 chars enforced in app before hashing (spec §15.1)
    password_hash   TEXT        NOT NULL,
    email_verified  BOOLEAN     NOT NULL DEFAULT FALSE,
    phone_verified  BOOLEAN     NOT NULL DEFAULT FALSE,
    preferred_lang  CHAR(2)     NOT NULL DEFAULT 'en' CHECK (preferred_lang IN ('en','ar')),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- OTP verification anchors one-free-trial-per-identity (spec §3.1, §15.2)
CREATE TABLE otp_verifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel     VARCHAR(10) NOT NULL CHECK (channel IN ('email','phone')),
    code_hash   TEXT NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_otp_user ON otp_verifications(user_id);

-- =============================================================================
-- MEMBER PROFILE (spec §3)
-- =============================================================================

CREATE TABLE member_profiles (
    user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    first_name      VARCHAR(80) NOT NULL,
    last_name       VARCHAR(80) NOT NULL,
    -- One free trial per verified identity (spec §3.4, §6). Flipped true on first trial booking.
    trial_used      BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Fitness assessment questionnaire captured at registration (spec §3.2).
-- Stored as JSONB so the admin can evolve questions without a migration.
CREATE TABLE fitness_assessments (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id   UUID NOT NULL REFERENCES member_profiles(user_id) ON DELETE CASCADE,
    responses   JSONB NOT NULL,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_assessment_member ON fitness_assessments(member_id);

-- =============================================================================
-- COACH PROFILE, DOCUMENTS, APPROVAL (spec §4)
-- =============================================================================

CREATE TABLE coach_profiles (
    user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    first_name      VARCHAR(80) NOT NULL,
    last_name       VARCHAR(80) NOT NULL,
    date_of_birth   DATE        NOT NULL,
    nationality     VARCHAR(80) NOT NULL,
    bio_en          TEXT,
    bio_ar          TEXT,
    status          coach_status NOT NULL DEFAULT 'pending',  -- not public until 'approved' (spec §4.1)
    approved_by     UUID REFERENCES users(id),
    approved_at     TIMESTAMPTZ,
    rejection_reason TEXT,
    avg_rating      NUMERIC(3,2) NOT NULL DEFAULT 0,           -- maintained from reviews (spec §13.7)
    rating_count    INTEGER      NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_coach_status ON coach_profiles(status);

CREATE TABLE coach_documents (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id    UUID NOT NULL REFERENCES coach_profiles(user_id) ON DELETE CASCADE,
    doc_type    doc_type NOT NULL,
    file_url    TEXT NOT NULL,           -- secured storage reference (spec §15.3)
    verified    BOOLEAN NOT NULL DEFAULT FALSE,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_coachdoc_coach ON coach_documents(coach_id);

-- =============================================================================
-- ADMIN CONFIGURATION: SESSION GRID (spec §5)
-- =============================================================================

-- Single-row platform settings (week start, day window, timezone) — spec §5.1, §17.
CREATE TABLE platform_settings (
    id              INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),  -- enforce single row
    week_start_dow  SMALLINT NOT NULL DEFAULT 6,   -- 6 = Saturday (spec §5.1)
    day_start_time  TIME NOT NULL DEFAULT '06:00',
    day_end_time    TIME NOT NULL DEFAULT '00:00', -- midnight (spec §5.1)
    timezone        TEXT NOT NULL DEFAULT 'Asia/Amman',
    currency        CHAR(3) NOT NULL DEFAULT 'JOD',
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO platform_settings (id) VALUES (1);

-- Admin-defined slot templates: the bookable grid (spec §5.1, §5.2, §5.3).
-- A template's capacity decides type: cap = 1 => 1-on-1, cap > 1 => group (spec §5.2).
CREATE TABLE slot_templates (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    day_of_week     SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Sun..6=Sat
    start_time      TIME NOT NULL,
    duration        slot_duration NOT NULL,
    capacity        INTEGER NOT NULL CHECK (capacity >= 1),  -- max attendance (spec §5.1)
    delivery        delivery_mode NOT NULL,
    is_group        BOOLEAN GENERATED ALWAYS AS (capacity > 1) STORED,  -- derived (spec §5.2)
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- COACH AVAILABILITY → CONCRETE BOOKABLE SESSIONS (spec §5.4, §6, §11)
-- =============================================================================

-- A coach instantiates a template on a real date => a session members can book.
-- Capacity/delivery are snapshotted so later template edits don't mutate live sessions.
CREATE TABLE coach_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id        UUID NOT NULL REFERENCES coach_profiles(user_id) ON DELETE CASCADE,
    template_id     UUID REFERENCES slot_templates(id),
    session_date    DATE NOT NULL,
    start_at        TIMESTAMPTZ NOT NULL,   -- UTC; derived from date + template time @ platform tz
    end_at          TIMESTAMPTZ NOT NULL,
    capacity        INTEGER NOT NULL CHECK (capacity >= 1),
    delivery        delivery_mode NOT NULL,
    is_group        BOOLEAN GENERATED ALWAYS AS (capacity > 1) STORED,
    -- Group roster approval is a single coach action over the session (spec §6.3).
    roster_approved BOOLEAN NOT NULL DEFAULT FALSE,
    -- Zoom fields populated for online sessions on booking (spec §11).
    zoom_meeting_id TEXT,
    zoom_join_url   TEXT,
    zoom_start_url  TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_at > start_at),
    -- a coach cannot run two sessions starting at the same instant
    UNIQUE (coach_id, start_at)
);
CREATE INDEX idx_session_coach_date ON coach_sessions(coach_id, session_date);
CREATE INDEX idx_session_start ON coach_sessions(start_at);

-- =============================================================================
-- PACKAGES (admin-configurable) & MEMBER PACKAGE INSTANCES (spec §9, §10, §7)
-- =============================================================================

-- Admin-configurable package catalogue (spec §9.1, §9.2). Baseline: 6/9/12.
CREATE TABLE package_definitions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_en         VARCHAR(120) NOT NULL,
    name_ar         VARCHAR(120) NOT NULL,
    class_count     INTEGER NOT NULL CHECK (class_count > 0),
    price           NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    currency        CHAR(3) NOT NULL DEFAULT 'JOD',
    validity_weeks  INTEGER NOT NULL CHECK (validity_weeks > 0),  -- per-package X (spec §9.2)
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A member's purchased package instance. Counters here enforce spec §7.
--   remaining  = classes_total - classes_consumed
--   bookable   = classes_total - classes_consumed - classes_pending  (>0 to book)
-- classes_consumed increments ONLY on completion or same-day cancel (spec §7.3, §7.4).
CREATE TABLE member_packages (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id         UUID NOT NULL REFERENCES member_profiles(user_id) ON DELETE CASCADE,
    package_def_id    UUID NOT NULL REFERENCES package_definitions(id),
    status            package_status NOT NULL DEFAULT 'pending_payment',  -- spec §9.6, §10
    classes_total     INTEGER NOT NULL CHECK (classes_total > 0),
    classes_consumed  INTEGER NOT NULL DEFAULT 0 CHECK (classes_consumed >= 0),
    classes_pending   INTEGER NOT NULL DEFAULT 0 CHECK (classes_pending  >= 0),
    validity_weeks    INTEGER NOT NULL CHECK (validity_weeks > 0),
    price             NUMERIC(10,2) NOT NULL,
    currency          CHAR(3) NOT NULL DEFAULT 'JOD',
    requested_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    activated_at      TIMESTAMPTZ,                 -- set on admin activation (spec §9.3)
    activated_by      UUID REFERENCES users(id),
    expires_at        TIMESTAMPTZ,                 -- = activated_at + validity_weeks (trigger)
    -- Spec §7.2 core invariant: cannot consume+hold more than the package holds.
    CONSTRAINT chk_no_overbooking
        CHECK (classes_consumed + classes_pending <= classes_total)
);
CREATE INDEX idx_mpkg_member ON member_packages(member_id);
CREATE INDEX idx_mpkg_status ON member_packages(status);
CREATE INDEX idx_mpkg_expires ON member_packages(expires_at);

-- Offline payment note shown to members (spec §10.3). Admin-configurable content.
CREATE TABLE payment_notes (
    id          INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),  -- single editable note
    body_en     TEXT NOT NULL DEFAULT '',
    body_ar     TEXT NOT NULL DEFAULT '',
    updated_by  UUID REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO payment_notes (id) VALUES (1);

-- =============================================================================
-- BOOKINGS (spec §6, §7, §8)
-- =============================================================================

CREATE TABLE bookings (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id         UUID NOT NULL REFERENCES member_profiles(user_id) ON DELETE CASCADE,
    session_id        UUID NOT NULL REFERENCES coach_sessions(id) ON DELETE CASCADE,
    -- NULL for the free trial booking; required for all package bookings (spec §3.4, §3.5).
    member_package_id UUID REFERENCES member_packages(id),
    is_trial          BOOLEAN NOT NULL DEFAULT FALSE,
    status            booking_status NOT NULL DEFAULT 'pending',
    rejection_reason  TEXT,        -- required when status = 'rejected' (spec §6.4)
    cancel_kind       cancel_kind, -- set when cancelled (drives deduction, spec §8)
    booked_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at        TIMESTAMPTZ, -- accept/reject time
    completed_at      TIMESTAMPTZ, -- coach marked done (spec §6.6)
    cancelled_at      TIMESTAMPTZ,
    -- a member books a given session once
    UNIQUE (member_id, session_id),
    -- trial bookings carry no package; package bookings must reference one
    CHECK (
        (is_trial AND member_package_id IS NULL) OR
        (NOT is_trial AND member_package_id IS NOT NULL)
    ),
    CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_booking_member ON bookings(member_id);
CREATE INDEX idx_booking_session ON bookings(session_id);
CREATE INDEX idx_booking_status ON bookings(status);

-- =============================================================================
-- REVIEWS & RATINGS (spec §12) — only after a completed session
-- =============================================================================

CREATE TABLE reviews (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id  UUID NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES member_profiles(user_id) ON DELETE CASCADE,
    coach_id    UUID NOT NULL REFERENCES coach_profiles(user_id) ON DELETE CASCADE,
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_review_coach ON reviews(coach_id);

-- =============================================================================
-- NOTIFICATIONS (spec §14)
-- =============================================================================

CREATE TABLE notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        notification_type NOT NULL,
    title_en    TEXT NOT NULL,
    title_ar    TEXT NOT NULL,
    body_en     TEXT,
    body_ar     TEXT,
    related_id  UUID,        -- booking / package id for deep-linking
    scheduled_at TIMESTAMPTZ, -- e.g. 15-min-before reminder (spec §14.3)
    sent_at     TIMESTAMPTZ,
    read_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notif_user ON notifications(user_id, read_at);
CREATE INDEX idx_notif_schedule ON notifications(scheduled_at) WHERE sent_at IS NULL;

-- =============================================================================
-- TRIGGERS — enforce spec rules that cannot live in a single CHECK
-- =============================================================================

-- (1) Expiry clock starts on activation (spec §9.3): when status flips to 'active'
--     and activated_at is set, compute expires_at = activated_at + validity_weeks.
CREATE OR REPLACE FUNCTION fn_set_package_expiry() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'active' AND NEW.activated_at IS NOT NULL
       AND (OLD.status IS DISTINCT FROM 'active') THEN
        NEW.expires_at := NEW.activated_at + (NEW.validity_weeks * INTERVAL '1 week');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_package_expiry
    BEFORE UPDATE ON member_packages
    FOR EACH ROW EXECUTE FUNCTION fn_set_package_expiry();

-- (2) Keep coach rating aggregate current when a review is added (spec §13.7).
CREATE OR REPLACE FUNCTION fn_update_coach_rating() RETURNS TRIGGER AS $$
BEGIN
    UPDATE coach_profiles
    SET avg_rating = (SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews WHERE coach_id = NEW.coach_id),
        rating_count = (SELECT COUNT(*) FROM reviews WHERE coach_id = NEW.coach_id)
    WHERE user_id = NEW.coach_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_coach_rating
    AFTER INSERT ON reviews
    FOR EACH ROW EXECUTE FUNCTION fn_update_coach_rating();

-- NOTE on counter transitions (spec §7):
--   The chk_no_overbooking CHECK guarantees the invariant at all times. The
--   actual +/- moves on classes_pending and classes_consumed are performed by
--   the Node service inside a single transaction per booking event:
--     book          -> classes_pending += 1
--     coach accept  -> (no counter change)
--     coach reject  -> classes_pending -= 1
--     complete      -> classes_pending -= 1, classes_consumed += 1
--     same-day cancel -> classes_pending -= 1, classes_consumed += 1
--     early cancel  -> classes_pending -= 1
--   Bookability is checked as: classes_total - classes_consumed - classes_pending > 0
--   and (optionally) session.start_at <= package.expires_at (spec §9.5).
-- =============================================================================
