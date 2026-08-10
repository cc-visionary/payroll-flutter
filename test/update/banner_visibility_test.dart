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
