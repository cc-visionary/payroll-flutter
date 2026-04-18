import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'app/theme_mode_provider.dart';
import 'core/env.dart';
import 'data/supabase/client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fail fast on release builds that forgot their `--dart-define` flags.
  // In debug the call is a no-op so local `flutter run` stays convenient.
  Env.assertConfigured(isRelease: kReleaseMode);
  await initSupabase();
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
    );
  }
}
