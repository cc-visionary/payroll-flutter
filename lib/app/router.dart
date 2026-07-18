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
import '../features/responsibility_cards/role_card_pdf_screen.dart';
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
import '../features/documents/bulk/bulk_generate_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/documents/generate_screen.dart';
import '../features/documents/view/document_view_screen.dart';
import '../features/hiring/hiring_screen.dart';
import '../features/hiring/applicant_form_screen.dart';
import '../features/hiring/applicant_detail_screen.dart';
import '../features/hiring/listing_form_screen.dart';
import '../features/hiring/listing_detail_screen.dart';
import '../features/kpi_library/kpi_library_screen.dart';
import '../features/org_chart/org_chart_screen.dart';
import '../features/performance/performance_screen.dart';
import '../features/performance/performance_check_in_screen.dart';
import '../features/performance/employee_review_detail_screen.dart';
import '../features/performance/manager_evaluation_screen.dart';
import '../features/performance/review_completion_screen.dart';
import '../features/performance/monthly_development_checkin_screen.dart';
import '../features/performance/review_cycle_detail_screen.dart';
import '../features/performance/review_cycle_form_screen.dart';
import '../features/performance/review_cycles_screen.dart';
import '../features/workflows/workflows_screen.dart';
import '../features/workflows/workflow_detail_screen.dart';
import '../features/workforce_planning/workforce_planning_screen.dart';
import '../features/auth/session_provider.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  // Nudge the router to re-run redirect whenever the async user profile
  // resolves — otherwise a fresh sign-in can land on /dashboard before
  // must_change_password has loaded, and the redirect never fires again.
  final profileRefresh = ValueNotifier<int>(0);
  ref.listen(userProfileProvider, (previous, next) {
    profileRefresh.value++;
  });
  ref.onDispose(profileRefresh.dispose);
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: Listenable.merge([
      GoRouterRefreshStream(Supabase.instance.client.auth.onAuthStateChange),
      profileRefresh,
    ]),
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
        if (loc.startsWith('/settings') && !profile.isAdmin) {
          return '/dashboard';
        }
        // The read-only role-card PDF (/responsibility-cards/:id/pdf) is reachable
        // from the employee-review screen, which non-HR direct managers use, so
        // exempt that leaf from the HR-only management-UI redirect. RLS on
        // role_scorecards (company-wide read) still governs the actual fetch.
        if (loc.startsWith('/responsibility-cards') &&
            !loc.endsWith('/pdf') &&
            !profile.isHrOrAdmin) {
          return '/dashboard';
        }
        if (loc.startsWith('/kpi-library') && !profile.isHrOrAdmin) {
          return '/dashboard';
        }
        if (loc.startsWith('/workforce-planning') && !profile.isHrOrAdmin) {
          return '/dashboard';
        }
        if (loc.startsWith('/compensation') && !profile.isHrOrAdmin) {
          return '/dashboard';
        }
        if (loc.startsWith('/compliance') && !profile.isHrOrAdmin) {
          return '/dashboard';
        }
        if (loc.startsWith('/audit') && !profile.isAdmin) return '/dashboard';
        if (loc.startsWith('/performance/review-cycles') &&
            !profile.isHrOrAdmin) {
          return '/performance';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(
        path: '/change-password',
        builder: (c, s) => const ChangePasswordScreen(),
      ),
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (c, s) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/employees',
            builder: (c, s) => const EmployeesScreen(),
          ),
          GoRoute(
            path: '/employees/new',
            builder: (c, s) => const EmployeeFormScreen(),
          ),
          GoRoute(
            path: '/employees/:id',
            builder: (c, s) =>
                EmployeeProfileScreen(employeeId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/employees/:id/edit',
            builder: (c, s) =>
                EmployeeFormScreen(employeeId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/responsibility-cards',
            builder: (c, s) => const ResponsibilityCardsScreen(),
          ),
          GoRoute(
            path: '/responsibility-cards/new',
            builder: (c, s) => const RoleScorecardFormScreen(),
          ),
          GoRoute(
            path: '/responsibility-cards/:id/pdf',
            builder: (c, s) =>
                RoleCardPdfScreen(cardId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/responsibility-cards/:id',
            builder: (c, s) =>
                RoleScorecardDetailScreen(cardId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/responsibility-cards/:id/edit',
            builder: (c, s) =>
                RoleScorecardFormScreen(cardId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/kpi-library',
            builder: (c, s) => const KpiLibraryScreen(),
          ),
          GoRoute(
            path: '/attendance',
            builder: (c, s) => const AttendanceScreen(),
          ),
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
          GoRoute(
            path: '/payroll',
            builder: (c, s) => const PayrollRunsScreen(),
          ),
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
            builder: (c, s) =>
                PayslipPreviewScreen(payslipId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/adjuncts', builder: (c, s) => const AdjunctsScreen()),
          GoRoute(path: '/hiring', builder: (c, s) => const HiringScreen()),
          GoRoute(
            path: '/hiring/new',
            builder: (c, s) => const ApplicantFormScreen(),
          ),
          GoRoute(
            path: '/hiring/listings/new',
            builder: (c, s) => const ListingFormScreen(),
          ),
          GoRoute(
            path: '/hiring/listings/:id',
            builder: (c, s) =>
                ListingDetailScreen(listingId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/hiring/listings/:id/edit',
            builder: (c, s) =>
                ListingFormScreen(listingId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/hiring/listings/:id/applicants/new',
            builder: (c, s) =>
                ApplicantFormScreen(listingId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/hiring/:id',
            builder: (c, s) =>
                ApplicantDetailScreen(applicantId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/hiring/:id/edit',
            builder: (c, s) =>
                ApplicantFormScreen(applicantId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/org-chart',
            builder: (c, s) => const OrgChartScreen(),
          ),
          GoRoute(
            path: '/workforce-planning',
            builder: (c, s) => const WorkforcePlanningScreen(),
          ),
          GoRoute(
            path: '/performance',
            builder: (c, s) => const PerformanceScreen(),
          ),
          GoRoute(
            path: '/performance/review-cycles',
            builder: (c, s) => const ReviewCyclesScreen(),
          ),
          GoRoute(
            path: '/performance/review-cycles/new',
            builder: (c, s) => const ReviewCycleFormScreen(),
          ),
          GoRoute(
            path: '/performance/review-cycles/:id',
            builder: (c, s) =>
                ReviewCycleDetailScreen(cycleId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/performance/reviews/:id',
            builder: (c, s) =>
                EmployeeReviewDetailScreen(reviewId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/performance/reviews/:id/evaluate',
            builder: (c, s) =>
                ManagerEvaluationScreen(reviewId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/performance/reviews/:id/complete',
            builder: (c, s) =>
                ReviewCompletionScreen(reviewId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/performance/reviews/:id/monthly-check-in',
            builder: (c, s) => MonthlyDevelopmentCheckinScreen(
              reviewId: s.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/performance/:id',
            builder: (c, s) =>
                PerformanceCheckInScreen(checkInId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/compensation',
            builder: (c, s) => const CompensationScreen(),
          ),
          GoRoute(path: '/assets', builder: (c, s) => const AssetsScreen()),
          GoRoute(
            path: '/compliance',
            builder: (c, s) => const ComplianceScreen(),
          ),
          GoRoute(
            path: '/workflows',
            builder: (c, s) => const WorkflowsScreen(),
          ),
          GoRoute(
            path: '/workflows/:id',
            builder: (c, s) =>
                WorkflowDetailScreen(instanceId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/documents',
            builder: (c, s) => DocumentsScreen(
              employeeId: s.uri.queryParameters['employeeId'],
            ),
          ),
          GoRoute(
            path: '/documents/bulk',
            builder: (c, s) => const BulkGenerateScreen(),
          ),
          GoRoute(
            path: '/documents/generate/:templateId',
            builder: (c, s) => GenerateScreen(
              templateId: s.pathParameters['templateId']!,
              employeeId: s.uri.queryParameters['employeeId'],
              compensationChangeId: s.uri.queryParameters['changeId'],
              documentId: s.uri.queryParameters['documentId'],
            ),
          ),
          GoRoute(
            path: '/documents/view/:id',
            builder: (c, s) =>
                DocumentViewScreen(documentId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/audit', builder: (c, s) => const AuditLogScreen()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
          GoRoute(
            path: '/settings/:tab',
            builder: (c, s) =>
                SettingsScreen(initialTab: s.pathParameters['tab']),
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
