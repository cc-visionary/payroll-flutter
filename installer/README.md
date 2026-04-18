# Release & distribution

One sub-folder per target platform — each has its own step-by-step guide.

| Platform | Channel | Folder |
|---|---|---|
| Windows | Direct download (website) + in-app updater | [windows/](./windows/README.md) |
| Android | Google Play (production + internal testing) | [android/](./android/README.md) |
| iOS | App Store + TestFlight | [ios/](./ios/README.md) |
| macOS | Mac App Store **or** Developer ID direct download | [macos/](./macos/README.md) |

First-run / new-account setup (bootstrap a new customer, invite employees,
forgot-password flow): [onboarding.md](./onboarding.md).

## Canonical identifiers

Kept consistent across every platform so the same JWT, deep links, and
support infrastructure work everywhere.

| Field | Value |
|---|---|
| Reverse-DNS bundle ID | `ph.luxium.payroll` |
| User-facing name | `Luxium Payroll` |
| macOS bundle `PRODUCT_NAME` | `Luxium Payroll` |
| Android `applicationId` | `ph.luxium.payroll` |
| iOS / macOS `PRODUCT_BUNDLE_IDENTIFIER` | `ph.luxium.payroll` |

## Required build-time defines

Every release build must pass these three `--dart-define` flags. Release
builds without them will fail fast on boot via `Env.assertConfigured` —
this is intentional, it's far better than silently connecting to localhost
and throwing obscure auth errors later.

```
--dart-define=SUPABASE_URL=https://<project>.supabase.co
--dart-define=SUPABASE_ANON_KEY=<anon-key>
--dart-define=UPDATE_MANIFEST_URL=https://updates.luxium.ph/payroll/version.json
```

Debug (`flutter run`) uses local Supabase defaults; no defines required.

## Auto-update flow

The `Settings → About → Check for Updates` button calls `UpdateService`
(`lib/features/settings/about/update_service.dart`). At runtime it:

1. Detects the install channel from the OS + `installerStore` metadata:
   `windowsInstaller`, `macosDirect`, `linuxDirect`, `appStore`, `playStore`,
   `sideloadAndroid`, `web`, or `unknown`.
2. Fetches `version.json` from `UPDATE_MANIFEST_URL`.
3. Semver-compares to the bundled `pubspec.yaml` version.
4. On a newer version, shows a dialog with release notes and routes to:
   - Store link (iOS / Play)
   - Download & Install installer (Windows — actually downloads `.exe` to `%TEMP%` and launches it detached)
   - Browser download (macOS direct / Linux / sideload Android)

See [`version.json.template`](./version.json.template) for the manifest
schema.

## Release cadence rules of thumb

- **Windows (unsigned)**: batch 1–2 weeks. Every new binary resets SmartScreen reputation — frequent tiny releases hurt.
- **Play Store**: start with **internal testing** → roll to production. `versionCode` must strictly increase.
- **App Store**: always ship to **TestFlight** before production. First submission review = 24–48h.
- **Mac App Store**: same as iOS. **Developer ID direct** requires notarization (`xcrun notarytool submit … --wait`) — takes ~5 min.

## Cross-platform functionality notes

Audited 2026-04 before first multi-platform release:

- `dart:io` / `Process.start` calls are guarded so iOS + web builds never reach them. `UpdateService._downloadAndLaunchWindowsInstaller` has a `kIsWeb || !Platform.isWindows` early return as defence-in-depth.
- XLSX disbursement exports auto-detect mobile and swap the native save dialog for the system share sheet via `share_plus`.
- Payslip PDF preview already supports share/print on every platform via the `printing` package.
- Supabase Realtime channels are disposed in every screen's `dispose()`. Mobile OS backgrounding may drop sockets — Supabase SDK handles reconnect automatically on resume.
- `file_picker` uses SAF on Android and `UIDocumentPicker` on iOS — no storage permissions needed in the manifest.
- `flutter_secure_storage` uses Keychain on iOS, Keystore on Android — works out of the box.

Any future contributor adding `Platform.isXxx` / `dart:io` / native processes
should follow the same guard pattern and add a note to the changed
platform's README if it affects Store compliance.
