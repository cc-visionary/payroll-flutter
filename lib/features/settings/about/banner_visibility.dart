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
