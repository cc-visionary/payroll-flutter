import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';

/// Covers the final fix wave's CRITICAL finding: `UserProfile.isAdmin`
/// (and therefore `isHrOrAdmin`) includes PAYROLL_ADMIN, so the
/// `/kpi-results` route guard used to admit it -- but
/// `ReviewCycleRepository.callerSeesAllReviews()` (see
/// `review_cycle_repository_test.dart`) never certified full review
/// visibility for PAYROLL_ADMIN. A PAYROLL_ADMIN could reach "Recompute" and
/// silently overwrite every review-sourced KPI result with NO_DATA.
///
/// `isPerformanceAdmin` is the fix: a narrower predicate the `/kpi-results`
/// guard now uses instead of `isHrOrAdmin`, built from
/// [kPerformanceAdminRoleCodes] -- the SAME constant
/// `ReviewCycleRepository._kFullReviewVisibilityRoles` is now literally
/// defined as (see that class's doc comment). This suite pins
/// [isPerformanceAdmin]'s membership directly, so an edit that quietly
/// widens it (e.g. "fixing" a permission complaint by adding PAYROLL_ADMIN
/// back) fails here first, on the readable end of the seam, rather than
/// being caught only downstream after a Recompute has already run.
UserProfile _profile(AppRole role) => UserProfile(
  userId: 'u1',
  email: 'u@example.com',
  companyId: 'co-1',
  employeeId: null,
  appRole: role,
  mustChangePassword: false,
);

void main() {
  group('UserProfile.isPerformanceAdmin', () {
    for (final role in const [
      AppRole.SUPER_ADMIN,
      AppRole.ADMIN,
      AppRole.HR,
      AppRole.HR_ADMIN,
    ]) {
      test('$role sees the /kpi-results route', () {
        expect(_profile(role).isPerformanceAdmin, isTrue);
      });
    }

    for (final role in const [
      AppRole.PAYROLL_ADMIN,
      AppRole.FINANCE_MANAGER,
      AppRole.MANAGER,
      AppRole.EMPLOYEE,
    ]) {
      test('$role does NOT see the /kpi-results route', () {
        expect(_profile(role).isPerformanceAdmin, isFalse);
      });
    }

    test(
      'PAYROLL_ADMIN is the exact divergence from isHrOrAdmin -- the defect '
      'this predicate exists to close',
      () {
        final payrollAdmin = _profile(AppRole.PAYROLL_ADMIN);
        expect(
          payrollAdmin.isHrOrAdmin,
          isTrue,
          reason:
              'isHrOrAdmin (used by every OTHER HR-gated route) still '
              'admits PAYROLL_ADMIN -- unchanged by this fix, deliberately',
        );
        expect(
          payrollAdmin.isPerformanceAdmin,
          isFalse,
          reason:
              'but /kpi-results must not, because callerSeesAllReviews() '
              'never certifies PAYROLL_ADMIN for full review visibility',
        );
      },
    );

    test(
      'membership is pinned to exactly the four roles '
      'kPerformanceAdminRoleCodes names -- a change here is a deliberate '
      'policy decision, not an accident',
      () {
        for (final role in AppRole.values) {
          expect(
            _profile(role).isPerformanceAdmin,
            kPerformanceAdminRoleCodes.contains(appRoleCode(role)),
            reason: '$role must agree with kPerformanceAdminRoleCodes',
          );
        }
      },
    );
  });
}
