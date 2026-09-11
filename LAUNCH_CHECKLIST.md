# CoachlyJo — Your launch checklist (what YOU do, in order)

Written 2026-09-11. Everything code-side is done and pushed. What's left is browser
work in five consoles: **Render → Brevo → Codemagic → Google Play → App Store Connect.**
Tick boxes as you go. Secrets you need to paste are in `LAUNCH_SECRETS.local.md`
(gitignored — never commit it).

**Realistic timeline:** Steps 1–5 in one afternoon. Then a forced **14-day wait** on
Google's closed test (Step 6), during which you do Step 7 (Apple) and the listings.

---

## Already done (don't redo)

| Thing | State |
|---|---|
| Neon Postgres | project `coachlyjo` (Frankfurt), schema v13 migrated + seeded |
| Backend config | `render.yaml` in repo — Render auto-deploys from GitHub `main` |
| App native projects | `frontend/android`, `frontend/ios` committed; bundle ID **`com.coachlyjo.app`** |
| Icons | launcher icons generated; Play icon + feature graphic in `branding/generated/` |
| CI | `codemagic.yaml` — `android-release` and `ios-release` workflows |
| Version | `1.0.0+1` |
| Code health | `flutter analyze` clean, static checks pass |

---

## Step 0 — Start today, because they take calendar time

- [ ] **Recruit 12+ Android testers** (aim for 15 — people drop out). They need a Gmail
      address and an Android phone. Google requires 12 opted-in testers for **14 continuous
      days** before a new personal account can publish. Friends, family, gym clients.
- [ ] **Free ~20 GB on your C: drive.** It's at 100% (under 2 GB free). Windows and
      browsers misbehave at that level and it will bite you mid-upload. Not related to
      the app, just do it.
- [ ] **Neon compute**: free tier auto-suspends when idle; first request after idle takes
      ~1 s to wake. That's fine. Nothing to do — just know it's expected.

---

## Step 1 — Render: put the API online (15 min)

