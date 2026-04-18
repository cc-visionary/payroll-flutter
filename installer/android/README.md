# Android release (Google Play)

App ID: `ph.luxium.payroll`
Distribution: **Google Play Console** (production, internal testing, closed/open testing).

## One-time setup

### 1. Google Play Console

1. Create the app listing at <https://play.google.com/console/u/0/developers/>.
2. Under **Setup → App integrity → App signing**, let Google manage the upload & app signing keys ("Play App Signing" — recommended). You keep the **upload key** locally; Google holds the final signing key.
3. Fill the required store listing: short description, full description, feature graphic (1024×500), screenshots, privacy policy URL.
4. **Privacy Policy URL is mandatory** — the app handles employee data. Host something at `https://luxium.ph/legal/payroll-privacy` before first upload.

### 2. Upload keystore (locally)

Generate once and **back it up** — you cannot recover it.

```bash
keytool -genkey -v \
  -keystore android/luxium-payroll.keystore \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias luxium-payroll
```

Then copy `android/key.properties.template` → `android/key.properties` and fill the passwords + paths. Both files are already in `.gitignore`.

## Release flow

```bash
# 1. Bump the version
#    pubspec.yaml: version: 1.0.1+2
#    (1.0.1 is the versionName shown to users, +2 is the versionCode;
#     the code MUST strictly increase every upload to Play.)

# 2. Build the AAB (Android App Bundle — required by Play)
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=UPDATE_MANIFEST_URL=https://updates.luxium.ph/payroll/version.json

# 3. Output: build/app/outputs/bundle/release/app-release.aab
#    Upload this file in Play Console → Production → Create new release.
```

### Optional: build an APK for direct sideload

```bash
flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
# Outputs under build/app/outputs/flutter-apk/app-<abi>-release.apk
```

The in-app updater detects `installerStore == 'com.android.vending'` → opens Play; otherwise treats as sideload and opens the direct APK URL from `version.json → stores.android` (if set) or the Play link as fallback.

## Internal testing track

Fastest loop during alpha:

1. Play Console → **Testing → Internal testing → Create new release** → upload the `.aab`.
2. Add testers by email (up to 100). They install via a Play Store link.
3. No review; live within minutes.

## Release checklist

- [ ] `versionCode` increased (strictly greater than last upload)
- [ ] `versionName` matches `pubspec.yaml` version
- [ ] All 3 `--dart-define` flags passed
- [ ] Privacy policy URL live
- [ ] Data safety form filled (Play Console asks about data collection)
- [ ] Screenshots + feature graphic uploaded
- [ ] Release notes written
- [ ] AAB uploaded
- [ ] Review rollout percentage (5% → 20% → 100%)
