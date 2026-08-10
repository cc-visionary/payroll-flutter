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
