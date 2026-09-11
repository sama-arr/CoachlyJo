# CoachlyJo branding assets (v0.6 — suggestion, easy to replace later)

`coachly-icon-1024.png` — app icon suggestion: brand gradient (#F20FB6 → #FF770F)
rounded square with a white "C" ring and a spark dot. The `ic_launcher-*.png`
files are pre-sized Android densities.

## Apply as the launcher icon (when you want it)
Easiest way, from `frontend/`:
1. Add to pubspec.yaml dev_dependencies: `flutter_launcher_icons: ^0.14.1`
2. Add config:
   flutter_launcher_icons:
     android: true
     ios: true
     image_path: "../branding/coachly-icon-1024.png"
3. Run: `dart run flutter_launcher_icons`

Also set the visible app name:
- Android: `android/app/src/main/AndroidManifest.xml` → `android:label="CoachlyJo"`
- iOS: `ios/Runner/Info.plist` → `CFBundleDisplayName` = `CoachlyJo`
(The in-app branding is already CoachlyJo everywhere in v0.6.)
