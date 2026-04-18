# macOS release

Bundle ID: `ph.luxium.payroll`
Display Name: `Luxium Payroll`
Two distribution paths:

1. **Mac App Store** — sandbox + notarization handled by Apple, delivered via Store.
2. **Developer ID + direct download** — notarized `.dmg` you host on the Luxium website. No Store cut, but Gatekeeper quarantine still applies (users right-click → Open on first launch unless notarized).

Pick one per-build — they use the same bundle ID but different signing certs.

## One-time setup

### Apple Developer Program

Same account as iOS ($99/yr). Under Certificates, IDs & Profiles:

- **Apple Distribution** (Mac App Store) — for Store builds.
- **Developer ID Application** + **Developer ID Installer** — for direct distribution.

### App Store Connect (Store path only)

Create a macOS app entry with the same bundle ID `ph.luxium.payroll` (Store treats Mac and iOS as separate SKUs — list both).

### Entitlements already in place

- `macos/Runner/Release.entitlements` sandboxes the app and allows:
  - `network.client` — Supabase / Lark / update manifest fetch
  - `files.user-selected.read-only` — attendance CSV import
  - `files.downloads.read-write` — writing the downloaded update installer to `~/Downloads` or the temp dir

No camera / mic / location entitlements — the app doesn't use them. Keep the permission surface minimal.

## Release flow — Mac App Store

```bash
# 1. Bump pubspec.yaml version + build number.
# 2. Build
flutter build macos --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=UPDATE_MANIFEST_URL=https://updates.luxium.ph/payroll/version.json

# 3. Open Xcode and archive
open macos/Runner.xcworkspace
# Product → Archive → Distribute App → App Store Connect → Upload
```

Automatic signing works fine here too. Same TestFlight flow as iOS: upload → TestFlight → internal testers → promote to production.

## Release flow — Developer ID (direct download)

```bash
# 1. Build unsigned
flutter build macos --release --dart-define=...

# 2. Sign (adjust identity string to match your installed cert)
codesign --deep --force --verbose --sign "Developer ID Application: Luxium Inc. (TEAMID)" \
  --options runtime \
  --entitlements macos/Runner/Release.entitlements \
  build/macos/Build/Products/Release/Luxium\ Payroll.app

# 3. Wrap as .dmg (needs `create-dmg` — brew install create-dmg)
create-dmg \
  --volname "Luxium Payroll" \
  --window-size 520 360 \
  --icon "Luxium Payroll.app" 130 180 \
  --app-drop-link 390 180 \
  dist/LuxiumPayroll-v1.0.1.dmg \
  "build/macos/Build/Products/Release/Luxium Payroll.app"

# 4. Notarize with Apple (takes a few minutes)
xcrun notarytool submit dist/LuxiumPayroll-v1.0.1.dmg \
  --apple-id you@luxium.ph \
  --team-id TEAMID \
  --password <app-specific-password> \
  --wait

# 5. Staple the notarization ticket to the DMG so Gatekeeper can verify offline
xcrun stapler staple dist/LuxiumPayroll-v1.0.1.dmg

# 6. Upload the .dmg to the Luxium website + update version.json
```

App-specific passwords: <https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords.

## In-app updater behavior on macOS

- Store-installed: `installerStore` isn't reliable on macOS, so by default the updater treats every Mac as `UpdateChannel.macosDirect` → opens the `.dmg` download URL in the browser. If you ship via Mac App Store instead, add `stores.macos = "https://apps.apple.com/..."` to `version.json` and change the service to prefer it (TODO in the code, easy tweak).
- Direct-download: user downloads the new `.dmg`, drags the new `.app` into Applications, replaces the old one.

## Release checklist

- [ ] `pubspec.yaml` version + build bumped
- [ ] `--dart-define` flags passed
- [ ] App launches on a clean Mac (no keychain prompts beyond first-run)
- [ ] Sandbox entitlements unchanged (network.client + two file-access keys)
- [ ] For Store: archive uploaded to App Store Connect
- [ ] For Direct: DMG signed + notarized + stapled
- [ ] Upload to Luxium website + `version.json` updated (direct path)
- [ ] Screenshots / release notes ready (Store path)
