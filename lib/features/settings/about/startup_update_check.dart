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