1. [ ] Go to **render.com** → sign up / log in **with GitHub**.
2. [ ] **New → Blueprint** → pick repo `sama-arr/CoachlyJo` → Render finds `render.yaml`.
3. [ ] It prompts for the `sync: false` secrets. Paste from `LAUNCH_SECRETS.local.md`:
       `PGHOST`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `JWT_SECRET`.
       Leave `SMTP_*`, `CORS_ORIGINS`, `ZOOM_*` **empty for now** (you'll add SMTP in Step 2).
4. [ ] **Apply**. First deploy takes ~3 min. Watch the logs until you see
       `API listening on http://localhost:10000`.
5. [ ] Your service gets a URL like `https://coachlyjo-api.onrender.com`.
       **Write it down in `LAUNCH_SECRETS.local.md` under API_BASE_URL.** This is the value
       every app build is compiled against.
6. [ ] Verify in a browser:
   - `https://<url>/health` → `{"ok":true,...}`
   - `https://<url>/health/schema` → `{"current":13,"expected":13,"upToDate":true}`
   - `https://<url>/privacy`, `/terms`, `/delete-account` → all show a page

> If the deploy log says the server refused to start, one of `JWT_SECRET`,
> `OTP_DEV_MODE=false`, or `PGPASSWORD` is missing — that guard is deliberate.

---

## Step 2 — Brevo: outgoing email (10 min) — **not optional**

Registration OTPs and password reset go by email. Apple's reviewer *will* tap
"Forgot password". Without SMTP the code is only in server logs.

1. [ ] **brevo.com** → free account (300 emails/day is plenty).
2. [ ] Top-right profile → **SMTP & API** → **SMTP** tab → **Generate a new SMTP key**.
3. [ ] Render → your service → **Environment** → add:

   | Key | Value |
   |---|---|
   | `SMTP_HOST` | `smtp-relay.brevo.com` |
   | `SMTP_PORT` | `587` |
   | `SMTP_USER` | the *login* shown on Brevo's SMTP tab (usually your email) |
   | `SMTP_PASS` | the SMTP key you generated |
   | `SMTP_FROM` | `CoachlyJo <no-reply@coachlyjo.com>` (or your Gmail if you have no domain — Brevo must have that sender verified: **Senders & IP → Add a sender**) |

4. [ ] Save → Render redeploys automatically.
5. [ ] **Test it**: you'll do this in Step 4 when you register the demo accounts — the OTP
       must arrive in your inbox.

---

## Step 3 — Keep the API awake (5 min)

Render's free instance sleeps after 15 min idle and takes ~50 s to wake. A reviewer who
sees a spinner for 50 seconds rejects the app.

Pick one:
- [ ] **Free:** uptimerobot.com → New Monitor → HTTP(s) → URL `https://<url>/health` →
      interval 5 min. Done.
- [ ] **$7/mo (better):** Render → service → **Settings → Instance type → Starter**.
      Do this at least the day before you submit to either store.

---

## Step 4 — Lock down admin + create the reviewer's demo accounts (30 min)

Do this in the app itself once you have an Android build (Step 5), **or** on the web
build if you run one locally. Order matters.

1. [ ] Log in as admin: `admin@fitness.local` / `admin1234` → **change this password
       immediately** (Settings/Account). Write the new one in `LAUNCH_SECRETS.local.md`.
2. [ ] Register a **coach**: `review.coach@coachlyjo.com` (use an email you can read
       — the OTP arrives there; e.g. a Gmail alias `yourname+coach@gmail.com`).
       Admin → **Approvals** → approve the coach.
3. [ ] Log in as the coach → **Availability** → set hours for the next 7 days.
4. [ ] Register a **member**: `review.member@coachlyjo.com` (again an alias you can read).
5. [ ] As the member → request a package with that coach → upload any image as
       "proof of payment".
6. [ ] As admin → **activate** that package.
7. [ ] As the member → **book one session**. As the coach → **accept** it.
8. [ ] Write all three logins in `LAUNCH_SECRETS.local.md` — they go in both stores'
       review notes.

**Check:** logging in as the member shows an active package + an upcoming session.

---

## Step 5 — Codemagic: build both apps in the cloud (45 min first time)

### 5a. Account + repo
1. [ ] **codemagic.io** → sign up **with GitHub** → **Add application** → GitHub →
       `sama-arr/CoachlyJo` → project type **Flutter App**.
2. [ ] It detects `codemagic.yaml`. Leave it on "codemagic.yaml" mode (not Workflow Editor).

### 5b. Android upload keystore  ⚠️ most important 5 minutes of this whole document
1. [ ] Codemagic → **Teams → (your team) → Code signing identities → Android keystores →
       Generate keystore**.
   - Reference name: `coachlyjo_upload`  (must match `codemagic.yaml` exactly)
   - Key alias: `upload`
   - Passwords: generate strong ones; write both in `LAUNCH_SECRETS.local.md`
2. [ ] **Download the `.jks` file.** Save it in **two places** (e.g. Google Drive + a USB
       stick). Also write the passwords next to it.
   **If this file is lost, you can never publish an update to CoachlyJo — ever. You'd
   have to create a new app listing and lose all users/reviews.**

### 5c. Google Play service account (lets Codemagic upload builds)
1. [ ] Play Console → **Setup → API access** → link/create a Google Cloud project.
2. [ ] **Create new service account** → follows link to Google Cloud → name `codemagic` →
       role **Service Account User** → Done → click the account → **Keys → Add key →
       JSON** → downloads a `.json` file.
3. [ ] Back in Play Console → API access → the account appears → **Grant access** →
       permissions: **Release manager** (or: Release to production, View app info) → Invite.
4. [ ] Codemagic → **Teams → Environment variables** → group name `coachlyjo` →
       variable `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` → paste the **entire contents** of
       the JSON file → tick **Secure** → Add.

### 5d. App Store Connect API key (lets Codemagic sign + upload iOS)
1. [ ] **appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect
       API → Team Keys → +** → name `Codemagic`, access **App Manager** → Generate.
2. [ ] Note the **Issuer ID** (top of page) and **Key ID**; **download the `.p8`**
       (you can only download it once — also back it up).
3. [ ] Codemagic → **Teams → Code signing identities → iOS → App Store Connect API keys →
       Add key** → name **`CoachlyJo ASC key`** (must match `codemagic.yaml` exactly) →
       Issuer ID, Key ID, upload `.p8` → Save.
4. [ ] Apple Developer portal → **Certificates, IDs & Profiles → Identifiers → +** →
       App IDs → App → Bundle ID **explicit** `com.coachlyjo.app`, description CoachlyJo →
       Register. (Codemagic can auto-create this, but doing it by hand avoids one
       failure mode.)

### 5e. Remaining variables (same `coachlyjo` group)
- [ ] `API_BASE_URL` = your Render URL, **no trailing slash** (e.g.
      `https://coachlyjo-api.onrender.com`). Not secure — it's public anyway.
- [ ] `APP_STORE_APPLE_ID` = leave until Step 7.1 creates the app record; then paste
      the numeric **Apple ID** from App Store Connect → App Information.

### 5f. First Android build
1. [ ] Codemagic → app → **Start new build** → workflow `android-release` → branch
       `main` → Start. ~10 min.
2. [ ] Green? Download `app-release.aab` from the build's **Artifacts**.
       (The Google Play publish step will **fail on this first build** with
       "package not found" — expected; Google requires the first upload to be manual.
       Ignore it this once.)
3. [ ] Red? Copy the failing step's log and paste it to me.

### 5g. First iOS build
1. [ ] **Start new build** → `ios-release` → `main`. ~20 min.
2. [ ] Green → the build appears in **App Store Connect → TestFlight** after ~15 min of
       Apple processing. (Requires Step 7.1 done first — the app record must exist.)
3. [ ] Red → paste me the log. Common first-time failures are signing-related and are
       fixed in the Codemagic UI, not in code.

### Future builds
Tell me "new build" and I bump the version, commit, tag `v1.0.1` etc. — the tag triggers
both workflows automatically. Every build gets a unique build number from Codemagic.

---

## Step 6 — Google Play (do the upload FIRST, then the listing)

### 6a. Create the app + start the clock (do this the same day as 5f)
1. [ ] **play.google.com/console → Create app**: name **CoachlyJo**, default language
       **English (United States)** (Arabic listing is added later), **App**, **Free**,
       accept declarations.
2. [ ] **Testing → Closed testing → Create new release** → upload `app-release.aab`
       → release name `1.0.0 (1)` → Next → Save.
3. [ ] **Testers tab → Create email list** → paste your testers' Gmail addresses → Save
       → select the list for the track → **Start rollout to Closed testing**.
4. [ ] Copy the **opt-in URL** → send to every tester with:
   > "Tap this link, press *Become a tester*, then install CoachlyJo from the Play Store.
   > Open it a few times over the next two weeks and don't leave the test until I say —
   > Google requires it before the app can go public. Tell me anything that looks broken."
5. [ ] **The 14-day clock starts when 12 have opted in.** Check the count every few days
       on the Closed testing page.

### 6b. Fill in the rest while the clock runs (1–2 h)
- [ ] **Main store listing** (Grow → Store presence → Main store listing):
  - App name: `CoachlyJo`
  - Short description (≤80): *Book verified 1-on-1 fitness coaches in Jordan — in person or over Zoom.*
  - Full description (≤4000): what it is, who the coaches are, how packages work
    (prepaid sessions, bank transfer + admin confirmation), Arabic support. Write it
    like a customer would read it. I can draft it — just ask.
  - App icon: `branding/generated/play-icon-512.png`
  - Feature graphic: `branding/generated/feature-graphic-1024x500.png`
  - Phone screenshots: **2–8**, take them on a real Android phone from the tester build
    (login, member home, coach list, booking, session view). Any modern phone's
    screenshots are the right size.
- [ ] **App content** (left menu, bottom) — go through every item:
  - **Privacy policy**: `https://<render-url>/privacy`
  - **Ads**: No
  - **App access**: *All or some functionality is restricted* → add instructions +
    the demo member login (from Step 4). Reviewers use this.
  - **Content rating**: fill questionnaire → category *Health & Fitness* app → no
    violence etc. → you get "Everyone" or similar.
  - **Target audience**: **18 and over** only. Do **not** tick any under-18 group
    (that triggers Google's Families policy and a far harder review).
  - **News app**: No. **COVID**: No. **Government app**: No. **Financial features**: No.
  - **Data safety** (answer honestly; matches what the app actually does):
    - Collects data: **Yes** · Encrypted in transit: **Yes** · Deletion request: **Yes**,
      URL `https://<render-url>/delete-account`; also tick that in-app deletion exists.
    - Personal info: **Name, Email, Phone number, Address** (area) — collected, required,
      purpose *App functionality / Account management*, not shared.
    - Photos and videos: **Photos** — collected, optional (payment proof), *App functionality*.
    - Health and fitness: **Health info / Fitness info** — collected (questionnaire),
      *App functionality*.
    - App activity / Device IDs: **No**.
- [ ] **Store settings**: category **Health & Fitness**; contact email (public).
- [ ] Optional: add an **Arabic** translation of the listing (Store listing → Add
      translation → Arabic).

### 6c. Day 14+
1. [ ] Dashboard → **Apply for production access** → answer honestly (how many testers,
       what feedback, what you fixed). Google replies in ~1–7 days.
2. [ ] Granted → **Production → Create new release** → upload the **same** `.aab` (or a
       newer one) → review → **Start rollout to Production**.
3. [ ] Review is usually < 7 days. You'll get an email.

---

## Step 7 — Apple App Store (start the same week; runs in parallel with the wait)

### 7.1 Create the app record (5 min)
- [ ] **App Store Connect → My Apps → + → New App**: iOS, name **CoachlyJo**, primary
      language English (U.S.), bundle ID **com.coachlyjo.app** (from Step 5d.4), SKU
      `coachlyjo-001`, full access.
- [ ] **App Information** → copy the numeric **Apple ID** → put it in Codemagic's
      `APP_STORE_APPLE_ID` variable (Step 5e).
- [ ] Now run the `ios-release` build (Step 5g) if you haven't.

### 7.2 TestFlight (30 min)
- [ ] App Store Connect → **TestFlight** → the build shows "Processing", then ready.
- [ ] If asked about **Export Compliance** → the app already declares it uses only
      standard HTTPS (`ITSAppUsesNonExemptEncryption=false`), so it shouldn't ask.
- [ ] **Internal Testing → +** group "Team" → add yourself → install the **TestFlight**
      app on your iPhone → install CoachlyJo → **register, get OTP email, log in, book a
      session.** If anything fails here, it fails in review — tell me.

### 7.3 Listing (1 h)
- [ ] **App Store → iOS App → 1.0 Prepare for Submission**:
  - Screenshots: **6.7" display** (iPhone 15 Pro Max / 14 Pro Max etc.) is required;
    Apple reuses it for smaller sizes. Take them from your iPhone via TestFlight, or
    ask me and I'll generate framed ones from Android screenshots.
  - Promotional text / Description / Keywords (e.g. `fitness,coach,personal trainer,
    Jordan,Amman,workout,gym,مدرب,لياقة`) / Support URL (any page — your Render
    `/terms` works, or a website) / Marketing URL optional.
  - **Build**: select the TestFlight build.
  - **App Review Information**: sign-in required **Yes** → demo member login from
    Step 4 → contact phone + email → **Notes**: paste the block from
    `COACHLYJO_LAUNCH_GUIDE.md` §5.5 with your real logins and Render URL filled in.
    That block explains the outside-the-app bank-transfer payment under Guideline
    3.1.3(d) — this is the #1 reason fitness-coaching apps get rejected; the note is
    what prevents it.
  - Version release: **Manually release** (so you control the go-live day).
- [ ] **App Information**: category **Health & Fitness**; secondary optional; Content
      rights: no third-party content; **Age rating** questionnaire → typically 4+ or 12+.
- [ ] **App Privacy** → Get started:
  - Collects data: **Yes**. Types: **Contact Info** (Name, Email, Phone, Physical
    Address), **Health & Fitness** (Health, Fitness), **Photos or Videos** (Photos),
    **User Content** (Other — questionnaire answers), **Identifiers** (User ID).
  - For each: *Linked to the user* **Yes**, *Used for tracking* **No**, purpose
    **App Functionality**.
  - Privacy policy URL: `https://<render-url>/privacy`.
- [ ] **Pricing and Availability**: Free, all countries (or Jordan + wherever you want).

### 7.4 Submit
- [ ] **Add for Review → Submit**. Typical review 24–72 h. Watch email.
- [ ] Approved → **Release this version**.
- [ ] Rejected → they tell you the guideline number. Paste the message to me; most
      first rejections are a one-line answer in Resolution Center, not a new build.

---

## Step 8 — After you're live

- [ ] Change the seeded admin password if you somehow skipped Step 4.1.
- [ ] Turn on Render **Starter** ($7) if you used UptimeRobot — real users notice the
      cold start.
- [ ] Neon dashboard → check storage monthly (payment-proof images are stored in the DB).
- [ ] Apple Developer membership on **auto-renew** — if it lapses the app is pulled.
- [ ] Have a Jordanian lawyer read `/privacy` and `/terms` (editable in Admin → Setup
      without a new app release).
- [ ] Android updates never need the 12-tester test again — only this first release.

---

## Quick reference

| Item | Value |
|---|---|
| Bundle ID / package | `com.coachlyjo.app` |
| Apple SKU | `coachlyjo-001` |
| App name | CoachlyJo |
| Category | Health & Fitness |
| Codemagic keystore reference | `coachlyjo_upload` (alias `upload`) |
| Codemagic ASC key name | `CoachlyJo ASC key` |
| Codemagic env group | `coachlyjo` |
| Play icon | `branding/generated/play-icon-512.png` |
| Feature graphic | `branding/generated/feature-graphic-1024x500.png` |
| Privacy / Terms / Delete URLs | `https://<render-url>/privacy` · `/terms` · `/delete-account` |
| Reviewer notes text | `COACHLYJO_LAUNCH_GUIDE.md` → Phase 5.5 |
| Secrets & logins | `LAUNCH_SECRETS.local.md` (gitignored) |

**When to ping me:** Render URL is live (I'll double-check it), any red Codemagic build,
any store rejection message, "write the description", "new build", or "screenshots".
