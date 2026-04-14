import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/responsibility_cards/responsibility_cards_screen.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/payroll/runs/payroll_runs_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/auth/session_provider.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  return GoRouter(
    initialLocation: '/employees',
    refreshListenable: GoRouterRefreshStream(Supabase.instance.client.auth.onAuthStateChange),
    redirect: (context, state) {
      final loggedIn = auth.asData?.value != null;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/employees';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/employees', builder: (c, s) => const EmployeesScreen()),
          GoRoute(path: '/responsibility-cards', builder: (c, s) => const ResponsibilityCardsScreen()),
          GoRoute(path: '/attendance', builder: (c, s) => const AttendanceScreen()),
          GoRoute(path: '/payroll', builder: (c, s) => const PayrollRunsScreen()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
        ],
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
