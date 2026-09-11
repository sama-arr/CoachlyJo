# CoachlyJo — Launch Guide (from v0.13 to live on both stores)

Follow this in order. Each phase ends with a check you can verify before moving on.
Tick the boxes as you go.

**Total cost to launch:** $99 (Apple, yearly) + $25 (Google, once) + $0–14/month hosting.
**Realistic time:** 3–5 weeks, most of it waiting on Google's 14-day test.

---

# PHASE 0 — Start the slow things today (30 minutes)

Three things have waiting periods. Start them before anything else, then come back
and do the real work while they process.

- [ ] **0.1 Create the Google Play account** — play.google.com/console, $25, account
      type **Personal**. Complete identity verification (passport/ID + address).
      *Takes a few days to clear.*
- [ ] **0.2 Create the Apple Developer account** — developer.apple.com/programs/enroll,
      $99/year, entity type **Individual / Sole Proprietor**.
      - Your Apple ID must have **two-factor authentication on**
      - First/last name must be your **legal name exactly as on your passport**
      - Fastest route: the **Apple Developer app on an iPhone** (ID scan, no waiting on email)
      - Physical address required — **P.O. boxes are rejected**
      - *Approval usually 24–48 hours.*
- [ ] **0.3 Line up a Mac.** You cannot build or upload an iOS app without one.
      Options: your own Mac · borrow one for a day · MacinCloud (~$30/month) ·
      pay a local iOS dev for the build-and-upload step.
- [ ] **0.4 Recruit 15 Android testers** (you need 12, recruit 15 for dropouts).
      Each needs a **Gmail address**. Gym friends, family, the coaches you're
      onboarding. Tell them: *"install an app, open it a few times over two weeks."*

**Check:** both store accounts submitted, tester list of 15 Gmail addresses written down.

---

# PHASE 1 — Put the backend online (2–3 hours)

The app is a client; it does nothing without the server. This phase is mandatory.

## 1.1 Database (free)

- [ ] Sign up at **neon.tech** → create a project named `coachlyjo`
- [ ] Copy the connection details it gives you: host, database, user, password
- [ ] Keep them somewhere safe — you'll paste them in step 1.3

## 1.2 Put the code on GitHub

- [ ] Create a **private** repository named `coachlyjo`
- [ ] Push the contents of the `coachlyjo-v0.13` folder to it:

```bash
cd coachlyjo-v0.13
git init
git add .
git commit -m "CoachlyJo v0.13"
git branch -M main
git remote add origin https://github.com/<your-username>/coachlyjo.git
git push -u origin main
```

> `node_modules` is already excluded by `.gitignore`. Never commit a real `.env`.

## 1.3 Deploy the API (free tier)

- [ ] Sign up at **render.com** → **New → Web Service** → connect the GitHub repo
- [ ] Settings:
      - **Root Directory:** `backend`
      - **Build Command:** `npm ci`
      - **Start Command:** `node src/server_v0_13.js`
      - **Instance type:** Free (upgrade to $7 before review — see 1.6)
- [ ] Add these **Environment Variables**:

| Key | Value |
|---|---|
| `NODE_ENV` | `production` |
| `JWT_SECRET` | run `openssl rand -base64 48` and paste the result |
| `OTP_DEV_MODE` | `false` |
| `PGHOST` | from Neon |
| `PGDATABASE` | from Neon |
| `PGUSER` | from Neon |
| `PGPASSWORD` | from Neon |
| `PGPORT` | `5432` |
| `PGSSLMODE` | `require` |

> The server **refuses to start** if `NODE_ENV=production` while `OTP_DEV_MODE=true`
> or `JWT_SECRET` is the default. That guard exists so you can't accidentally ship
> a build that hands out verification codes.

- [ ] Deploy. Render gives you a URL like `https://coachlyjo-api.onrender.com`.
      **Write it down — this is your API base URL.**

## 1.4 Create the database tables

In Render → your service → **Shell**:

```bash
npm run migrate
npm run seed
```

- [ ] Open `https://<your-render-url>/health/schema` — it must show
      `{"current":13,"expected":13,"upToDate":true}`

## 1.5 Verify the three public pages load

- [ ] `https://<your-render-url>/privacy` — shows the privacy policy
- [ ] `https://<your-render-url>/terms` — shows the terms
- [ ] `https://<your-render-url>/delete-account` — shows the deletion form

**These three URLs are what you paste into the store forms later.** No domain needed.

## 1.6 Stop the free instance from sleeping

Free Render services sleep after ~15 minutes idle and take 30–60 seconds to wake.
A reviewer who hits a 60-second spinner rejects the app.

Pick one:
- [ ] **Free:** sign up at **uptimerobot.com**, add an HTTP monitor for
      `https://<your-render-url>/health` every 5 minutes, **or**
- [ ] **Safer ($7):** upgrade the Render instance to Starter for the review month

> Also add a Neon paid plan or at least check your storage: payment proofs and coach
> documents are stored as images in the database.

## 1.7 Email and Zoom (do not skip email)

A reviewer *will* test "forgot password". Without SMTP nothing arrives.

