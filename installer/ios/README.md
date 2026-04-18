# iOS release (App Store)

Bundle ID: `ph.luxium.payroll`
Display Name: `Luxium Payroll`
Distribution: **App Store Connect** (production + TestFlight).

## One-time setup

### 1. Apple Developer Program

- Enroll at <https://developer.apple.com/programs/> ($99/yr for organizations).
- Create the **App ID** matching `ph.luxium.payroll` under Certificates, IDs & Profiles → Identifiers.

### 2. App Store Connect

- Create the app listing: name "Luxium Payroll", primary language, bundle ID, SKU.
- Fill privacy details, screenshots (6.5" iPhone + 12.9" iPad required), keywords, description.
- Export compliance: `Info.plist` already sets `ITSAppUsesNonExemptEncryption = false` → skips the encryption questionnaire on each upload (we only use HTTPS, which is exempt).

### 3. Signing

Easiest path is **automatic signing**: open `ios/Runner.xcworkspace` in Xcode → Runner → Signing & Capabilities → check **Automatically manage signing** and pick your team. Xcode creates and rotates certs/provisioning profiles in the background.

For CI, switch to manual signing + App Store Connect API Key (documented by [fastlane match](https://docs.fastlane.tools/actions/match/)).

## Release flow

```bash
# 1. Bump the version
#    pubspec.yaml: version: 1.0.1+5
#    The version (1.0.1) shows in the Store; the build number (+5) must
#    strictly increase every TestFlight / App Store upload.

# 2. Build the signed .ipa
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=UPDATE_MANIFEST_URL=https://updates.luxium.ph/payroll/version.json

# 3. Upload via Xcode
open build/ios/archive/Runner.xcarchive
# Xcode → Window → Organizer → select archive → Distribute App → App Store Connect → Upload
```

Or via command line:

```bash
xcrun altool --upload-app -f build/ios/ipa/*.ipa \
  -t ios \
  -u your-appleid@example.com \
  -p <app-specific-password>
```

The app-specific password comes from <https://appleid.apple.com/account/manage> → Sign-In and Security → App-Specific Passwords.

## TestFlight (recommended before public release)

Every `.ipa` you upload lands in App Store Connect → TestFlight automatically. Add internal testers (up to 100 Apple IDs on your team — no review needed, available in minutes) or external testers (up to 10,000, first build needs a short App Review, ~24h).

## App Store review

- First submission: expect 24–48h review. Rejections are most often about unclear demo-account access (payroll apps always need a test login), missing privacy manifests, or broken links in the description.
- Create a **demo account** in the app and put the credentials in App Review → Sign-In Information. Without it, you will be rejected.
- Bake a real **Privacy Nutrition Label** answer in Store listing → Data Collected. Be honest: employee PII, work email, attendance, device identifiers.

## In-app updater behavior on iOS

The app detects `Platform.isIOS` → `UpdateChannel.appStore` → "Check for Updates" opens the Store link from `version.json → stores.ios`. Set it to the App Store URL after the first successful release (you won't have the URL until then — leave the field empty and the button stays disabled for the first build).

## Release checklist

- [ ] `pubspec.yaml` version + build bumped
- [ ] `--dart-define` flags passed (SUPABASE_URL / ANON_KEY / UPDATE_MANIFEST_URL)
- [ ] Bundle ID matches App Store Connect (`ph.luxium.payroll`)
- [ ] Signing team selected in Xcode
- [ ] Archive uploaded to App Store Connect
- [ ] TestFlight build processed and installed on at least one physical device
- [ ] Privacy policy URL live
- [ ] Demo account credentials added to App Review info
- [ ] Screenshots updated if UI changed
- [ ] Release notes written (goes in "What's New" on the Store)
