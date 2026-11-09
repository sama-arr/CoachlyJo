# CoachlyJo — Fitness Coaching Platform (v0.15 · app 1.1.1+17)

A mobile fitness-coaching platform connecting **Members** (clients) with verified **Coaches** for online and in-person sessions. Built per the consolidated spec v1.0.

- **Backend:** Node.js (Express) + PostgreSQL
- **Frontend:** Flutter (iOS + Android + Web from one codebase)
- **Market:** Jordan · **Languages:** Arabic + English · **Currency:** JOD · **Timezone:** Asia/Amman

> **Status of this build.** The **backend is complete and tested** — 123 automated end-to-end checks (v0.4 suite) pass against a live PostgreSQL database, covering registration/OTP, coach approval, the paid single-session trial (one per coach), coach-bound packages, proof-of-payment lifecycle, offline package activation, the credit-counter rules, expiry, reviews, and reports. The **Flutter app** covers all core screens and flows and is provided as reviewed source; you compile it with the Flutter SDK (it could not be compiled in the build environment). Items intentionally simplified are listed under "Scope notes" at the end.

---

## Repository layout

```
apex-v0.4/
├── backend/
│   ├── src/
│   │   ├── server.js              # Express entry
│   │   ├── db/
│   │   │   ├── pool.js            # PG pool + withTransaction()
│   │   │   ├── schema.sql         # full schema (tables, triggers, constraints)
│   │   │   ├── migrate.js         # idempotent runner (baseline + v0_2..v0_4)
│   │   │   ├── migrate_v0_2.sql   # v0.2 incremental migration
│   │   │   ├── migrate_v0_3.sql   # v0.3 incremental migration
│   │   │   ├── migrate_v0_4.sql   # v0.4: coach-bound packages, proof of payment
│   │   │   ├── version.js         # expected schema version (4)
│   │   │   └── seed.js            # admin user, packages, slots, payment note
│   │   ├── middleware/auth.js     # JWT + role guards
│   │   ├── services/
│   │   │   ├── booking.service.js # the credit-counter logic (spec §7/§8/§9)
│   │   │   └── zoom.service.js    # Zoom link (dev placeholder + real path)
│   │   └── routes/                # auth, members, coaches, bookings, admin
│   ├── tests/e2e.js               # end-to-end API test (123 checks)
│   ├── package.json
│   └── .env.example
└── frontend/
    ├── lib/
    │   ├── main.dart              # app, theme, RTL/locale, role routing
    │   ├── core/                  # config, api client, auth state
    │   └── screens/               # login, register, member/coach/admin homes
    └── pubspec.yaml
```

---

## Part 1 — Backend setup & testing

### Prerequisites
- Node.js 18+ (tested on Node 22)
- PostgreSQL 14+ (tested on PostgreSQL 16)

### 1. Install PostgreSQL and create the database

```bash
# macOS (Homebrew)
brew install postgresql@16 && brew services start postgresql@16

# Ubuntu/Debian
sudo apt-get install -y postgresql postgresql-contrib
sudo service postgresql start
```

Create the database and an app user:

```bash
sudo -u postgres psql <<'SQL'
CREATE DATABASE fitness;
CREATE USER fitapp WITH PASSWORD 'fitpass';
GRANT ALL PRIVILEGES ON DATABASE fitness TO fitapp;
\c fitness
GRANT ALL ON SCHEMA public TO fitapp;
SQL
```

### 2. Configure and install the backend

```bash
cd backend
cp .env.example .env          # adjust credentials if you changed them
npm install
```

### 2b. Email (SMTP) setup — optional, needed for real reset codes

Without SMTP the app runs in dev mode: verification and reset codes are printed
in the server console and returned in API responses (`OTP_DEV_MODE=true`).
To send real email, set in `backend/.env` (any SMTP provider works):

```
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user-or-apikey
SMTP_PASS=secret
SMTP_FROM="Apex Fitness <no-reply@example.com>"
OTP_DEV_MODE=false
```


> **All four Zoom variables are required.** `ZOOM_ACCOUNT_ID`, `ZOOM_CLIENT_ID`,
> `ZOOM_CLIENT_SECRET` **and `ZOOM_HOST_USER`** (the email of the Zoom account
> meetings are hosted under). If any one is missing the integration counts as
> unconfigured: meetings are not created and bookings are accepted without a
> link. Check **Admin → Setup → Integration health** after any deploy — it shows
> exactly which variables are missing and how many confirmed sessions currently
> have no link.

### 2c. Zoom setup — optional, needed for real meeting links

1. Go to `marketplace.zoom.us` -> **Develop** -> **Build App** -> **Server-to-Server OAuth**.
2. In **Scopes**, add `meeting:write:admin`, then activate the app.
3. Copy the three credentials into `backend/.env`:

```
ZOOM_ACCOUNT_ID=...
ZOOM_CLIENT_ID=...
ZOOM_CLIENT_SECRET=...
```

Restart the server. New online bookings now create real Zoom meetings.
Until then, placeholder links are used (Zoom reports "invalid meeting ID" —
expected in dev). If a Zoom API call fails at runtime the server logs the error
and falls back to a placeholder so bookings are never blocked.

### 3. Create the tables and seed data

> **Upgrading from an earlier version?** Just run `npm run migrate` on your
> existing database — it is idempotent and applies only what is missing, then
> `GET /health/schema` should report `{"current":15,"expected":15,"upToDate":true}`.
> No reseeding needed. 

