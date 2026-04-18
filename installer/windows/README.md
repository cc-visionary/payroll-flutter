# Windows installer

## Local build

Requires:
- Flutter SDK with Windows desktop support enabled (`flutter config --enable-windows-desktop`).
- [Inno Setup 6+](https://jrsoftware.org/isdl.php) — installs `iscc.exe` in `C:\Program Files (x86)\Inno Setup 6\`.

```powershell
# 1. Build the Flutter Windows release
flutter build windows --release `
  --dart-define=SUPABASE_URL=https://<project>.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=<anon-key>

# 2. Package the installer
& "C:\Program Files (x86)\Inno Setup 6\iscc.exe" `
  /DVersion=0.1.0 `
  installer\windows\payroll_flutter.iss
```

Output: `dist\PayrollFlutter-Setup-v0.1.0.exe`.

## What the installer does

- Installs to `%LocalAppData%\PayrollFlutter` (no admin rights required).
- Creates Start menu + optional desktop/quick-launch shortcuts.
- Registers an uninstaller under Add/Remove Programs.
- Runs the app at the end of setup.

## Silent / unattended

```powershell
PayrollFlutter-Setup-v0.1.0.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

## Wiring the in-app updater

The app has a built-in "Check for Updates" button (Settings → About). At
runtime it fetches a JSON manifest, compares versions, and — on Windows —
downloads the `.exe` installer and launches it.

1. **Pick a hosting location** for the manifest. Any static HTTPS endpoint
   works (Supabase Storage, S3, GitHub Pages, a plain web server).
2. **Copy** `installer/version.json.template` → rename to `version.json`,
   update the `version`, `releaseNotes`, and per-platform `url` fields, and
   upload it alongside the installer binary.
3. **Configure the build** with the manifest URL. Pass
   `--dart-define=UPDATE_MANIFEST_URL=https://<your-host>/version.json` to
   `flutter build` (and to the Inno Setup build step if you script it).
   Without this define the app falls back to `https://updates.luxium.ph/payroll-flutter/version.json`.
4. **Release flow** for each new version:
   ```powershell
   # 1. Build + sign the .exe
   flutter build windows --release `
     --dart-define=SUPABASE_URL=... `
     --dart-define=SUPABASE_ANON_KEY=... `
     --dart-define=UPDATE_MANIFEST_URL=https://<host>/version.json
   & "C:\Program Files (x86)\Inno Setup 6\iscc.exe" /DVersion=1.0.1 installer\windows\payroll_flutter.iss

   # 2. Upload dist\PayrollFlutter-Setup-v1.0.1.exe to the host.
   # 3. Update version.json with the new version + download URL, re-upload.
   ```
5. Inno Setup already handles file-replacement: the in-app flow downloads the
   installer to `%TEMP%`, launches it detached, and prompts the user to close
   the app. When they do, Inno Setup replaces binaries and re-launches.

## Code signing (future)

The installer currently ships **unsigned** — users will see a SmartScreen warning on first launch. When we acquire an OV or EV code-signing cert:

1. Drop the `.pfx` file in GitHub Actions secrets as `WINDOWS_CERT_P12` (base64-encoded) and `WINDOWS_CERT_PASSWORD`.
2. Uncomment `SignTool=signtool` in `payroll_flutter.iss`.
3. In CI, register the `signtool` name with Inno Setup:
   ```powershell
   iscc /Ssigntool="signtool.exe sign /f $env:CERT_FILE /p $env:CERT_PWD /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $f" installer\windows\payroll_flutter.iss
   ```
4. Sign the inner `payroll_flutter.exe` before Inno Setup packages it (recommended) — add a step in the workflow that runs `signtool sign` on `build\windows\x64\runner\Release\payroll_flutter.exe`.
