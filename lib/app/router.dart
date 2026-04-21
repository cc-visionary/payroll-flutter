import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/change_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/employees/employee_form_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/employees/profile/employee_profile_screen.dart';
import '../features/responsibility_cards/responsibility_cards_screen.dart';
import '../features/responsibility_cards/role_scorecard_detail_screen.dart';
import '../features/responsibility_cards/role_scorecard_form_screen.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/attendance/attendance_detail_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/payroll/payslips/detail/payslip_detail_screen.dart';
import '../features/payroll/payslips/payslip_preview_screen.dart';
import '../features/payroll/runs/detail/payroll_run_detail_screen.dart';
import '../features/payroll/runs/payroll_runs_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/adjuncts/adjuncts_screen.dart';
import '../features/assets/assets_screen.dart';
import '../features/audit/audit_log_screen.dart';
import '../features/auth/profile_provider.dart';
import '../features/compensation/compensation_screen.dart';
import '../features/compliance/compliance_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/hiring/hiring_screen.dart';
import '../features/offboarding/offboarding_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/org_chart/org_chart_screen.dart';
import '../features/performance/performance_screen.dart';
import '../features/workflows/workflows_screen.dart';
import '../features/workforce_planning/workforce_planning_screen.dart';
import '../features/auth/session_provider.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: GoRouterRefreshStream(Supabase.instance.client.auth.onAuthStateChange),
    errorBuilder: (c, s) => const _NotFoundRedirect(),
    redirect: (context, state) {
      final loggedIn = auth.asData?.value != null;
      final loggingIn = state.matchedLocation == '/login';
      final changingPassword = state.matchedLocation == '/change-password';
      if (state.matchedLocation == '/') {
        return loggedIn ? '/dashboard' : '/login';
      }
      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/dashboard';

      final profile = ref.read(userProfileProvider).asData?.value;
      if (profile != null) {
        if (profile.mustChangePassword && !changingPassword) {
          return '/change-password';
        }
        if (!profile.mustChangePassword && changingPassword) {
          return '/dashboard';
        }
        final loc = state.matchedLocation;
        if (loc.startsWith('/settings') && !profile.isAdmin) return '/dashboard';
        if (loc.startsWith('/responsibility-cards') && !profile.isHrOrAdmin) return '/dashboard';
        if (loc.startsWith('/workforce-planning') && !profile.isHrOrAdmin) return '/dashboard';
        if (loc.startsWith('/compensation') && !profile.isHrOrAdmin) return '/dashboard';
        if (loc.startsWith('/compliance') && !profile.isHrOrAdmin) return '/dashboard';
        if (loc.startsWith('/audit') && !profile.isAdmin) return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/change-password', builder: (c, s) => const ChangePasswordScreen()),
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
          GoRoute(path: '/employees', builder: (c, s) => const EmployeesScreen()),
          GoRoute(path: '/employees/new', builder: (c, s) => const EmployeeFormScreen()),
          GoRoute(
            path: '/employees/:id',
            builder: (c, s) => EmployeeProfileScreen(employeeId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/employees/:id/edit',
            builder: (c, s) => EmployeeFormScreen(employeeId: s.pathParameters['id']),
          ),
          GoRoute(path: '/responsibility-cards', builder: (c, s) => const ResponsibilityCardsScreen()),
          GoRoute(path: '/responsibility-cards/new', builder: (c, s) => const RoleScorecardFormScreen()),
          GoRoute(
            path: '/responsibility-cards/:id',
            builder: (c, s) => RoleScorecardDetailScreen(cardId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/responsibility-cards/:id/edit',
            builder: (c, s) => RoleScorecardFormScreen(cardId: s.pathParameters['id']),
          ),
          GoRoute(path: '/attendance', builder: (c, s) => const AttendanceScreen()),
          GoRoute(
            path: '/attendance/:employeeId/:date',
            builder: (c, s) {
              final iso = s.pathParameters['date']!;
              return AttendanceDetailScreen(
                employeeId: s.pathParameters['employeeId']!,
                date: DateTime.parse(iso),
              );
            },
          ),
          GoRoute(path: '/payroll', builder: (c, s) => const PayrollRunsScreen()),
          GoRoute(
            path: '/payroll/:id',
            builder: (c, s) =>
                PayrollRunDetailScreen(runId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/payroll/:runId/payslip/:payslipId',
            builder: (c, s) => PayslipDetailScreen(
              runId: s.pathParameters['runId']!,
              payslipId: s.pathParameters['payslipId']!,
            ),
          ),
          GoRoute(
            path: '/payslips/:id',
            builder: (c, s) => PayslipPreviewScreen(payslipId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/adjuncts', builder: (c, s) => const AdjunctsScreen()),
          GoRoute(path: '/hiring', builder: (c, s) => const HiringScreen()),
          GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
          GoRoute(path: '/offboarding', builder: (c, s) => const OffboardingScreen()),
          GoRoute(path: '/org-chart', builder: (c, s) => const OrgChartScreen()),
          GoRoute(path: '/workforce-planning', builder: (c, s) => const WorkforcePlanningScreen()),
          GoRoute(path: '/performance', builder: (c, s) => const PerformanceScreen()),
          GoRoute(path: '/compensation', builder: (c, s) => const CompensationScreen()),
          GoRoute(path: '/assets', builder: (c, s) => const AssetsScreen()),
          GoRoute(path: '/compliance', builder: (c, s) => const ComplianceScreen()),
          GoRoute(path: '/workflows', builder: (c, s) => const WorkflowsScreen()),
          GoRoute(path: '/documents', builder: (c, s) => const DocumentsScreen()),
          GoRoute(path: '/audit', builder: (c, s) => const AuditLogScreen()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
          GoRoute(
            path: '/settings/:tab',
            builder: (c, s) => SettingsScreen(initialTab: s.pathParameters['tab']),
          ),
        ],
      ),
    ],
  );
});

class _NotFoundRedirect extends StatelessWidget {
  const _NotFoundRedirect();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/dashboard');
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

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