```bash
npm run migrate               # loads src/db/schema.sql
npm run seed                  # creates admin + packages + slot templates + payment note
```

The seed prints the admin login:
```
Admin: admin@fitness.local / admin1234
```

> If `migrate` reports a permissions error on tables, run the GRANT block in step 1 again **after** migrate, or simply run migrate as the `postgres` superuser. (The seed grants are handled automatically.)

> **v0.13 file naming:** source files carry a `_v0_13` suffix
> (`server_v0_13.js`, `member_home_v0_13.dart`, ...) so versions never mix when
> extracted side by side. Two files keep fixed names because their frameworks
> require it: `frontend/lib/main.dart` (Flutter entry point) and
> `pubspec.yaml`. Underscores are used rather than `-v0.9` because the Dart
> analyzer flags hyphens/dots in filenames. All npm scripts below already point
> at the renamed files. **SQL migrations are never renamed** — they are
> versioned history (`migrate_v0_2.sql` ... `migrate_v0_13.sql`) and the runner
> applies them in order.

> **Static pre-flight (optional):** `python3 tools/static_checks.py` runs a
> toolchain-free sanity check of the Flutter code (import resolution, balance,
> const/i18n misuse, unused private members, and every frontend API path against
> the backend routes). `flutter analyze` remains the authoritative check.


## Push notifications (v0.14)

The app ships complete without Firebase: notifications appear in the in-app
centre and by email, and `PushService.init()` fails soft. Add the three pieces
below and OS notifications start working with **no code change and no new
build logic** — just a rebuild.

### 1. Firebase project
1. console.firebase.google.com → **Add project** → name it `CoachlyJo`
2. **Add app → Android**, package name `com.coachlyjo.app` →
   download `google-services.json` → put it in `frontend/android/app/`
3. **Add app → iOS**, bundle ID `com.coachlyjo.app` →
   download `GoogleService-Info.plist` → add it to `frontend/ios/Runner/`
   **in Xcode** (drag into the Runner target so it is bundled, not just copied)

### 2. iOS push key (Apple)
1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** → **+**
2. Tick **Apple Push Notifications service (APNs)**, create, download the `.p8`
   (you can only download it once)
3. Firebase console → Project settings → **Cloud Messaging** → iOS app →
   **Upload** the `.p8`, with your Key ID and Team ID
4. In Xcode, enable the **Push Notifications** capability on the Runner target

### 3. Server credentials
Firebase console → Project settings → **Service accounts** → **Generate new
private key**. From the JSON, set on Render:

```
FIREBASE_PROJECT_ID=coachlyjo-xxxx
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@coachlyjo-xxxx.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n
```

Paste the private key exactly as it appears in the JSON, `\n` sequences and
all — the server converts them back to real newlines.

### Checking it works
Server logs show `[push]` lines only on failure. Register a device (sign in on a
phone), then trigger any notification — accept a booking, activate a package —
and it should arrive in the tray. If nothing arrives: confirm the device token
reached `device_tokens`, and on iOS confirm the APNs key is uploaded, which is
the usual culprit.

### 4. Run the API

```bash
npm start                     # http://localhost:4000
# health check:
curl http://localhost:4000/health     # -> {"ok":true,...}
```

### 5. Run the automated end-to-end test

With the API running in one terminal:

```bash
node tests/e2e_v0_13.js
```

Expected tail:
```
=== RESULT: 352 passed, 0 failed ===
```

> Check-count history: 123 (v0.4) -> 111 (v0.5) -> 126 (v0.6) -> 137 (v0.7) ->
> 137 (v0.8) -> 168 (v0.9) -> 206 (v0.10) -> 249 (v0.11) -> 250 (v0.12) ->
> 291 (v0.13: account deletion, legal documents, public web pages, token revocation).

This drives the real API through: admin login → member register + OTP verify + login → coach register + docs → admin approval → coach publishes sessions → free trial (and its one-per-member block) → package request + admin activation (expiry set) → the credit counters (hold on booking, deduction on completion, release on rejection) → review-after-completion → expiry-window block → reports.

### 6. Manual testing with curl (optional)

```bash
# Login as admin
TOKEN=$(curl -s localhost:4000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@fitness.local","password":"admin1234"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

# Read platform settings
curl -s localhost:4000/api/admin/settings -H "Authorization: Bearer $TOKEN"

# Register a member (OTP is returned in dev mode as devOtp)
curl -s localhost:4000/api/auth/register/member -H 'Content-Type: application/json' \
  -d '{"email":"lina@x.com","phone":"+962790000001","password":"secret12","firstName":"Lina","lastName":"A"}'
```

In **dev mode** (`OTP_DEV_MODE=true`) the OTP code is returned in the registration response (`devOtp`) and logged to the server console — no SMS/email provider needed for testing.

---

## Part 2 — Frontend (Flutter) setup & testing

### Prerequisites
- Flutter SDK 3.x (`flutter --version`)
- An Android emulator, iOS simulator, Chrome, or a physical device

### 1. Install dependencies

```bash
cd frontend
flutter pub get
flutter analyze          # static check — recommended before first run
```

### 2. Point the app at your backend

The API base URL is configurable. Pick the value for your target:

