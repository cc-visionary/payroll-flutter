import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where the app looks for `version.json`.
///
/// Override per build with:
///   flutter build windows --dart-define=UPDATE_MANIFEST_URL=https://.../version.json
///
/// The default points at the GitHub Releases "latest" redirector so any build —
/// including local dev builds and manually-compiled installers — can check for
/// updates out of the box. CI injects the same URL via --dart-define for
/// parity. Host the manifest on any static URL (Supabase Storage, S3, plain
/// web) by overriding this at build time.
const String kUpdateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue:
      'https://github.com/cc-visionary/payroll-flutter/releases/latest/download/version.json',
);

/// Per-platform install channel. Used to pick between a store-link update
/// (App Store / Play Store) and a direct installer download (desktop).
enum UpdateChannel {
  windowsInstaller,
  macosDirect,
  linuxDirect,
  appStore,
  playStore,
  sideloadAndroid,
  web,
  unknown;

  String get label {
    switch (this) {
      case UpdateChannel.windowsInstaller:
        return 'Windows Desktop';
      case UpdateChannel.macosDirect:
        return 'macOS Desktop';
      case UpdateChannel.linuxDirect:
        return 'Linux Desktop';
      case UpdateChannel.appStore:
        return 'iOS · App Store';
      case UpdateChannel.playStore:
        return 'Android · Google Play';
      case UpdateChannel.sideloadAndroid:
        return 'Android · Sideload';
      case UpdateChannel.web:
        return 'Web Application';
      case UpdateChannel.unknown:
        return 'Unknown Platform';
    }
  }

  bool get isDesktop => switch (this) {
        UpdateChannel.windowsInstaller ||
        UpdateChannel.macosDirect ||
        UpdateChannel.linuxDirect =>
          true,
        _ => false,
      };

  bool get isStore => switch (this) {
        UpdateChannel.appStore || UpdateChannel.playStore => true,
        _ => false,
      };
}

/// Shape of the hosted `version.json` manifest.
///
/// Example:
/// ```json
/// {
///   "version": "1.0.1",
///   "buildNumber": 5,
///   "releaseNotes": "- Fixed tooltip sizing\n- Faster payroll runs",
///   "releasedAt": "2026-05-01T00:00:00Z",
///   "platforms": {
///     "windows": { "url": "https://.../PayrollFlutter-Setup-v1.0.1.exe", "sha256": "" },
///     "macos":   { "url": "https://.../PayrollFlutter-v1.0.1.dmg" },
///     "linux":   { "url": "https://.../PayrollFlutter-v1.0.1.AppImage" }
///   },
///   "stores": {
///     "ios": "https://apps.apple.com/app/idXXXXXXXXX",
///     "android": "https://play.google.com/store/apps/details?id=ph.luxium.payroll"
///   }
/// }
/// ```
class UpdateManifest {
  final String version;
  final int? buildNumber;
  final String? releaseNotes;
  final DateTime? releasedAt;
  final Map<String, PlatformAsset> platforms;
  final Map<String, String> stores;

