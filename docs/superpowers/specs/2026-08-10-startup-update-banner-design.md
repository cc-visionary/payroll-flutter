# Startup update notification

Date: 2026-08-10
Status: approved design

## Problem

The app can already check for updates, but almost nobody ever triggers a check.
`UpdateService.check()` runs only when a user opens Settings → About and presses
the button. Nothing calls it at launch. In practice people sit on stale builds
until someone tells them out of band.

Worse, `/settings/*` redirects non-admins to `/dashboard`
(`lib/app/router.dart:93`), so the one screen that can report an update is
unreachable for most of the people running the app.

## Scope

In scope: check for an update once at launch, and tell the user with a
dismissible banner that can start the update itself.

Out of scope: changing how updates are fetched or installed, the `version.json`
manifest format, silent background installation, and any change to the admin
redirect in `router.dart`.

## What already exists

Most of this feature is built. `lib/features/settings/about/update_service.dart`
(416 lines) already:

- detects the install channel per platform (`UpdateChannel`);
- fetches and parses the hosted `version.json` manifest, including
  `releaseNotes`;
- compares versions (`_isNewer`, currently private);
- returns a sealed `UpdateUpToDate | UpdateAvailable | UpdateError`;
- launches the update — store link, download-and-run installer, or browser.

`about_settings_screen.dart` already renders a full update dialog with release
notes and a launch button.

There is no token, no private repository, no asset selection and no redirect
handling to deal with — the manifest is fetched from a public URL. **The only
thing missing is that nothing calls `check()` at startup, and nothing surfaces
the result outside Settings.**

## Approach

A `MaterialBanner` in the app shell, raised once per launch when a check finds a
newer version, dismissible per version.

A banner and not a modal or a snackbar. A modal interrupts every launch until
acted on. A snackbar times out, and a startup notification is precisely the one
a user is most likely to miss, because launch is when they look away. The banner
takes no focus and it waits.

**The banner carries its own action rather than pointing at Settings.** This is
the load-bearing decision. `/settings/*` is admin-only, so a banner whose action
navigated there would bounce the majority of users straight back to the
dashboard. Instead the existing `_showUpdateDialog` is extracted from
`about_settings_screen.dart` into a shared `showUpdateDialog(...)`, called by
both the About tab and the banner. Every user can update, the admin redirect is
untouched, and there is still only one rendering of the update UI.

Rejected: *exempting `/settings/about` from the admin redirect.* It reaches the
same goal but widens an auth-relevant redirect and drops non-admins into a
Settings shell they cannot otherwise use.

Rejected: *showing the banner to admins only.* Smallest change, but it abandons
the goal — ordinary employees keep running stale builds.

## Components

### Extraction

`showUpdateDialog(BuildContext, WidgetRef, UpdateAvailable)` moves out of
`_AboutSettingsScreenState` into
`lib/features/settings/about/update_dialog.dart`. The About tab calls the
extracted function. This lands before anything new is written.

**It is not a pure refactor, and pretending otherwise would hide a real change.**
Today the download progress bar renders *inline in the About card*
(`about_settings_screen.dart:279-287`), driven by `_launching` and `_progress` on
that screen's state. The banner has no card to render into. So the extracted
dialog becomes self-contained: it owns `launchUpdate`, its own progress
indicator, the failure message and the Windows "Installer started" follow-up.

The consequence is deliberate: About's inline progress bar is retired, and
progress is shown in the dialog for both entry points. The alternative — a
callback-based dialog that leaves `_launch` on the About screen — would force a
second progress implementation for the banner, which is exactly the duplication
this extraction exists to prevent. `_checking` and `_status` stay on the About
screen; they belong to its manual check button, which the banner does not use.

### `startupUpdateCheckProvider`

Runs `UpdateService.check()` once per launch, kicked off from the banner's
first build via `FutureProvider`. This does not delay startup: `check()`
yields at its first `await` (fetching `PackageInfo` / the manifest) before
doing any work, so the first frame paints before the check does anything.
**Launch-only** — no polling timer. A user who wants a newer version
restarts, which they must do to install one anyway.

It is separate from the About tab's manual check, which keeps its own state so a
user pressing "Check for updates" still gets an immediate, visible result.

### `dismissedUpdateVersionProvider`

An `AsyncNotifier<String?>` over `shared_preferences`, key
`dismissed_update_version`.

