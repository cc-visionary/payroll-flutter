# Startup Update Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Check for an update once at launch and announce it with a dismissible banner that can start the update itself, so every user — admin or not — stops running stale builds.

**Architecture:** All the update machinery already exists in `lib/features/settings/about/update_service.dart`; nothing calls it at startup and its UI is trapped behind an admin-only route. So this plan adds a launch-time check provider, a per-version dismissal persisted to `shared_preferences`, a pure visibility predicate, and a `MaterialBanner` in the app shell — and extracts the existing update dialog so the banner and the About tab share one rendering of it.

**Tech Stack:** Flutter (Material 3), Riverpod 2 (`NotifierProvider`, `AsyncNotifierProvider`, `FutureProvider`), `shared_preferences`, `package_info_plus`, `http`. No new dependencies.

## Global Constraints

- **No new dependencies.** Everything needed is already in `pubspec.yaml`.
- **Do not modify `lib/app/router.dart`.** The admin redirect at line 93 stays exactly as it is; the banner reaches non-admins by carrying its own action, not by navigating.
- **Design tokens from `PRODUCT.md`.** Use `LuxiumSpacing` constants (already imported across `lib/features/settings/about/`), theme `colorScheme` roles, and the single Luxium purple CTA. Never introduce a cyan/sky-blue accent. 6px radius default.
- **Do not run `dart format`.** This repo has mixed old/new formatter style and is not gated on it. Match the surrounding style of each file you edit.
- **The gate is `flutter analyze`** (must report no new issues) plus `flutter test`.
- **No test may perform network I/O.** `UpdateService` already accepts an injectable `http.Client`; use it.
- **Existing type names are fixed:** `UpdateChannel`, `UpdateManifest`, `PlatformAsset`, `UpdateCheckResult`, `UpdateUpToDate`, `UpdateAvailable`, `UpdateError`, `updateServiceProvider`, `updateChannelProvider`.

---

### Task 1: Promote the version comparison to public API

`UpdateService._isNewer` is private, but the dismissal gate in Task 4 needs it to compare a manifest version against a stored dismissed version. Only its visibility changes.