| Target | API_BASE_URL |
|---|---|
| Android emulator | `http://10.0.2.2:4000` (default) |
| iOS simulator | `http://localhost:4000` |
| Chrome (web) | `http://localhost:4000` |
| Physical device | `http://<your-computer-LAN-IP>:4000` |

### 3. Run

```bash
# Android emulator (uses default 10.0.2.2)
flutter run

# iOS simulator or web — override the URL:
flutter run --dart-define=API_BASE_URL=http://localhost:4000

# Web specifically:
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:4000
```

### 4. Try the flows

Log in with the seeded admin (`admin@fitness.local` / `admin1234`) to approve coaches and activate packages, or tap **Create an account** to register as a member or coach. In dev mode the registration screen shows the OTP code on the verify step so you can complete sign-up without a real SMS.

A full manual walkthrough:
1. **Register a coach** → submit documents → log out.
2. **Log in as admin** → Coaches tab → **Approve** the coach.
3. **Register a member** → verify OTP.
4. As member → **Packages** → request the 6-class package → the dialog shows the bank details, then upload proof of payment.
5. **Log in as admin** → Payments tab → **Activate** the member's package.
6. As member → open the approved coach → **Book** a session (or **Trial**).
7. **Log in as coach** → Requests → **Accept**, later **Complete**.
8. As member → Bookings → **Review** the completed session.
9. **Admin** → Reports to see it reflected.

> Note: a coach must set availability before a member can book. As of v0.5 the coach does this in-app: **Coach → Availability tab** — pick a session duration, toggle days on, add time ranges (with an Online/In-person chip each). Bookable sessions are generated automatically for the next 4 weeks and appear in the Sessions tab and to members. Try also: **Forgot password?** on the login screen, and cancelling a booking to see the same-day deduction warning.

---

## Key design points (where the spec's hard rules live)

- **Credit counters (spec §7)** are enforced both in `booking.service.js` and by a database `CHECK (classes_consumed + classes_pending <= classes_total)` — overbooking is impossible even if app code has a bug.
- **Package expiry (spec §9.3)** is set by a database trigger when admin activates: `expires_at = activated_at + validity_weeks`.
- **1-on-1 vs group (spec §5.2)** is a generated column from `capacity > 1`.
- **Passwords (spec §15)** are bcrypt-hashed, min 8 chars, no max.
- **Offline payment (spec §10)**: member request creates a `pending_payment` row and shows the admin-configurable note; admin activation credits the classes.

---

## Scope notes (intentionally simplified in this build)

- **Push notifications & 15-min reminders (spec §11, §14)**: the schema has a `notifications` table and scheduling column; wiring to FCM/APNs and a scheduler (e.g. a cron worker) is not included.
- **Zoom**: dev mode returns a placeholder meeting link so online-session flows are testable. The real Server-to-Server OAuth call is documented in `zoom.service.js`; add credentials to enable.
- **Document upload**: the API stores a file URL reference; a production app adds a file picker + object storage (e.g. S3).
- **Arabic content**: the data model and Material RTL support are in place; full screen-by-screen Arabic localization strings would be added with an `intl` ARB workflow.

These are additive — none change the core data model or the tested flows.

---

## Changelog

### v0.3
Backend tests expanded to **78 end-to-end checks**, all passing. Highlights:
- **Root-cause fix for "column does not exist" (items 13,14):** migrations are now idempotent and applied together by `npm run migrate` (schema.sql + migrate_v0_2.sql + migrate_v0_3.sql). A `schema_meta` version is written, the server logs a warning at startup if the DB is stale, `GET /health/schema` reports status, and undefined-column errors now return a clear "Database schema is out of date. Run: npm run migrate" instead of a raw error. **If you hit 13/14, run `npm run migrate` once.**
- **Loading-forever fixed (items 1,3,9):** Coaches, Packages, People, and Reports tabs now show an error + Retry instead of an infinite spinner when a request fails; null-safe rendering.
- **Registration (items 10,11,12):** DOB is a calendar date-picker (date-only); nationality is a standard country dropdown; current location is an admin-configurable dropdown; birth place added. Email format validated; phone entered as `07XXXXXXXX` (10 digits) and stored normalized as `009627XXXXXXXX`. Validation enforced on both client and server.
- **Admin-configurable packages (item 4):** Setup → Packages allows create/edit of price, classes, validity, mode, active. Edits never change already-purchased packages (snapshots preserved). `GET/POST/PUT /api/admin/packages`.
- **Admin-configurable locations (items 10,11):** Setup → Locations add/remove; `GET/POST/PATCH/DELETE /api/admin/locations`, public `GET /api/auth/locations`.
- **Reviews show their session (item 2):** admin coach view lists each review with its session date + delivery.
- **Settings popups (items 5,6,8):** top-right menu per role — admin: change password / payment details / sign out; coach: change password / change bio / sign out; member: change password / sign out.
- **Coach Profile footer tab removed (item 7);** bio now lives in the settings popup.

Run `npm run migrate && npm run seed && npm start`, then the suite of that version → `78 passed, 0 failed`.

### v0.2
14 feature items (docs-at-signup, questionnaire, package split, single session, etc.). Tests 38 → 66.