- [ ] Sign up at **brevo.com** (free, 300 emails/day) → get SMTP credentials
- [ ] Add to Render env vars: `SMTP_HOST`, `SMTP_PORT` (587), `SMTP_USER`,
      `SMTP_PASS`, `SMTP_FROM` (e.g. `CoachlyJo <no-reply@yourmail.com>`)
- [ ] Zoom (optional for launch): marketplace.zoom.us → Develop → Build App →
      **Server-to-Server OAuth** → scope `meeting:write:admin` → add
      `ZOOM_ACCOUNT_ID`, `ZOOM_CLIENT_ID`, `ZOOM_CLIENT_SECRET`
      *Without these, online sessions get placeholder links that say "invalid meeting ID".
      Not a rejection risk on its own, but a reviewer may notice. Add them if you can.*

**Check:** health URL green, three public pages load, a password-reset email arrives.

---

# PHASE 2 — Prepare the app for the stores (2 hours, on the Mac for iOS parts)

## 2.1 Generate the native project folders

The repo ships Flutter code only. Create the platform folders once:

```bash
cd coachlyjo-v0.13/frontend
flutter create --platforms=android,ios --org com.coachlyjo .
flutter pub get
flutter analyze          # must come back clean
```

## 2.2 Set the app name and icon

- [ ] **Android:** `android/app/src/main/AndroidManifest.xml` → `android:label="CoachlyJo"`
- [ ] **iOS:** `ios/Runner/Info.plist` → `CFBundleDisplayName` = `CoachlyJo`
- [ ] Icon — add to `pubspec.yaml` dev_dependencies:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.1

flutter_launcher_icons:
  android: true
  ios: true
  image_path: "../branding/coachlyjo-icon-1024.png"
```
```bash
flutter pub get
dart run flutter_launcher_icons
```

## 2.3 Create the Android signing key — AND BACK IT UP

```bash
keytool -genkey -v -keystore ~/coachlyjo-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties` (never commit this file):

```
storePassword=<what you typed>
keyPassword=<what you typed>
keyAlias=upload
storeFile=/Users/<you>/coachlyjo-upload.jks
```

Wire it into `android/app/build.gradle` (signingConfigs → release), per
[Flutter's signing docs](https://docs.flutter.dev/deployment/android#signing-the-app).

- [ ] **Back up `coachlyjo-upload.jks` and its passwords in two separate places.**
      Lose this file and you can never update the app — you'd have to publish a new
      listing and abandon your users. This is the single most unrecoverable mistake
      in the whole process.

## 2.4 Build with the production API URL

```bash
# Android (this is the .aab Play requires — APKs are not accepted for new apps)
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://<your-render-url>

# iOS (on the Mac)
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://<your-render-url>
```

- [ ] **Never build without `--dart-define`.** The default points at the emulator and
      the app will appear completely broken to a reviewer.
- [ ] Install the release build on a real phone and confirm you can register and log in.

**Check:** app on a physical phone talks to the live server.

---

# PHASE 3 — Create the reviewer's demo accounts (30 minutes)

**This is the step most first submissions get wrong.** A reviewer registers, tries to
buy a package, reaches "transfer to this bank account and upload proof", and stops —
because an admin has to approve the payment. They see a dead end and reject the app
as incomplete or broken.

Log in as admin on the live server and prepare:

- [ ] **3.1** A coach account: register as a coach → approve it in Admin → Approvals →
      log in as that coach → **Availability** tab → set hours for several days so
      bookable sessions exist
- [ ] **3.2** A member account: `review.member@coachlyjo.com` / a simple password
- [ ] **3.3** As that member, request a package with the coach (upload any image as proof)
- [ ] **3.4** As admin, **activate** that package → the member now has classes
- [ ] **3.5** As the member, **book one session** and accept it as the coach, so the
      reviewer sees a live booking, not an empty app
- [ ] **3.6** Write down all three logins (member, coach, admin) — you'll paste them
      into both stores' review notes

**Check:** logging in as the demo member shows an active package and an upcoming session.

---

# PHASE 4 — Google Play (start the 14-day clock as early as possible)

## 4.1 Create the app

- [ ] Play Console → **Create app** → name **CoachlyJo**, language English (add Arabic
      later), type **App**, **Free**

## 4.2 Upload to closed testing FIRST

- [ ] **Testing → Closed testing → Create track** → upload your `.aab`
- [ ] **Testers tab** → create an email list → paste your 15 Gmail addresses
- [ ] Copy the **opt-in link** and send it to all 15 with this message:

> *"Please tap this link, press Become a tester, then install CoachlyJo from the Play
> Store. Open it a few times over the next two weeks and stay a tester until I tell you
> — Google requires it before the app can be published. Tell me anything that looks
> broken."*

- [ ] **The 14-day clock starts when they opt in.** Check the tester count every few
      days; if someone drops out you may need to top up.

## 4.3 Fill in everything else while the clock runs

- [ ] **Store listing:** short description (80 chars), full description (4000),
      screenshots (phone: 2–8 images), 512×512 icon, 1024×500 feature graphic
- [ ] **App content → Privacy policy:** `https://<your-render-url>/privacy`
- [ ] **App content → Data safety** — declare honestly:
      - Personal info: name, email address, phone number, address (area)
      - Photos: yes (payment proof screenshots)
      - Health and fitness: yes (the questionnaire asks about injuries and goals)
      - Encrypted in transit: **yes**
      - Users can request data deletion: **yes**
      - **Account deletion URL:** `https://<your-render-url>/delete-account`
      - Also tick that in-app deletion exists (Settings → Delete account)
