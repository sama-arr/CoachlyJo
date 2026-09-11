-- =============================================================================
-- Schema migration v0.8 -> v0.9
--   (1) Locations: CoachlyJo operates inside Amman for now — the governorate
--       list is DEACTIVATED (not deleted, so existing member locations stay
--       valid and cities can be re-enabled on expansion) and replaced with
--       Amman districts.
--   (3) Admin package adjustments: every add / deduct / cancel / move is
--       recorded with the admin, timestamp, before-after values and a reason.
-- =============================================================================

-- ---- (1) Amman areas ---------------------------------------------------------
UPDATE locations SET is_active = FALSE
 WHERE name_en IN ('Amman','Zarqa','Irbid','Aqaba','Salt','Madaba','Jerash',
                   'Ajloun','Mafraq','Karak','Tafilah','Maan','Ma''an','Balqa');

INSERT INTO locations (name_en, name_ar, sort_order) VALUES
    ('Abdoun',            'عبدون',            10),
    ('Sweifieh',          'الصويفية',          11),
    ('Um Uthaina',        'أم أذينة',          12),
    ('Deir Ghbar',        'دير غبار',          13),
    ('Dabouq',            'دابوق',            14),
    ('Khalda',            'خلدا',             15),
    ('Tla'' Al Ali',      'تلاع العلي',        16),
    ('Al Rabieh',         'الرابية',           17),
    ('Um Al Summaq',      'أم السماق',         18),
    ('Jubeiha',           'الجبيهة',           19),
    ('Shmeisani',         'الشميساني',         20),
    ('Abdali',            'العبدلي',           21),
    ('Jabal Amman',       'جبل عمّان',         22),
    ('Jabal Al Weibdeh',  'جبل اللويبدة',      23),
    ('Wadi Saqra',        'وادي صقرة',         24),
    ('Sports City',       'المدينة الرياضية',   25),
    ('Gardens',           'الجاردنز',          26),
    ('Mecca Street',      'شارع مكة',          27),
    ('7th Circle',        'الدوار السابع',      28),
    ('8th Circle',        'الدوار الثامن',      29),
    ('Marj Al Hamam',     'مرج الحمام',        30),
    ('Naour',             'ناعور',            31),
    ('Tabarbour',         'طبربور',           32),
    ('Marka',             'ماركا',            33),
    ('Al Hashmi',         'الهاشمي',           34),
    ('Al Muqabalain',     'المقابلين',         35),
    ('Al Yasmin',         'الياسمين',          36),
    ('Al Bayader',        'البيادر',           37),
    ('Sahab',             'سحاب',             38),
    ('Airport Road',      'طريق المطار',        39)
ON CONFLICT (name_en) DO UPDATE
    SET name_ar = EXCLUDED.name_ar,
        sort_order = EXCLUDED.sort_order,
        is_active = TRUE;

-- ---- (3) Package adjustment audit trail --------------------------------------
CREATE TABLE IF NOT EXISTS package_adjustments (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    package_id   UUID NOT NULL REFERENCES member_packages(id) ON DELETE CASCADE,
    admin_id     UUID NOT NULL REFERENCES users(id),
    action       TEXT NOT NULL CHECK (action IN ('add_classes','deduct_classes','cancel','move_coach','extend_expiry')),
    before_value TEXT,
    after_value  TEXT,
    reason       TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pkg_adj_package ON package_adjustments(package_id, created_at DESC);

INSERT INTO schema_meta (id, version) VALUES (1, 9)
ON CONFLICT (id) DO UPDATE SET version = GREATEST(schema_meta.version, 9);