### v0.1
Coach availability management (spec §5.4) and admin session structure (spec §5.1). Tests 29 → 38.
Backend tests expanded to **66 end-to-end checks**, all passing. Changes:
- **Coach documents at signup (item 1):** uploaded during registration (pdf/doc/docx/jpg/png), stored as binary in PostgreSQL (10MB cap, type-validated); admin can list and download them. Endpoints: `register/coach` accepts `documents[]`, `GET /api/admin/coaches/:id/documents`, `GET /api/admin/documents/:docId/download`.
- **Member location + configurable questionnaire (item 2):** signup captures location (text) and a dynamic questionnaire; the question set is admin-managed. Endpoints: `GET /api/auth/questionnaire`, admin `GET/POST/DELETE /api/admin/questionnaire`.
- **Zoom link to both sides (item 3):** member and coach both see the link once a session is accepted.
- **Settings page, all roles (item 4):** change password (old → new → confirm); coaches edit their About/bio. `POST /api/auth/change-password`, `GET/PUT /api/coaches/profile`.
- **Review button hides after submit (item 5):** bookings carry a `reviewed` flag.
- **Coach profile for members (item 6):** Coaches tab opens a profile with bio, rating, reviews, then sessions.
- **Admin people directory (item 7):** lists all coaches and members; tap for profile + metrics; per-coach today summary. `GET /api/admin/coaches`, `/members`, `/coaches/:id/summary`, `/members/:id/summary`.
- **Packages split Online / In-person (item 8):** catalogue has both variants; booking a mismatched session shows "You can only book online/in-person sessions" instead of a generic block.
- **Activation + expiry dates shown (item 9)** on member packages.
- **No free trial → one paid Single Session (item 10):** purchasable once per member via the offline flow; a package is required afterwards.
- **Pre-booking cap = 3 (item 11):** at most 3 concurrent upcoming bookings, any package.
- **Coach sees member phone + location on accept (item 12).**
- **Admin payment-details editor (item 13)** in Settings (free text, EN/AR).
- **Admin reject payment (item 14):** Payments tab has a Reject button (pending → cancelled). `POST /api/admin/packages/:id/reject`.

Run `npm run migrate` (applies `schema.sql` then `migrate_v0_2.sql`) and `npm run seed`, then the suite of that version → `66 passed, 0 failed`.

> **Frontend note (v0.2):** document upload uses the `file_picker` package — run `flutter pub get` after upgrading. As before, `flutter analyze` is your authoritative compile check; the Dart toolchain could not be run in the build environment.

### v0.1
- Coach availability management (spec §5.4) and admin session structure (spec §5.1). Tests 29 → 38.

---

## What's new in v0.4

**Upgrading an existing v0.3 database:** just run `npm run migrate` — the runner is now fully idempotent (it detects the existing baseline and applies only the incremental migrations). `/health/schema` should then report `{"current":4,"expected":4,"upToDate":true}`. New installs are unchanged: `npm run migrate && npm run seed`.

1. **Admin can view coach documents.** Document rows are tappable everywhere the admin sees them (pending-approval cards and the coach profile under People). Images preview inline; PDFs/Word files open in the device's viewer via a tokenized download URL.
2. **Zoom links are hyperlinks.** "Join Zoom session" opens the Zoom app/browser, for both member and coach.
3. **Single session = one paid trial per coach, permanent.** A member can buy the single session once with each coach, ever. A request the admin cancelled does not consume the allowance. Enforced by a partial unique index (`uq_single_per_coach`) plus a friendly API message.
4. **Completed packages leave the active view.** The coach's Clients tab has Active / Completed segments: a package moves to Completed when all classes are consumed or it expires. Data is retained for reports.
5. **Booking restrictions are popups.** "You can only book an online session" (and all other booking errors) now show as dialogs instead of inline banners.
6. **Proof of payment.** Purchasing requires uploading a payment screenshot (jpg/png, ≤10MB). The admin's Payments tab shows the request with a "View proof" preview and three actions: **Activate**, **Reject proof** (with a reason — the member sees it and can re-upload), or **Cancel request** outright.
7. **Packages are coach-bound.** Purchase flow: pick a coach → pick a package → attach proof. Bookings consume only a package bought for that session's coach. A member may hold packages with several coaches at once but only one usable (pending/active, not exhausted) purchase per coach — DB-enforced (`uq_concurrent_pkg_per_coach`). Admin can **reassign** a pending/active package to another coach from the member's profile (People → member → Packages → Reassign), for cases like a coach leaving.
8. **Admin dashboards.** Reports tab now shows headline stats (revenue, sessions completed, active/total members, pending payments/coaches), revenue-per-week and sessions-per-week charts, package sales, and a coach performance leaderboard, all filterable by 7/30/90 days.
9. **Coach dashboard.** New Dashboard tab for coaches: upcoming sessions, pending requests, completed sessions, active clients, completion rate, rating, and a weekly trend chart. Activity only — no revenue figures are exposed to coaches.
10. **Coach sees their subscribers.** The Clients tab lists each member subscribed with that coach: package name, sessions used/remaining, expiry, next/last session, and contact details.

### v0.15 — tester feedback round 2

1. **Documents and the profile photo now upload from camera, gallery or files.**
   v0.14 offered only the file browser, so a coach holding a paper certificate
   had to photograph it, find it in Files and pick it from there. All three
   document categories and the profile photo use the same three-source picker.
2. **Light theme fixed properly.** The green status colour and the greys were
   hardcoded dark-mode values, so on white the green went muddy and captions
   became unreadable — on the cancellation policy, home, find-a-coach,
   notifications, privacy and terms screens. ~90 hardcoded colours across 17
   files are replaced by a semantic palette (`AppColors.of(context)`) that
   resolves per brightness, with a deeper green for light mode. The static
   checker now fails the build if a screen reintroduces a hardcoded colour in a
   const context or uses one without scope.