  const UpdateManifest({
    required this.version,
    this.buildNumber,
    this.releaseNotes,
    this.releasedAt,
    required this.platforms,
    required this.stores,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> j) {
    final platforms = <String, PlatformAsset>{};
    final rawPlatforms = j['platforms'];
    if (rawPlatforms is Map) {
      for (final e in rawPlatforms.entries) {
        final v = e.value;
        if (v is Map) {
          platforms[e.key.toString()] = PlatformAsset(
            url: (v['url'] as String?) ?? '',
            sha256: v['sha256'] as String?,
          );
        }
      }
    }
    final stores = <String, String>{};
    final rawStores = j['stores'];
    if (rawStores is Map) {
      for (final e in rawStores.entries) {
        final v = e.value;
        if (v is String) stores[e.key.toString()] = v;
      }
    }
    return UpdateManifest(
      version: j['version'] as String,
      buildNumber: (j['buildNumber'] as num?)?.toInt(),
      releaseNotes: j['releaseNotes'] as String?,
      releasedAt: j['releasedAt'] == null
          ? null
          : DateTime.tryParse(j['releasedAt'] as String),
      platforms: platforms,
      stores: stores,
    );
  }

  PlatformAsset? assetFor(UpdateChannel channel) {
    switch (channel) {
      case UpdateChannel.windowsInstaller:
        return platforms['windows'];
      case UpdateChannel.macosDirect:
        return platforms['macos'];
      case UpdateChannel.linuxDirect:
        return platforms['linux'];
      case UpdateChannel.sideloadAndroid:
        // Sideload Android pulls the .apk directly from GitHub Releases; no
        // Play Store store-link, no auto-install (Android blocks those from
        // unknown sources). Opens the APK in the browser so the OS's
        // "package installer" flow takes over.
        return platforms['android'];
      default:
        return null;
    }
  }

  String? storeLinkFor(UpdateChannel channel) {
    switch (channel) {
      case UpdateChannel.appStore:
        return stores['ios'];
      case UpdateChannel.playStore:
        return stores['android'];
      default:
        return null;
    }
  }
}

class PlatformAsset {
  final String url;
  final String? sha256;
  const PlatformAsset({required this.url, this.sha256});
}

/// Result of a single update check.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpdateUpToDate extends UpdateCheckResult {
  final String currentVersion;
  const UpdateUpToDate(this.currentVersion);
}

class UpdateAvailable extends UpdateCheckResult {
  final String currentVersion;
  final UpdateManifest manifest;
  final UpdateChannel channel;
  const UpdateAvailable({
    required this.currentVersion,
    required this.manifest,
    required this.channel,
  });
}

class UpdateError extends UpdateCheckResult {
  final String message;
  const UpdateError(this.message);
}

/// Central update service. Detects the channel for the current device and
/// knows how to: (1) fetch the manifest, (2) compare versions, (3) open the
/// right update path (store link / download-and-launch installer / browser
/// reload prompt).
class UpdateService {
  final http.Client _http;
  final String manifestUrl;
  UpdateService({http.Client? httpClient, String? manifestUrl})
      : _http = httpClient ?? http.Client(),
        manifestUrl = manifestUrl ?? kUpdateManifestUrl;

  /// Auto-detect the install channel from the current device + installer
  /// metadata. For Android we distinguish Play-store installs from sideloads
  /// via `PackageInfo.installerStore`.
  static Future<UpdateChannel> detectChannel() async {
    if (kIsWeb) return UpdateChannel.web;
    try {
      if (Platform.isWindows) return UpdateChannel.windowsInstaller;
      if (Platform.isMacOS) return UpdateChannel.macosDirect;
      if (Platform.isLinux) return UpdateChannel.linuxDirect;
      if (Platform.isIOS) return UpdateChannel.appStore;
      if (Platform.isAndroid) {
        try {
          final info = await PackageInfo.fromPlatform();
          // Play Store installer package id.
          if (info.installerStore == 'com.android.vending') {
            return UpdateChannel.playStore;
          }
          return UpdateChannel.sideloadAndroid;
        } catch (_) {
          return UpdateChannel.sideloadAndroid;
        }
      }
    } catch (_) {
      // Platform getters throw on web when dart:io is unsupported.
    }
    return UpdateChannel.unknown;
  }

