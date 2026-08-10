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
    final result = ref.watch(startupUpdateCheckProvider).value;
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