3. **About screen**, directly above Sign out: app version, build number, the API
   host this build talks to, a live server check, and a one-tap "copy details
   for a bug report" — so it is obvious whether a tester is on staging or
   production.
4. **Zoom link fixed — root cause: `ZOOM_HOST_USER` was missing from
   `render.yaml`.** `hasCreds()` requires four variables and only three were
   declared, so Zoom counted as unconfigured, meeting creation failed and
   bookings were accepted with no link. Alongside the fix:
   - `link_pending` is exposed to both apps: members see "meeting link coming
     soon" instead of an empty space, and coaches get **Retry** and
     **Add my link** actions;
   - `POST /api/bookings/:id/retry-meeting-link` recreates a missing link after
     a configuration fix, without cancelling and rebooking;
   - **Admin → Integration health** (`GET /api/health/integrations`) reports
     Zoom, SMTP, push and schema state plus the count of confirmed sessions with
     no link, so a missing variable is visible instead of silent.
5. **iOS push notifications fixed.** iOS hands Firebase an APNs token
   asynchronously and `getToken()` returns null until it arrives; v0.14 called
   it immediately, so iOS devices were never registered — which is exactly why
   Android worked and iOS did not. The service now waits for the APNs token
   (with a bounded retry) before registering, and sets
   `setForegroundNotificationPresentationOptions` so alerts also appear while
   the app is open. Foreground duplicates on iOS are suppressed.

**Also fixed:** `npm run seed` duplicated the entire package catalogue on every
run — the `ON CONFLICT DO NOTHING` had no unique constraint to act on, so a
second seed left members seeing sixteen packages. Migration v0_15 removes
unpurchased duplicates and adds the missing unique index; the seed is now
genuinely idempotent, and a test guards it.

**Carried over from your staging work:** questionnaire dropdowns, the three
coach document categories mapped to the correct enum values, the pending-coach
navigation fix, Firebase options for both platforms, Android desugaring and the
staging Codemagic/Render configuration.

### v0.14 — tester feedback round

1. **Short registration**: name, email, phone, password and nationality only.
   Nationality defaults to **Jordan** and is searchable. Birth place is gone
   from the product and the database.
2. **Complete Profile** is a mandatory tab after signing in — date of birth,
   area and the fitness questionnaire for members; date of birth, years of
   experience, specialties, **required documents** and an optional photo for
   coaches. Enforced server-side: no booking or purchase until it is done, and
   the API returns exactly which fields are missing.
3. **Coaches are locked until approved**: a permanent "Awaiting admin approval"
   banner, and the schedule tabs are absent rather than present-but-failing.
   Enforced on 12 API routes, not just in the UI.
4. **Documents are required** before a coach can be reviewed.
5. "Rules & regulations" is now **Cancellation policy**, collapsed by default.
6. **Contact us** in the drawer and Settings — tappable email, phone, WhatsApp
   and Instagram, all editable in **Admin → Setup → Contact details**.
7. **How it works** steps are stacked, not a carousel.
8. **Change password** is its own screen, opened from a row.
9. Nationality search, defaulting to Jordan.
10. **Branded HTML emails** for verification and reset codes — gradient header,
    the wordmark as styled text (images are blocked by most mail clients),
    large code block, Arabic RTL version, plain-text fallback.
11. **Coach experience and specialty** compose the bio automatically in both
    languages; optional **profile photo**.
12. **Light / dark / system theme**, chosen in Settings, saved per device and
    mirrored to the account.
13. **OS push notifications** via Firebase (see "Push notifications" above) with
    **15-minute reminders** added to the 24-hour and 1-hour ones, driven by a
    5-minute scheduler tick.
14. Notifications can no longer be deleted — they are a record.
15. Bottom bars show the label **only on the selected tab**, so six tabs stop
    squeezing.
16. **Per-week availability calendar**: a real grid of days × hours. Tap an
    hour to open or close it, long-press a block to switch online/in-person,
    **Copy last week**, **Clear week**, and booked hours locked. Existing
    recurring availability is carried forward into 8 weeks of real dates by the
    migration, so no coach loses their schedule.
17. Coach dashboard "Upcoming sessions" counts **booked** sessions only.
18. The heartbeat background animation is gone.
19. **Gym illustrations** — dumbbell, kettlebell, athlete, trophy, heart-rate and
    stopwatch — drawn as vectors, so they recolour with the theme and cost
    kilobytes rather than megabytes.
20. The "have a lawyer review this" line is removed from the user-facing legal
    text (still worth doing — just not shown to members).
21. The settings cog is now a **hamburger opening a slide-out drawer**.

**Also fixed in this release**
- **Zoom failure no longer blocks acceptance.** Creating the meeting before
  accepting was right, but throwing meant a coach could not accept *any* online
  session when Zoom was unconfigured or briefly down. The booking is now
  accepted, the link is marked pending, and the coach can paste their own
  Zoom/Meet link (`PUT /api/bookings/:id/meeting-link`).
- `birth_place` was still written by the account-deletion service and the coach
  member-detail query; both would have thrown after the column was dropped.
- The e2e suite is back to green and extended: **338 checks**, covering the
  two-step password reset, Zoom-before-accept, mode-filtered session lists and
  every v0.14 feature.

