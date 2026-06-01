import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';

/// Lazy auto-generation: ensures the current quarter's company-wide period
/// exists, then for each active employee ensures the right check-ins exist
/// (quarterly for REGULAR, 1M/3M/5M for PROBATIONARY), with skill_ratings
/// auto-seeded from the employee's RoleScorecard KPIs.
///
/// Called once when /performance is opened. Idempotent at every step.
Future<void> autoGeneratePerformanceForCurrentQuarter(WidgetRef ref) async {
  final profile = await ref.read(userProfileProvider.future);
  final companyId = profile?.companyId;
  if (companyId == null) return;
  final repo = ref.read(performanceRepositoryProvider);
  final now = DateTime.now().toUtc();

  // 1. Quarterly company-wide period (for REGULAR employees).
  final quarterlyPeriodId = await repo.ensureQuarterlyPeriodForCurrentQuarter(
    companyId: companyId,
    now: now,
  );

  // 2. For each active employee, ensure the right check-ins exist.
  final employees = await ref.read(
      employeeListProvider(const EmployeeListQuery()).future);
  for (final emp in employees) {
    if (emp.employmentStatus != 'ACTIVE') continue;
    final reviewerId = emp.reportsToId;

    if (emp.employmentType == 'REGULAR') {
      final checkInId = await repo.ensureCheckInForEmployeeInPeriod(
        periodId: quarterlyPeriodId,
        employeeId: emp.id,
        reviewerId: reviewerId,
      );
      await repo.seedSkillRatingsForCheckIn(
        checkInId: checkInId,
        roleScorecardId: emp.roleScorecardId,
      );
    } else if (emp.employmentType == 'PROBATIONARY') {
      final periodIds = await repo.ensureProbationaryPeriodsForEmployee(
        companyId: companyId,
        employeeId: emp.id,
        employeeFullName: emp.fullName,
        hireDate: emp.hireDate,
        now: now,
      );
      for (final pid in periodIds) {
        final checkInId = await repo.ensureCheckInForEmployeeInPeriod(
          periodId: pid,
          employeeId: emp.id,
          reviewerId: reviewerId,
        );
        await repo.seedSkillRatingsForCheckIn(
          checkInId: checkInId,
          roleScorecardId: emp.roleScorecardId,
        );
      }
    }
    // Other employmentTypes are out of scope in v1.
  }
}
