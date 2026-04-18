/// Compile-time environment via --dart-define.
///
/// Required build flags for RELEASE / public builds:
///   `--dart-define=SUPABASE_URL=https://PROJECT.supabase.co`
///   `--dart-define=SUPABASE_ANON_KEY=ANON_KEY`
///
/// Optional:
///   `--dart-define=UPDATE_MANIFEST_URL=https://.../version.json`
///
/// Defaults are for local development only (local Supabase CLI at
/// 127.0.0.1:54321). Shipping with the defaults means the app will try to
/// connect to nothing — call [Env.assertConfigured] during boot to surface
/// that clearly instead of failing later with obscure Supabase errors.
class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const String appName = 'Luxium Payroll';

  /// Whether the build looks like a release build pointing at real infra.
  static bool get isProdConfigured =>
      !supabaseUrl.contains('127.0.0.1') &&
      !supabaseUrl.contains('localhost') &&
      supabaseAnonKey.isNotEmpty;

  /// Fail-fast on misconfigured release builds. Call from `main()` before
  /// `runApp`. Throws [StateError] with a human-readable message — Flutter's
  /// default error screen surfaces this clearly in debug; in release it still
  /// prevents the app from booting into a confusing auth-failing state.
  static void assertConfigured({required bool isRelease}) {
    if (!isRelease) return;
    final missing = <String>[];
    if (supabaseUrl.contains('127.0.0.1') ||
        supabaseUrl.contains('localhost')) {
      missing.add('SUPABASE_URL (still pointing at localhost)');
    }
    if (supabaseAnonKey.isEmpty) {
      missing.add('SUPABASE_ANON_KEY (empty)');
    }
    if (missing.isEmpty) return;
    throw StateError(
      'Missing --dart-define at build time: ${missing.join(", ")}. '
      'Pass them to `flutter build` — see installer/<platform>/README.md.',
    );
  }
}