### v0.13 — App Store / Play Store compliance

See **STORE_RELEASE.md** for the full submission checklist (accounts, forms,
assets, and the Apple payments question). In the code:

1. **Account deletion**, required by both stores. `Settings -> Delete account`
   previews what will be lost, requires typing DELETE plus the account password,
   then erases name, email, phone, date of birth, location, questionnaire
   answers, uploaded documents, payment-proof images and notifications; cancels
   upcoming sessions without deducting a class and notifies the other party.
   Anonymised purchase records are kept for accounting — disclosed in the
   privacy policy. Admin accounts are refused (deleting one would lock the
   platform); admins can delete member/coach accounts on request.
2. **Public web deletion route** at `/delete-account` (English + Arabic) —
   Google Play requires a path that works without the app installed. Requests
   land in **Setup -> Account deletion requests** for the admin to verify and
   complete.
3. **Privacy policy and terms**, bilingual and admin-editable, reachable from
   Settings *and from the login screen* (reviewers check before signing in), and
   served publicly at `/privacy` and `/terms` — those are the URLs for the store
   listings. The seeded text describes what the app actually collects and is a
   starting point for your lawyer, not finished legal advice.
4. **Production hardening**: helmet security headers, CORS allowlist via
   `CORS_ORIGINS`, rate limiting (tighter on auth endpoints), `trust proxy`, and
   a startup guard that refuses to boot with `NODE_ENV=production` while
   `OTP_DEV_MODE=true` or `JWT_SECRET` is still the default.
5. **Token revocation**: a deleted or deactivated account's token is rejected on
   the next request instead of remaining valid until it expires.

### v0.12

**Rebrand to CoachlyJo.** The app name, wordmark, notification email subjects,
home-page copy (English and Arabic) and the launcher icon all use the new name.
A migration rewrites the seeded home/rules copy in place, so an existing
database picks up the new name on `npm run migrate` without losing any text the
admin edited. `branding/coachlyjo-icon-1024.png` is the updated icon (the "C"
mark with a JO lockup); apply it with `flutter_launcher_icons` as described in
`branding/README.md`, and set the store display name to **CoachlyJo** in
`AndroidManifest.xml` and `Info.plist`.

### v0.11

1. **Delete a package definition** (Admin -> Setup -> Packages). One button that
   always does the safe thing:
   - never purchased -> **deleted permanently**;
   - already purchased -> deletion is refused with the sale count, and the app
     offers **Archive** instead: it disappears from the member catalogue at
     once, while members who bought it keep their classes and reports stay
     accurate. Archived rows show greyed out with a **Restore** button.
   The list now also shows how many times each package was sold.
2. **Notification centre** — the `notifications` table has existed since v0.1
   but nothing ever wrote to it; v0.11 fills it in. A **bell with an unread
   badge** sits in every app bar (member, coach, admin), with a full list,
   tap-to-read, mark-all-read and delete. Every notification is stored in
   **English and Arabic**, and is **also emailed** when SMTP is configured.
   Events covered:
   - *Member*: payment approved / rejected, booking accepted / rejected, coach
     cancelled your session, no-show recorded, package expiring (3 days) /
     expired, admin changed / moved / cancelled your package, session reminders.
   - *Coach*: application approved / rejected, new booking request, client
     cancelled, new client bought a package, penalty recorded, session reminders.
   - *Admin*: new coach application, new package awaiting payment approval,
     coach same-day cancellation.
   **Session reminders** go to both sides **24 hours and 1 hour before** each
   confirmed session, driven by a new 15-minute scheduler. Every scheduled
   notification carries a de-duplication key, so the job can run as often as it
   likes without ever sending twice.
   *Push notifications (FCM/APNs) are not included yet* — they need the Firebase
   project and Apple certificates. The service has a single delivery point where
   push slots in later; nothing else will change.
3. **New animated background**: the two static circles are replaced by a layered
   aurora — five soft colour blobs drifting on their own slow paths, two faint
   diagonal light streaks, a subtle grid for depth, and a **heartbeat pulse
   line** sweeping the lower third as the fitness signature. One custom painter,
   one ticker, no extra packages; it honours the OS "reduce motion" setting and
   falls back to a static frame.

**Two latent bugs found and fixed** by the new tests: creating *or* updating a
package definition with an explicit `mode` always failed (the `package_mode`
enum needed an explicit cast) — so "New package" in the admin app had never
worked; and the notification de-duplication index needed its partial predicate
repeated in `ON CONFLICT`.

### v0.10

1. **Home page** (new first tab for members *and* coaches): a CoachlyJo welcome
   panel, a swipeable **How it works** carousel, and **Rules & regulations** as
   expandable sections. A video block appears automatically once a URL is set —
   nothing to rebuild when the client has the video ready.
   Everything on this page is **admin-editable in English and Arabic** under
   **Admin -> Setup -> Home & rules** (add, edit, hide, delete blocks; set the
   video link).
2. **Cancellation & rejection policy enforced** exactly as published:
   - **Client cancels >24h before** the session -> no class deducted.
     **Within 24h** -> the class is deducted. (This replaces the old same-day
     rule so the app matches the printed policy.)
   - **Max 3 client cancellations per package** — the 4th is refused, in the UI
     and on the server; the booking stays and the coach can mark a no-show if
     the member does not attend.
   - **Coach can now cancel** an accepted session (new). The member is **never**
     charged a class. A **same-day** coach cancellation records **one session
     owed by the coach**, visible on the coach dashboard ("Sessions owed") and
     in **Admin -> Setup -> Coach penalties**, where the admin settles it.
   - **Max 3 coach rejections per client package**, reason mandatory. After
     that the reject button becomes "cancel with a reason".