Deliberately **not** the `ThemeModeNotifier` pattern, which returns a default
synchronously and overwrites it once the load resolves. That is right for a
theme and wrong here: a bare `String?` cannot distinguish "nothing dismissed"
from "not loaded yet", so the banner would render on the first frame and vanish
when the read landed. `AsyncValue` encodes that distinction for free, and the
predicate treats unloaded as suppress — the banner fades in once rather than
flickering out.

### `shouldShowUpdateBanner(…)`

A pure predicate, so the gates are a table test rather than five widget tests:

```dart
bool shouldShowUpdateBanner({
  required UpdateCheckResult? result,   // null until the launch check completes
  required AsyncValue<String?> dismissedVersion,
  required UpdateChannel channel,
})
```

Shows only when all hold:

| Gate | Why |
|---|---|
| `channel` is `windowsInstaller`, `macosDirect`, `linuxDirect` or `sideloadAndroid` | The channels where the app itself must deliver the update |
| `result is UpdateAvailable` | Nothing to announce otherwise |
| `manifest.assetFor(channel) != null` | **Load-bearing.** The live manifest ships `windows` and `android` only. Without this gate a macOS or Linux build would raise a banner leading to a dialog with nothing to download |
| Dismissal has loaded | Otherwise the banner flashes and disappears |
| `UpdateService.isNewer(manifest.version, dismissed)` | Per-version dismissal |

App Store and Play Store are excluded: the OS already notifies and auto-updates,
and a store listing may not have propagated the new build yet. Web is excluded —
a reload gets the new build.

`_isNewer` is promoted to a public static `isNewer`. It is already the correct
comparison; only its visibility changes. Comparing with `isNewer` rather than
string inequality means a rolled-back manifest cannot resurrect a version the
user already declined.

### `UpdateBanner`

A `ConsumerWidget` in `lib/widgets/update_banner.dart` returning a
`MaterialBanner` or `SizedBox.shrink()`, mounted declaratively in
`lib/app/shell.dart`. Declarative rather than
`ScaffoldMessenger.showMaterialBanner`: an imperative show/hide races with
Riverpod rebuilds, and a widget that merely returns a banner is directly
testable.

```
┌──────────────────────────────────────────────────────────┐
│ ⬆  Update available — 1.0.1 (you're on 1.0.0)            │
│                              [ Later ]  [ Update ]       │
├──────────────────────────────────────────────────────────┤
│   Dashboard …                                            │
```

**Later** persists the version and hides the banner. It returns only for a newer
one. A failed write leaves the banner up rather than reporting a dismissal that
did not persist.

**Update** opens the shared dialog, which already shows release notes and owns
download and launch.

Because the banner lives in the shell, it cannot appear over the login screen or
the forced password-change flow.

Styling follows `PRODUCT.md`: theme tokens, the single Luxium purple CTA, 6px
radius. No new accent colour.

## Failure and edge cases

| Case | Behaviour |
|---|---|
| Check fails (offline, malformed manifest, HTTP error) | No banner. `UpdateError` is surfaced only by the About tab's manual check |
| No release published yet (404) | `UpdateService` already maps this to `UpToDate`; no banner |
| Dismissed 1.0.1, then 1.0.2 published | Banner returns at the next launch |
| Dismissed 1.0.1, manifest reverts to 1.0.0 | Silent — `isNewer` rejects it |
| `shared_preferences` read fails | The `AsyncValue` settles in its error state, which the predicate treats as loaded-with-no-dismissal — the banner shows. Worst case is one redundant banner, never a swallowed update |
| Dismissal write fails | Banner stays up; no dismissal is recorded |
| Store or web channel | Banner never constructed |
| Channel is desktop but the manifest has no asset for it (macOS, Linux today) | No banner. The About tab still reports the update, so the information is not lost — only the dead-end call to action is |

## Testing

- Table tests for `shouldShowUpdateBanner` across every gate, including the
  not-yet-loaded dismissal and each excluded channel.
- `isNewer` tests for the dismissal comparison, including the rollback case.
- Dismissal round-trip against an in-memory `SharedPreferences`.
- Widget tests for `UpdateBanner`: visible when an update is available, hidden
  after **Later**, hidden on a store channel, and **Update** opening the dialog.
- A test that the About tab still renders release notes through the extracted
  `showUpdateDialog`, guarding the refactor.
- No test performs network I/O; `UpdateService` already takes an injectable
  `http.Client`.