  Future<UpdateCheckResult> check() async {
    final channel = await detectChannel();
    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    try {
      final res = await _http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 404) {
        // No release published yet — friendlier than a raw 404.
        return UpdateUpToDate(current);
      }
      if (res.statusCode != 200) {
        return UpdateError(
            'Update server returned HTTP ${res.statusCode}.');
      }
      final manifest = UpdateManifest.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
      if (!_isNewer(manifest.version, current)) {
        return UpdateUpToDate(current);
      }
      return UpdateAvailable(
        currentVersion: current,
        manifest: manifest,
        channel: channel,
      );
    } on TimeoutException {
      return const UpdateError('Update check timed out.');
    } on SocketException {
      return const UpdateError('No internet connection.');
    } on HandshakeException {
      return const UpdateError(
          "Couldn't reach the update server (TLS handshake failed). "
          'Check that the update URL is correct.');
    } on HttpException catch (e) {
      return UpdateError('Update server error: ${e.message}');
    } on FormatException {
      return const UpdateError('Update manifest is malformed.');
    } catch (e) {
      return UpdateError('Update check failed: $e');
    }
  }

  /// Compares semver-ish strings. Handles `1.0.0`, `1.0`, `1.0.0+5`.
  static bool _isNewer(String remote, String local) {
    List<int> parts(String s) {
      final trimmed = s.split('+').first.split('-').first;
      return trimmed
          .split('.')
          .map((p) => int.tryParse(p) ?? 0)
          .toList(growable: true);
    }

    final a = parts(remote);
    final b = parts(local);
    while (a.length < b.length) {
      a.add(0);
    }
    while (b.length < a.length) {
      b.add(0);
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] > b[i]) return true;
      if (a[i] < b[i]) return false;
    }
    return false;
  }

  /// Execute the update action appropriate for the detected channel.
  ///
  /// - Desktop: download installer, launch it, request app exit.
  /// - iOS/Android store: open store link.
  /// - Sideload Android / Linux direct / Web: open the asset or return false.
  Future<bool> launchUpdate(UpdateAvailable update,
      {void Function(double progress)? onProgress}) async {
    switch (update.channel) {
      case UpdateChannel.windowsInstaller:
        return _downloadAndLaunchWindowsInstaller(update, onProgress);
      case UpdateChannel.macosDirect:
      case UpdateChannel.linuxDirect:
      case UpdateChannel.sideloadAndroid:
        // Sideload Android: open the GitHub Release APK in the browser;
        // Android's package installer takes over once the download lands.
        final asset = update.manifest.assetFor(update.channel);
        if (asset == null || asset.url.isEmpty) return false;
        return launchUrl(Uri.parse(asset.url),
            mode: LaunchMode.externalApplication);
      case UpdateChannel.appStore:
      case UpdateChannel.playStore:
        final link = update.manifest.storeLinkFor(update.channel);
        if (link == null || link.isEmpty) return false;
        return launchUrl(Uri.parse(link),
            mode: LaunchMode.externalApplication);
      case UpdateChannel.web:
        // Hosted web app — a simple reload picks up the new bundle.
        if (kIsWeb) {
          // Defer to the browser; callers show a reload-required dialog.
          return true;
        }
        return false;
      case UpdateChannel.unknown:
        return false;
    }
  }

  Future<bool> _downloadAndLaunchWindowsInstaller(
    UpdateAvailable update,
    void Function(double)? onProgress,
  ) async {
    // Defensive belt-and-suspenders guard. `launchUpdate` already dispatches
    // by `UpdateChannel` but `dart:io` APIs and `Process.start` will get this
    // file auto-rejected by App Store review if ever invoked on iOS.
    if (kIsWeb || !Platform.isWindows) return false;
    final asset = update.manifest.assetFor(UpdateChannel.windowsInstaller);
    if (asset == null || asset.url.isEmpty) return false;
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'PayrollFlutter-Setup-v${update.manifest.version}.exe';
      final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');

      final req = http.Request('GET', Uri.parse(asset.url));
      final streamed = await _http.send(req);
      if (streamed.statusCode != 200) return false;

      final total = streamed.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await streamed.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null && total > 0) {
            onProgress(received / total);
          }
        },
        onDone: () {},
        onError: (_) {},
        cancelOnError: true,
      ).asFuture();
      await sink.flush();
      await sink.close();

      // Fire-and-forget the installer; the user is prompted by Inno Setup to
      // close the running app. The caller should request a graceful exit
      // after this returns.
      await Process.start(file.path, const <String>[],
          mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Provider wiring so callers can `ref.read(updateServiceProvider)` and
/// `ref.watch(updateChannelProvider)` for the detected platform label.
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final updateChannelProvider = FutureProvider<UpdateChannel>(
    (ref) => UpdateService.detectChannel());