3. **Coach home page** shows the coach-side rules (their cancellation rules,
   the rejection limit, and how client cancellations affect them).
4. **A more interactive front end**:
   - staggered fade/slide entrance for list items, smooth page transitions;
   - **animated counters** on hero panels;
   - **progress rings** showing classes used vs remaining on each package;
   - **skeleton loaders** instead of bare spinners;
   - tap feedback with scale + haptics, animated carousel dots, refreshed
     empty states.
   - **Dimmed palette**: same brand hues at lower intensity (#C91E97 / #D9700F
     as working tones) on a deeper base, with the full-strength colors kept for
     the wordmark and icon badges.

Also in this release: the static checker now ships in the repo at
`tools/static_checks.py`, and a migration-chain bug introduced by the v0.9
rename pass was fixed (`migrate_v0_8.sql` had been renamed away; SQL migrations
are now excluded from renames).

### v0.9

1. **Amman areas as locations**: the governorate list is replaced by **30 Amman
   districts** (Abdoun, Sweifieh, Um Uthaina, Khalda, Jabal Amman, Dabouq,
   Marj Al Hamam, ... each with its Arabic name). The old cities are
   **deactivated, not deleted** — existing member locations stay valid and a
   city can be switched back on from Admin -> Setup -> Locations when CoachlyJo
   expands beyond Amman.
2. **Member questionnaire on the coach side**: tapping a member in **Requests**
   or **Clients** opens a detail screen with their contact info, their fitness
   questionnaire answers (goal, injuries, weight, height, activity level) and
   their packages with that coach. Privacy gate enforced server-side: a coach
   can only open a member who has a package or a booking with them.
3. **Admin package management** — on any package the admin can:
   - **Add classes** / **Deduct classes** (never below classes already used or
     held by upcoming bookings),
   - **Cancel the package** — blocked while upcoming bookings exist, so nothing
     disappears silently (the admin clears those first),
   - **Move the package to another coach** — always allowed; any upcoming
     bookings with the previous coach are released automatically with **no class
     deducted**, so a package and its bookings can never point at two coaches.
   Every action requires a **reason** and is written to an **audit trail**
   (admin, timestamp, before -> after) shown as History on the package.
4. **Coach -> Members**: a coach's profile now lists every member who bought a
   package with them — packages, classes used/bought, revenue, last purchase and
   whether they're currently active — plus a shortcut to that coach's packages.
5. **Packages master screen** (new admin tab): every package in the system with
   member, coach, mode, classes (used / held / left / total), price paid,
   purchase and expiry dates, payment-proof state and admin-edit count. Filter
   by status and mode, or search by member or coach name.

Also fixed: the coach bookings API now returns `member_id` (needed to open a
member from a request), and two dead-code/analyzer issues were cleaned up. The
static checker gained two new rules (const contexts containing runtime
translations, unused private members) so `flutter analyze` stays clean.

### v0.8

1. **Richer visual design**: the theme now actually looks branded.
   - Stronger ambient magenta/orange glow on every screen.
   - **Hero panels** at the top of each tab — gradient wash, brand border, soft
     shadow, gradient icon badge, and live numbers (classes remaining/pending,
     upcoming counts, dashboard highlights).
   - **Brand cards** with gradient-tinted surfaces and colored borders replace
     flat grey rows; coaches and members get **gradient-ring avatars**.
   - **Colored status pills** (green active / orange pending / red no-show /
     grey past) replace grey chips; dashboard stat tiles are gradient-filled
     with colored icon chips, and chart bars use the brand gradient.
   - Gradient **empty states** instead of bare grey text; the login wordmark
     sits on a glowing brand halo.
2. **Language switch is now easy to find** (item 2): the settings icon opens a
   proper **Settings** hub with **Language** as the first card (English /
   العربية, full-width toggle), for members, coaches and admins alike. In v0.7
   it was buried inside the "Change password" screen.
3. **Bug fix**: a `const` widget list in the member settings menu contained a
   runtime translation call — this failed to compile under `flutter analyze`.
   Fixed, and the static checker now detects this class of error automatically
   so it can't recur.
4. **Versioned file names**: all source files carry a `_v0_13` suffix (see the
   note in Part 1) with every import, require and npm script updated; the full
   137-check suite passes against the renamed tree.

### v0.7

1. **More color ("controlled")**: ambient magenta/orange glow on every screen,
   gradient section headers with accent rules, status-colored card edges
   (green active / orange pending / red no-show / grey past), and gradient
   CTAs on key actions. Still dark, now alive.
