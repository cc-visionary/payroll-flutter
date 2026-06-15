import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'app/theme_mode_provider.dart';
import 'core/env.dart';
import 'data/repositories/audit_repository.dart';
import 'data/services/auth_audit_service.dart';
import 'data/supabase/client.dart';

/// TEMPORARY DIAGNOSTIC (debug only): the known Flutter desktop mouse-tracker
/// reentrancy bug (`!_debugDuringDeviceUpdate`) cascades into "Cannot hit test a
/// render box with no size" and floods the console with a full error dump on
/// every pointer event — which itself freezes the UI. This filter presents the
/// FIRST occurrence of each signature in full (so we capture the culprit widget
/// + stack) and suppresses the repeats so the app stays responsive while we
/// localise the root cause. Remove once the trigger is found and fixed.
void _installMouseTrackerDiagnostics() {
  final original = FlutterError.onError;
  final presented = <String>{};
  var suppressed = 0;

  String signatureOf(String s) {
    if (s.contains('Cannot hit test a render box with no size')) return 'no-size';
    if (s.contains('_debugDuringDeviceUpdate') || s.contains('mouse_tracker')) {
      return 'mouse-tracker';
    }
    return '';
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    final sig = signatureOf(details.exceptionAsString());
    if (sig.isNotEmpty) {
      if (presented.add(sig)) {
        debugPrint('\n━━━━━━ [mouse-tracker diagnostic] FIRST "$sig" — '
            'full details below (this names the culprit widget) ━━━━━━');
        FlutterError.presentError(details);
        debugPrint('━━━━━━ [mouse-tracker diagnostic] further "$sig" errors '
            'will be SUPPRESSED to keep the app responsive ━━━━━━\n');
      } else {
        suppressed++;
        if (suppressed % 2000 == 0) {
          debugPrint('[mouse-tracker diagnostic] suppressed $suppressed '
              'repeat framework mouse errors so far');
        }
      }
      return; // these are caught, non-fatal framework errors
    }
    (original ?? FlutterError.presentError)(details);
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) _installMouseTrackerDiagnostics();
  // Fail fast on release builds that forgot their `--dart-define` flags.
  // In debug the call is a no-op so local `flutter run` stays convenient.
  Env.assertConfigured(isRelease: kReleaseMode);
  await initSupabase();
  // Wire LOGIN / LOGOUT audit instrumentation before ProviderScope
  // mounts — a persisted session may already be active by the time
  // the first widget builds, and we want the subscription live for
  // any auth event fired during/after restoration.
  AuthAuditService(AuditRepository(Supabase.instance.client))
      .start(Supabase.instance.client);
  runApp(const ProviderScope(child: PayrollApp()));
}

class PayrollApp extends ConsumerWidget {
  const PayrollApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: Env.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
      ],
    );
  }
}