**Files:**
- Modify: `lib/features/settings/about/update_service.dart` (the `_isNewer` declaration at ~line 292, and its one call site at ~line 265)
- Test: `test/update/is_newer_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `static bool UpdateService.isNewer(String remote, String local)` — true when `remote` is strictly newer. Tolerates `1.0.0`, `1.0`, `1.0.0+5`, `1.0.0-beta`.

- [ ] **Step 1: Write the failing test**

Create `test/update/is_newer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('a higher patch is newer', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
    });

    test('an equal version is not newer', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('a lower version is not newer', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('ignores a build suffix', () {
      expect(UpdateService.isNewer('1.0.0+7', '1.0.0+6'), isFalse);
      expect(UpdateService.isNewer('1.0.1+1', '1.0.0+9'), isTrue);
    });

    test('treats a missing component as zero', () {
      expect(UpdateService.isNewer('1.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewer('1.0', '1.0.0'), isFalse);
    });

    // The dismissal gate depends on this: a manifest that rolls back below a
    // version the user already dismissed must NOT resurrect the banner.
    test('a rolled-back manifest is not newer than the dismissal', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/update/is_newer_test.dart`
Expected: FAIL — compile error, `isNewer` is not defined for `UpdateService` (the member is `_isNewer`).

- [ ] **Step 3: Rename the member**

In `lib/features/settings/about/update_service.dart`, change the declaration:

```dart
  /// Compares semver-ish strings. Handles `1.0.0`, `1.0`, `1.0.0+5`.
  ///
  /// Public because the startup banner's dismissal gate compares a manifest
  /// version against the version the user last dismissed.
  static bool isNewer(String remote, String local) {
```

and update its single call site inside `check()`:

```dart
      if (!isNewer(manifest.version, current)) {
        return UpdateUpToDate(current);
      }
```

Leave the body of the function untouched.

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/update/is_newer_test.dart && flutter analyze`
Expected: all tests PASS; analyzer reports no new issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/about/update_service.dart test/update/is_newer_test.dart
git commit -m "refactor(update): make the version comparison public"
```

---

### Task 2: Extract the update dialog

The dialog currently lives in `_AboutSettingsScreenState` and its launch flow writes progress into the About card. The banner has no card, so the extracted dialog becomes self-contained: it owns the launch, its own progress indicator, the failure message, and the Windows "Installer started" follow-up. About's inline progress bar is retired — this is intended, see the spec.

**Files:**
- Create: `lib/features/settings/about/update_dialog.dart`
- Modify: `lib/features/settings/about/about_settings_screen.dart` (remove `_showUpdateDialog`, `_launch`, the `_launching`/`_progress` fields and the inline progress block at ~lines 279-287; call the extracted function from `_check`)
- Test: `test/update/update_dialog_test.dart` (create)

**Interfaces:**
- Consumes: `UpdateAvailable`, `UpdateChannel`, `updateServiceProvider` from Task 1's file.
- Produces: `Future<void> showUpdateDialog(BuildContext context, WidgetRef ref, UpdateAvailable update)` — shows the dialog and returns when it closes.

- [ ] **Step 1: Write the failing test**

Create `test/update/update_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/update_dialog.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';

UpdateAvailable _available({String? notes}) => UpdateAvailable(
      currentVersion: '1.0.0',
      channel: UpdateChannel.windowsInstaller,
      manifest: UpdateManifest(
        version: '1.0.1',
        releaseNotes: notes,
        platforms: const {
          'windows': PlatformAsset(url: 'https://example.test/Setup.exe'),
        },
        stores: const {},
      ),
    );

Future<void> _pump(WidgetTester tester, UpdateAvailable update) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showUpdateDialog(context, ref, update),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows both versions', (tester) async {
    await _pump(tester, _available());
    expect(find.text('Update available — v1.0.1'), findsOneWidget);
    expect(find.text('Current: v1.0.0'), findsOneWidget);
  });

  testWidgets('renders release notes when present', (tester) async {
    await _pump(tester, _available(notes: 'Faster payroll runs'));
    expect(find.text('Release notes'), findsOneWidget);
    expect(find.text('Faster payroll runs'), findsOneWidget);
  });

  testWidgets('omits the release-notes heading when blank', (tester) async {
    await _pump(tester, _available(notes: '   '));
    expect(find.text('Release notes'), findsNothing);
  });

  testWidgets('Later closes the dialog without launching', (tester) async {
    await _pump(tester, _available());
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available — v1.0.1'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/update/update_dialog_test.dart`
Expected: FAIL — `update_dialog.dart` does not exist.

- [ ] **Step 3: Create the extracted dialog**

Create `lib/features/settings/about/update_dialog.dart`. Move the body of `_showUpdateDialog` across verbatim, then fold the launch flow in as dialog-local state:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/luxium_spacing.dart';
import 'update_service.dart';

/// The one update dialog. Shown from Settings → About and from the startup
/// banner, so both entry points render identical UI and there is only one
/// implementation of download progress.
Future<void> showUpdateDialog(
  BuildContext context,
  WidgetRef ref,
  UpdateAvailable update,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends ConsumerStatefulWidget {
  final UpdateAvailable update;
  const _UpdateDialog({required this.update});

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  bool _launching = false;
  double _progress = 0;
  String? _error;

  UpdateAvailable get _update => widget.update;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channel = _update.channel;
    final asset = _update.manifest.assetFor(channel);
    final storeLink = _update.manifest.storeLinkFor(channel);
    final canLaunch = channel.isStore
        ? (storeLink != null && storeLink.isNotEmpty)
        : (asset != null && asset.url.isNotEmpty);
    final notes = _update.manifest.releaseNotes;
    final hasNotes = notes != null && notes.trim().isNotEmpty;

    return AlertDialog(
      title: Text('Update available — v${_update.manifest.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current: v${_update.currentVersion}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: LuxiumSpacing.sm),
            if (hasNotes) ...[
              Text(
                'Release notes',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: LuxiumSpacing.xs),
              Text(notes, style: theme.textTheme.bodySmall),
              const SizedBox(height: LuxiumSpacing.md),
            ],
            Text(
              'Channel: ${channel.label}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_launching) ...[
              const SizedBox(height: LuxiumSpacing.md),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: LuxiumSpacing.xs),
              Text(
                _progress == 0
                    ? 'Starting…'
                    : 'Downloading installer… ${(_progress * 100).round()}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: LuxiumSpacing.md),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _launching ? null : () => Navigator.pop(context),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: (!canLaunch || _launching) ? null : _launch,
          icon: Icon(
            channel.isStore
                ? Icons.open_in_new
                : channel == UpdateChannel.windowsInstaller
                ? Icons.download
                : Icons.open_in_browser,
            size: 16,
          ),
          label: Text(
            channel.isStore
                ? 'Open Store'
                : channel == UpdateChannel.windowsInstaller
                ? 'Download & Install'
                : 'Download',
          ),
        ),
      ],
    );
  }

  Future<void> _launch() async {
    setState(() {
      _launching = true;
      _progress = 0;
      _error = null;
    });
    final ok = await ref.read(updateServiceProvider).launchUpdate(
          _update,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = p.clamp(0.0, 1.0));
          },
        );
    if (!mounted) return;
    setState(() => _launching = false);
    if (!ok) {
      setState(() => _error = 'Could not launch the update.');
      return;
    }
    Navigator.pop(context);
    if (_update.channel == UpdateChannel.windowsInstaller) {
      // Installer is running detached. Prompt the user to close the app so
      // Inno Setup can replace files.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Installer started'),
          content: const Text(
            'The installer is now running. Close Payroll Flutter when prompted so the update can complete.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    }
  }
}
```

Verify the `luxium_spacing.dart` import path against what `about_settings_screen.dart` already imports and copy it exactly — do not guess.

- [ ] **Step 4: Rewire the About screen**

In `about_settings_screen.dart`:
1. Add `import 'update_dialog.dart';`
2. In `_check`, replace `_showUpdateDialog(result);` with `showUpdateDialog(context, ref, result);`
3. Delete the `_showUpdateDialog` and `_launch` methods entirely.
4. Delete the `_launching` and `_progress` fields.
5. Delete the `if (_launching) ...[ … ]` block from `build` (~lines 279-287).
6. Change the button guard from `(_checking || _launching) ? null : _check` to `_checking ? null : _check`.

Keep `_checking` and `_status` — they belong to the manual check button.

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test test/update/update_dialog_test.dart && flutter analyze`
Expected: 4 tests PASS; analyzer reports no new issues (in particular no unused-field warning for `_launching`/`_progress`).

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/about/update_dialog.dart lib/features/settings/about/about_settings_screen.dart test/update/update_dialog_test.dart
git commit -m "refactor(update): extract the update dialog so the banner can reuse it"
```

---

### Task 3: Persist the dismissed version

**Files:**
- Create: `lib/features/settings/about/dismissed_update_version.dart`
- Test: `test/update/dismissed_update_version_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `final dismissedUpdateVersionProvider = AsyncNotifierProvider<DismissedUpdateVersion, String?>(DismissedUpdateVersion.new)`
  - `Future<void> DismissedUpdateVersion.dismiss(String version)`
  - `const String kDismissedUpdateVersionKey = 'dismissed_update_version'`

- [ ] **Step 1: Write the failing test**

Create `test/update/dismissed_update_version_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/dismissed_update_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts as null when nothing was ever dismissed', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(dismissedUpdateVersionProvider.future), isNull);
  });

  test('reads a previously stored dismissal', () async {
    SharedPreferences.setMockInitialValues({
      kDismissedUpdateVersionKey: '1.0.1',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(dismissedUpdateVersionProvider.future), '1.0.1');
  });

  test('dismiss persists the version and updates the state', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(dismissedUpdateVersionProvider.future);

    await c.read(dismissedUpdateVersionProvider.notifier).dismiss('1.0.2');

    expect(c.read(dismissedUpdateVersionProvider).value, '1.0.2');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDismissedUpdateVersionKey), '1.0.2');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/update/dismissed_update_version_test.dart`
Expected: FAIL — `dismissed_update_version.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/features/settings/about/dismissed_update_version.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kDismissedUpdateVersionKey = 'dismissed_update_version';

/// The app version the user last dismissed the update banner for.
///
/// Deliberately an [AsyncNotifier] rather than the synchronous-default pattern
/// used by `ThemeModeNotifier`. A bare `String?` cannot distinguish "nothing
/// dismissed" from "not loaded yet", so the banner would render on the first
/// frame and vanish once the read landed. `AsyncValue` carries that
/// distinction, and the banner predicate treats unloaded as suppress.
class DismissedUpdateVersion extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kDismissedUpdateVersionKey);
  }

  /// Records [version] as dismissed. On a write failure the state is left
  /// alone, so a dismissal that did not persist is never reported as one that
  /// did — the banner stays up and the user can try again.
  Future<void> dismiss(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kDismissedUpdateVersionKey, version);
    state = AsyncData(version);
  }
}

final dismissedUpdateVersionProvider =
    AsyncNotifierProvider<DismissedUpdateVersion, String?>(
  DismissedUpdateVersion.new,
);
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/update/dismissed_update_version_test.dart && flutter analyze`
Expected: 3 tests PASS; analyzer clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/about/dismissed_update_version.dart test/update/dismissed_update_version_test.dart
git commit -m "feat(update): persist the dismissed update version"
```

---

### Task 4: The visibility predicate

Five gates in a widget's `build` is where bugs hide; five gates in a pure function is a table test.

**Files:**
- Create: `lib/features/settings/about/banner_visibility.dart`
- Test: `test/update/banner_visibility_test.dart` (create)

**Interfaces:**
- Consumes: `UpdateService.isNewer` (Task 1); `UpdateCheckResult`, `UpdateAvailable`, `UpdateChannel`, `UpdateManifest`, `PlatformAsset`.
- Produces: `bool shouldShowUpdateBanner({required UpdateCheckResult? result, required AsyncValue<String?> dismissedVersion})`

Note the channel is **not** a separate parameter — `UpdateAvailable` already carries `channel`, and taking it twice invites the two to disagree.

- [ ] **Step 1: Write the failing test**

Create `test/update/banner_visibility_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/banner_visibility.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';

UpdateAvailable _available({
  UpdateChannel channel = UpdateChannel.windowsInstaller,
  String version = '1.0.1',
  Map<String, PlatformAsset> platforms = const {
    'windows': PlatformAsset(url: 'https://example.test/Setup.exe'),
  },
  Map<String, String> stores = const {},
}) =>
    UpdateAvailable(
      currentVersion: '1.0.0',
      channel: channel,
      manifest: UpdateManifest(
        version: version,
        platforms: platforms,
        stores: stores,
      ),
    );

const _loadedNone = AsyncData<String?>(null);

void main() {
  group('shouldShowUpdateBanner', () {
    test('shows when an update is available on a desktop channel', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(),
          dismissedVersion: _loadedNone,
        ),
        isTrue,
      );
    });

    test('hidden until the launch check completes', () {
      expect(
        shouldShowUpdateBanner(result: null, dismissedVersion: _loadedNone),
        isFalse,
      );
    });

    test('hidden when up to date', () {
      expect(
        shouldShowUpdateBanner(
          result: const UpdateUpToDate('1.0.0'),
          dismissedVersion: _loadedNone,
        ),
        isFalse,
      );
    });

    test('hidden when the check errored', () {
      expect(
        shouldShowUpdateBanner(
          result: const UpdateError('offline'),
          dismissedVersion: _loadedNone,
        ),
        isFalse,
      );
    });

    // The flash-then-vanish bug this whole AsyncValue exists to prevent.
    test('hidden until the stored dismissal has loaded', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(),
          dismissedVersion: const AsyncLoading<String?>(),
        ),
        isFalse,
      );
    });

    test('an errored dismissal read counts as no dismissal', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(),
          dismissedVersion: AsyncError<String?>('boom', StackTrace.empty),
        ),
        isTrue,
      );
    });

    test('hidden for a version the user already dismissed', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(version: '1.0.1'),
          dismissedVersion: const AsyncData<String?>('1.0.1'),
        ),
        isFalse,
      );
    });

    test('shown again for a version newer than the dismissal', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(version: '1.0.2'),
          dismissedVersion: const AsyncData<String?>('1.0.1'),
        ),
        isTrue,
      );
    });

    test('stays hidden when the manifest rolls back below the dismissal', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(version: '1.0.0'),
          dismissedVersion: const AsyncData<String?>('1.0.1'),
        ),
        isFalse,
      );
    });

    test('hidden on store channels — the OS already notifies', () {
      for (final channel in [UpdateChannel.appStore, UpdateChannel.playStore]) {
        expect(
          shouldShowUpdateBanner(
            result: _available(
              channel: channel,
              platforms: const {},
              stores: const {
                'ios': 'https://apps.apple.test/x',
                'android': 'https://play.test/x',
              },
            ),
            dismissedVersion: _loadedNone,
          ),
          isFalse,
          reason: '$channel must not raise a banner',
        );
      }
    });

    test('hidden on web and unknown channels', () {
      for (final channel in [UpdateChannel.web, UpdateChannel.unknown]) {
        expect(
          shouldShowUpdateBanner(
            result: _available(channel: channel),
            dismissedVersion: _loadedNone,
          ),
          isFalse,
          reason: '$channel must not raise a banner',
        );
      }
    });

    // The live manifest ships windows + android only. A macOS or Linux build
    // must not raise a banner leading to a dialog with nothing to download.
    test('hidden on a desktop channel with no asset in the manifest', () {
      for (final channel in [
        UpdateChannel.macosDirect,
        UpdateChannel.linuxDirect,
      ]) {
        expect(
          shouldShowUpdateBanner(
            result: _available(channel: channel),
            dismissedVersion: _loadedNone,
          ),
          isFalse,
          reason: '$channel has no asset in this manifest',
        );
      }
    });

    test('shown on a desktop channel that does have an asset', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(
            channel: UpdateChannel.linuxDirect,
            platforms: const {
              'linux': PlatformAsset(url: 'https://example.test/app.AppImage'),
            },
          ),
          dismissedVersion: _loadedNone,
        ),
        isTrue,
      );
    });

    test('shown for sideloaded Android with an apk', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(
            channel: UpdateChannel.sideloadAndroid,
            platforms: const {
              'android': PlatformAsset(url: 'https://example.test/app.apk'),
            },
          ),
          dismissedVersion: _loadedNone,
        ),
        isTrue,
      );
    });

    test('hidden when the asset url is present but empty', () {
      expect(
        shouldShowUpdateBanner(
          result: _available(
            platforms: const {'windows': PlatformAsset(url: '')},
          ),
          dismissedVersion: _loadedNone,
        ),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/update/banner_visibility_test.dart`
Expected: FAIL — `banner_visibility.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/features/settings/about/banner_visibility.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_service.dart';

/// Channels where the app itself must deliver the update.
///
/// App Store and Play Store are excluded: the OS already notifies and
/// auto-updates, and a store listing may not have propagated the new build
/// yet. Web is excluded — a reload picks up the new bundle.
const Set<UpdateChannel> _bannerChannels = {
  UpdateChannel.windowsInstaller,
  UpdateChannel.macosDirect,
  UpdateChannel.linuxDirect,
  UpdateChannel.sideloadAndroid,
};

/// Whether the startup update banner should be visible.
///
/// Pure so the gates are a table test rather than a pile of widget tests.
/// [result] is null until the launch check completes.
bool shouldShowUpdateBanner({
  required UpdateCheckResult? result,
  required AsyncValue<String?> dismissedVersion,
}) {
  if (result is! UpdateAvailable) return false;
  if (!_bannerChannels.contains(result.channel)) return false;

  // The manifest ships assets per platform and does not cover every channel.
  // Without this the banner would point at a dialog with nothing to download.
  final asset = result.manifest.assetFor(result.channel);
  if (asset == null || asset.url.isEmpty) return false;

  // Unloaded means suppress: showing now and hiding when the read lands would
  // flash the banner. An errored read is treated as "nothing dismissed" — one
  // redundant banner is a better failure than a swallowed update.
  if (dismissedVersion.isLoading) return false;
  final dismissed = dismissedVersion.hasValue ? dismissedVersion.value : null;
  if (dismissed == null) return true;

  // isNewer, not `!=`, so a rolled-back manifest cannot resurrect a version
  // the user already declined.
  return UpdateService.isNewer(result.manifest.version, dismissed);
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/update/banner_visibility_test.dart && flutter analyze`
Expected: all tests PASS; analyzer clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/about/banner_visibility.dart test/update/banner_visibility_test.dart
git commit -m "feat(update): add the startup banner visibility predicate"
```

---

### Task 5: The launch-time check

**Files:**
- Create: `lib/features/settings/about/startup_update_check.dart`
- Test: `test/update/startup_update_check_test.dart` (create)

**Interfaces:**
- Consumes: `updateServiceProvider`, `UpdateCheckResult`.
- Produces: `final startupUpdateCheckProvider = FutureProvider<UpdateCheckResult?>(...)`

Launch-only by design: no polling timer. A user who wants a newer version restarts the app, which they must do to install one anyway. It is separate from the About tab's manual check so that pressing "Check for Updates" still gives an immediate, visible result.

- [ ] **Step 1: Write the failing test**

Create `test/update/startup_update_check_test.dart`.

Note this drives the **real** `UpdateService` through an injected `MockClient`
rather than a hand-written fake: `UpdateService` has a final `manifestUrl`
field, so `implements UpdateService` would not compile without reimplementing
it, and the real service is what we actually want under test.

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:payroll_flutter/features/settings/about/startup_update_check.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Payroll',
      packageName: 'ph.luxium.payroll',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  UpdateService serving(String body, {int status = 200}) => UpdateService(
        httpClient: MockClient((_) async => http.Response(body, status)),
        manifestUrl: 'https://example.test/version.json',
      );

  ProviderContainer containerFor(UpdateService service) {
    final c = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('surfaces an available update from the manifest', () async {
    final c = containerFor(serving(jsonEncode({
      'version': '1.0.1',
      'platforms': {
        'linux': {'url': 'https://example.test/app.AppImage'},
        'windows': {'url': 'https://example.test/Setup.exe'},
      },
    })));

    expect(
      await c.read(startupUpdateCheckProvider.future),
      isA<UpdateAvailable>(),
    );
  });

  test('reports up to date when the manifest matches the running build',
      () async {
    final c = containerFor(
      serving(jsonEncode({'version': '1.0.0', 'platforms': {}})),
    );

    expect(
      await c.read(startupUpdateCheckProvider.future),
      isA<UpdateUpToDate>(),
    );
  });

  test('a malformed manifest resolves to an error result, never a throw',
      () async {
    final c = containerFor(serving('not json at all'));

    expect(await c.read(startupUpdateCheckProvider.future), isA<UpdateError>());
  });

  test('a 404 manifest is treated as up to date', () async {
    final c = containerFor(serving('', status: 404));

    expect(
      await c.read(startupUpdateCheckProvider.future),
      isA<UpdateUpToDate>(),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/update/startup_update_check_test.dart`
Expected: FAIL — `startup_update_check.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/features/settings/about/startup_update_check.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_service.dart';

/// Runs one update check per launch.
///
/// Launch-only on purpose: no polling timer. A user who wants a newer version
/// restarts the app, which they must do to install one anyway.
///
/// Separate from the About tab's manual check, which keeps its own state so
/// "Check for Updates" still reports an immediate, visible result.
///
/// Resolves to null if the check throws — a failed startup check must never
/// take the app down, and the banner simply stays hidden.
final startupUpdateCheckProvider = FutureProvider<UpdateCheckResult?>((
  ref,
) async {
  try {
    return await ref.read(updateServiceProvider).check();
  } catch (_) {
    return null;
  }
});
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/update/startup_update_check_test.dart && flutter analyze`
Expected: 4 tests PASS; analyzer clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/about/startup_update_check.dart test/update/startup_update_check_test.dart
git commit -m "feat(update): check for updates once per launch"
```

---

### Task 6: The banner, mounted in the shell

**Files:**
- Create: `lib/widgets/update_banner.dart`
- Modify: `lib/app/shell.dart` (mount the banner above the routed child)
- Test: `test/update/update_banner_test.dart` (create)

**Interfaces:**
- Consumes: `startupUpdateCheckProvider` (Task 5), `dismissedUpdateVersionProvider` (Task 3), `shouldShowUpdateBanner` (Task 4), `showUpdateDialog` (Task 2).
- Produces: `class UpdateBanner extends ConsumerWidget`.

- [ ] **Step 1: Write the failing test**

Create `test/update/update_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/dismissed_update_version.dart';
import 'package:payroll_flutter/features/settings/about/startup_update_check.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';
import 'package:payroll_flutter/widgets/update_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

UpdateAvailable _available({
  UpdateChannel channel = UpdateChannel.windowsInstaller,
  String version = '1.0.1',
}) =>
    UpdateAvailable(
      currentVersion: '1.0.0',
      channel: channel,
      manifest: UpdateManifest(
        version: version,
        platforms: const {
          'windows': PlatformAsset(url: 'https://example.test/Setup.exe'),
          'android': PlatformAsset(url: 'https://example.test/app.apk'),
        },
        stores: const {
          'ios': 'https://apps.apple.test/x',
          'android': 'https://play.test/x',
        },
      ),
    );

Future<void> _pump(WidgetTester tester, UpdateCheckResult? result) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        startupUpdateCheckProvider.overrideWith((ref) async => result),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Column(children: [UpdateBanner()])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('announces an available update', (tester) async {
    await _pump(tester, _available());
    expect(find.textContaining('Update available'), findsOneWidget);
    expect(find.textContaining('1.0.1'), findsOneWidget);
  });

  testWidgets('is absent when up to date', (tester) async {
    await _pump(tester, const UpdateUpToDate('1.0.0'));
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('is absent on a store channel', (tester) async {
    await _pump(tester, _available(channel: UpdateChannel.playStore));
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('is absent for an already dismissed version', (tester) async {
    SharedPreferences.setMockInitialValues({
      kDismissedUpdateVersionKey: '1.0.1',
    });
    await _pump(tester, _available(version: '1.0.1'));
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('Later persists the dismissal and hides the banner',
      (tester) async {
    await _pump(tester, _available(version: '1.0.1'));
    expect(find.byType(MaterialBanner), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kDismissedUpdateVersionKey), '1.0.1');
  });

  testWidgets('Update opens the shared dialog', (tester) async {
    await _pump(tester, _available());
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Update available — v1.0.1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/update/update_banner_test.dart`
Expected: FAIL — `update_banner.dart` does not exist.

- [ ] **Step 3: Write the banner**

Create `lib/widgets/update_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/about/banner_visibility.dart';
import '../features/settings/about/dismissed_update_version.dart';
import '../features/settings/about/startup_update_check.dart';
import '../features/settings/about/update_dialog.dart';
import '../features/settings/about/update_service.dart';

/// The startup update notification.
///
/// A MaterialBanner, not a modal (which would interrupt every launch) and not a
/// snackbar (which times out — and launch is exactly when a user looks away).
///
/// Mounted declaratively rather than through
/// ScaffoldMessenger.showMaterialBanner: an imperative show/hide races with
/// Riverpod rebuilds, and a widget that merely returns a banner is directly
/// testable.
///
/// It carries its own action rather than pointing at Settings, because
/// `/settings/*` redirects non-admins to the dashboard — a banner that
/// navigated there would be useless for most users.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(startupUpdateCheckProvider).valueOrNull;
    final dismissed = ref.watch(dismissedUpdateVersionProvider);

    if (!shouldShowUpdateBanner(result: result, dismissedVersion: dismissed)) {
      return const SizedBox.shrink();
    }
    // Narrowed by the predicate; re-asserted so the fields below type-check.
    final update = result as UpdateAvailable;

    return MaterialBanner(
      leading: const Icon(Icons.system_update_alt),
      content: Text(
        'Update available — v${update.manifest.version} '
        "(you're on v${update.currentVersion})",
      ),
      actions: [
        TextButton(
          onPressed: () => ref
              .read(dismissedUpdateVersionProvider.notifier)
              .dismiss(update.manifest.version),
          child: const Text('Later'),
        ),
        TextButton(
          onPressed: () => showUpdateDialog(context, ref, update),
          child: const Text('Update'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the widget tests**

Run: `flutter test test/update/update_banner_test.dart`
Expected: 6 tests PASS.

- [ ] **Step 5: Mount it in the shell**

In `lib/app/shell.dart`, add the import:

```dart
import '../widgets/update_banner.dart';
```

Then replace line 256 — the routed child inside the shell's top-level `Row`:

```dart
          Expanded(child: child),
```

with:

```dart
          Expanded(
            child: Column(
              children: [
                const UpdateBanner(),
                Expanded(child: child),
              ],
            ),
          ),
```

This puts the banner across the content area, to the right of the navigation
rail, above whatever route is showing. The banner returns `SizedBox.shrink()`
when hidden, so it costs nothing in the common case.

Because it lives here, inside the authenticated shell, it cannot appear over the
login screen or the forced password-change flow — those routes never build this
widget.

Change nothing else in this 753-line file.

- [ ] **Step 6: Run the whole suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests PASS (225 pre-existing files plus the new ones); analyzer reports no new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/update_banner.dart lib/app/shell.dart test/update/update_banner_test.dart
git commit -m "feat(update): announce a new version at startup, dismissible per version"
```

---

## Done when

- `flutter test` and `flutter analyze` are both green.
- Launching a Windows or sideloaded-Android build against a manifest with a newer version raises the banner.
- **Later** hides it and it stays hidden across restarts until a newer version is published.
- **Update** opens the same dialog the About tab opens.
- A non-admin user sees and can act on the banner without ever touching `/settings`.
