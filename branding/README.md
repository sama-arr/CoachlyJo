# CoachlyJo branding assets (v0.6 — suggestion, easy to replace later)

`coachlyjo-icon-1024.png` — app icon suggestion: brand gradient (#F20FB6 → #FF770F)
rounded square with a white "C" ring and a spark dot. The `ic_launcher-*.png`
files are pre-sized Android densities.

## Apply as the launcher icon (when you want it)
Easiest way, from `frontend/`:
1. Add to pubspec.yaml dev_dependencies: `flutter_launcher_icons: ^0.14.1`
2. Add config:
   flutter_launcher_icons:
     android: true
     ios: true
     image_path: "../branding/coachlyjo-icon-1024.png"
3. Run: `dart run flutter_launcher_icons`

Also set the visible app name:
- Android: `android/app/src/main/AndroidManifest.xml` → `android:label="CoachlyJo"`
- iOS: `ios/Runner/Info.plist` → `CFBundleDisplayName` = `CoachlyJo`
(The in-app branding is already CoachlyJo everywhere in v0.6.)

## Generated store assets (`generated/`)
Produced by `python tools/make_store_assets.py` from the 1024 master — re-run after
changing the master icon:
- `icon-ios-1024.png` — opaque (Apple rejects icons with alpha); used via `image_path_ios`
- `adaptive-foreground.png` / `adaptive-background.png` — Android adaptive icon layers
- `play-icon-512.png` — Play Console → Store listing → App icon
- `feature-graphic-1024x500.png` — Play Console → Store listing → Feature graphic