- [ ] **App content → Ads:** No
- [ ] **Content rating** questionnaire → Health & Fitness category
- [ ] **Target audience:** 18+ (or 16+) — do **not** select a children's audience;
      that triggers the Families policy and far stricter review

## 4.4 After 14 days

- [ ] Dashboard → **Apply for production access** → answer the questions about how
      you tested, what feedback you got, and what you changed
- [ ] Once granted: **Production → Create release** → upload the same `.aab` → submit
- [ ] Review is usually under 7 days but can take longer

---

# PHASE 5 — Apple App Store

## 5.1 Create the app record

- [ ] appstoreconnect.apple.com → **My Apps → +** → New App
      - Platform iOS, name **CoachlyJo**, language English, bundle ID `com.coachlyjo.app`,
        SKU `coachlyjo-001`

## 5.2 Upload the build

- [ ] From the Mac: `flutter build ipa --release --dart-define=API_BASE_URL=https://<your-render-url>`
- [ ] Upload `build/ios/ipa/*.ipa` with **Transporter** (free on the Mac App Store)
- [ ] Wait ~15 minutes for processing, then check it appears in **TestFlight**
- [ ] Install via TestFlight on your own iPhone and test the full flow

## 5.3 App Privacy (App Store Connect → App Privacy)

Declare the same as Play: name, email, phone, photos, health & fitness data.
Mark everything **"Linked to the user"** and **not used for tracking**.

- [ ] Privacy policy URL: `https://<your-render-url>/privacy`

## 5.4 Listing

- [ ] Screenshots for **6.7"** and **6.5"** iPhones (required sizes)
- [ ] Description, keywords, support URL, marketing URL (optional)
- [ ] Age rating questionnaire
- [ ] Category: Health & Fitness

## 5.5 Review notes — paste this

```
CoachlyJo connects members with verified one-to-one fitness coaches in Amman, Jordan.

TEST ACCOUNTS
Member: review.member@coachlyjo.com / <password>
  This account already has an active package and an upcoming session.
Coach:  review.coach@coachlyjo.com / <password>
Admin:  <admin email> / <password>

HOW PAYMENT WORKS (please read)
Packages are prepaid ONE-TO-ONE personal training sessions delivered by a human
coach, either in person in Amman or live over Zoom. Payment is made by bank
transfer outside the app; the member uploads proof of the transfer and an
administrator confirms it before the sessions become bookable. Under App Review
Guideline 3.1.3(d) Person-to-Person Experiences, real-time one-to-one services of
this kind may use purchase methods other than in-app purchase. The app offers no
digital content, no group classes and no subscriptions.

To see the booking flow without waiting for payment approval, use the member
account above, which is already funded.

ACCOUNT DELETION
Settings → Delete account removes the account and personal data in-app.
A web route is also available at https://<your-render-url>/delete-account
```

- [ ] Submit for review (typically 1–3 days)

---

# PHASE 6 — The rejections to expect, and why you're already covered

| Likely rejection | Status |
|---|---|
| App can't connect / blank screen | Fixed by Phase 1 + building with `--dart-define` |
| Reviewer stuck at payment, "app is incomplete" | Fixed by Phase 3 demo accounts + review notes |
| 3.1.1 — must use in-app purchase | Covered by the 3.1.3(d) wording in the review notes |
| No way to delete the account | Built in v0.13 — in-app **and** web |
| Privacy policy missing or broken link | Served live at `/privacy` |
| Data safety form incomplete/inaccurate | Phase 4.3 — declare health data and photos honestly |
| Login sends credentials over http | Render gives HTTPS automatically |
| Password reset doesn't work | Fixed by SMTP in 1.7 |
| Slow/unresponsive on first open | Fixed by 1.6 (pinger or paid instance) |
| Placeholder "invalid meeting ID" Zoom links | Add Zoom credentials in 1.7 |

**Two things to say honestly if asked:** the app collects health-related information
(the fitness questionnaire) — declare it; and payment happens outside the app —
explain it rather than hiding it. Reviewers reject surprises, not honest flows.

---

# PHASE 7 — After you're live

- [ ] Change the seeded admin password if you haven't
- [ ] Check Neon storage monthly (payment proofs are images in the database)
- [ ] Confirm backups are actually on
- [ ] Keep the Apple membership on auto-renew — if it lapses, your app is pulled
      within 24 hours
- [ ] Have a Jordanian lawyer review the privacy policy and terms
      (Admin → Setup → Home & rules lets you edit both, in English and Arabic,
      without a new app release)
- [ ] Android updates never need the 12-tester test again — only this first release

---

## If you get stuck

Send me: the phase number, what you did, and the exact error or rejection message.
Rejection messages quote a guideline number — that number tells us precisely what to fix.