2. **Anti-fraud completion**: a coach can mark a session **Completed** or
   **Did not show up** only AFTER the session's end time (server-enforced;
   the buttons stay locked in the UI until then). A **no-show still deducts
   the member's class** (the slot was reserved and wasted) and blocks the
   review for that session. If the coach presses neither within **48 hours**,
   the system auto-completes the booking (`completion_kind` records
   coach / no_show / auto for the admin's audit trail).
3. **Arabic**: full member + coach experience in Arabic with automatic RTL
   layout — switch from the login screen (top-right) or Settings; persists per
   device. Package names and the payment note use their Arabic texts; dates
   localize with Western digits (per client decision). Admin stays English.
4. **Bug fix (root cause)**: members could never re-book a session whose
   earlier booking was cancelled or rejected (raw duplicate-key error). The
   unique guard now applies only to live bookings; re-booking freed slots
   works and is covered by tests.

### v0.6 — "CoachlyJo"

1. **CoachlyJo brand theme**: the app is now **CoachlyJo** — dark theme on
   near-black `#0B0B0F`, brand magenta `#F20FB6` + orange `#FF770F`, one
   signature magenta->orange gradient used where it counts (wordmark, primary
   CTAs, selected states). Subtle role identity: member screens lean magenta,
   coach screens lean orange, admin keeps the neutral dual-brand look.
   A suggested app icon + apply instructions live in `branding/`.
2. **Package archive (member)**: Packages tab shows Active packages up front;
   finished / expired / cancelled ones move to a collapsed **Past packages**
   section (nothing is ever deleted). `GET /api/members/packages/mine?scope=active|past`.
3. **Booking archive (member)**: Bookings tab shows **Upcoming** only
   (pending + accepted, future); completed / cancelled / rejected / past-dated
   bookings live in a collapsed **History** section.
   `GET /api/members/bookings?scope=upcoming|history`.
4. **Coach Sessions tab = open slots only**, grouped by date like a calendar.
   Booked sessions are handled in Requests (where member details live).
   `GET /api/coaches/my-sessions?scope=open`.
5. **Fully booked sessions hidden from members**: sessions with a pending,
   accepted or completed booking no longer appear in the member's session list
   — two members can no longer request the same 1-on-1 slot.
6. **Purchase flow redesign**: the member first picks the session type
   (**Online | In-person** — deliberately no default), then the class amount
   (Single / 6 / 9 / 12 as tappable price cards), then sees the bank details
   and uploads proof — all in one dialog.

### v0.5

1. **Forgot password** (members & coaches only): "Forgot password?" on the login
   screen. A 6-character code is emailed (10-minute expiry, single use, max 5
   wrong attempts; requesting a new code invalidates the old one). The API always
   answers neutrally ("If this email is registered...") so account existence
   cannot be probed. In dev mode (no SMTP configured) the code appears in the
   server log and API response (`OTP_DEV_MODE=true`).
2. **Bank details before proof upload**: the purchase dialog now shows
   "Please pay to the following bank details:" (admin-configurable payment note)
   above the proof-of-payment upload, all in the same dialog.
   New endpoint: `GET /api/members/payment-note`.
3. **Real Zoom integration**: with Server-to-Server OAuth credentials in `.env`,
   accepting an online booking creates a real Zoom meeting (topic, start time,
   duration). Without credentials the previous placeholder links are used —
   Zoom shows "invalid meeting ID" for those, which is expected in dev.
   See "Zoom setup" below.
4. **Cancel confirmation**: members get a confirmation dialog before cancelling
   a booking that states the consequence — same-day cancellation deducts a
   class, earlier cancellation does not.
5. **Weekly availability redesign**: coaches get an **Availability** tab —
   per-weekday on/off toggle, one or more time ranges per day ("Add more"),
   an Online/In-person chip per range, and a single per-coach session duration
   (30/45/50/60/90 min, **default 50**). Bookable 1-on-1 sessions are generated
   automatically on a rolling 4-week horizon (e.g. 8-11 PM at 50 min ->
   8:00, 8:50, 9:40). Editing availability removes only FUTURE UNBOOKED
   generated sessions; booked sessions are always kept and reported back.
   Regeneration runs on every availability edit, on coach approval, at server
   startup, and every 6 hours. The Sessions tab is now read-only (with
   per-session delete for one-off exceptions). Admin slot templates are retired
   from the UI; group sessions are out of scope for now (both confirmed).

### v0.4 API additions
| Endpoint | Role | Purpose |
|---|---|---|
| `POST /api/members/packages/request` | member | now requires `coachId` + `proof {fileName, mimeType, dataBase64}` |
| `POST /api/members/packages/:id/proof` | member | re-upload proof after rejection |
| `GET /api/admin/packages/:id/payment-proof` | admin | proof image bytes |
| `POST /api/admin/packages/:id/reject-payment` | admin | reject proof with reason (member can re-upload) |
| `POST /api/admin/member-packages/:id/reassign` | admin | move a package to another coach |
| `GET /api/admin/reports/detailed?days=7\|30\|90` | admin | dashboard data |
| `GET /api/coaches/clients` | coach | subscriber list with active/completed flag |
| `GET /api/coaches/dashboard?days=7\|30\|90` | coach | activity stats + weekly trend |
| `GET /api/admin/documents/:docId/download` | admin | now also accepts `?token=` for external viewers |

### Version history
- **v0.1** — core structure, coach availability, admin session UI
- **v0.2** — 14 features (documents in DB, questionnaire config, package modes, paid single session, booking cap, offline payments, Zoom on acceptance, contact reveal, settings, admin directory)
- **v0.3** — schema version marker, phone normalization, validation, dropdowns, package/location CRUD, error+retry states
- **v0.4** — this release (items above); backend e2e suite grew from 78 to **123 checks**, and all session dates in the suite are now computed dynamically so the tests never go stale
