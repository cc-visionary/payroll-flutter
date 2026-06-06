import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/employee.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';

/// Outcome of a batch generation run: how many check-ins were newly created
/// vs. already existed (idempotent skips).
typedef BatchGenResult = ({int created, int existed});

/// Manually generates performance check-ins for every ACTIVE employee for the
/// given quarter:
///   - REGULAR      → one check-in in that quarter's company-wide period
///   - PROBATIONARY → check-ins for each 1M/3M/5M milestone already reached
///     (milestones are date-based off hire date, independent of the quarter)
///
/// Skill ratings are seeded from each employee's RoleScorecard KPIs. Every step
/// is idempotent, so re-running a quarter never creates duplicates. Returns the
/// created/existed counts for user feedback.
///
/// Triggered manually from the Performance screen — there is intentionally no
/// automatic generation on screen open.
Future<BatchGenResult> generatePerformanceCheckInsForQuarter(
  WidgetRef ref, {
  required int year,
  required int quarter,
}) async {
  final profile = await ref.read(userProfileProvider.future);
  final companyId = profile?.companyId;
  if (companyId == null || companyId.isEmpty) {
    throw Exception('No company on your profile.');
  }
  final repo = ref.read(performanceRepositoryProvider);
  final now = DateTime.now().toUtc();

  final quarterlyPeriodId = await repo.ensureQuarterlyPeriod(
    companyId: companyId,
    year: year,
    quarter: quarter,
  );

  final employees =
      await ref.read(employeeListProvider(const EmployeeListQuery()).future);

  var created = 0;
  var existed = 0;

  Future<void> ensureOne(String periodId, Employee emp) async {
    final pre =
        await repo.findCheckInId(periodId: periodId, employeeId: emp.id);
    final checkInId = await repo.ensureCheckInForEmployeeInPeriod(
      periodId: periodId,
      employeeId: emp.id,
      reviewerId: emp.reportsToId,
    );
    await repo.seedSkillRatingsForCheckIn(
      checkInId: checkInId,
      roleScorecardId: emp.roleScorecardId,
    );
    if (pre == null) {
      created++;
    } else {
      existed++;
    }
  }

  for (final emp in employees) {
    if (emp.employmentStatus != 'ACTIVE') continue;

    if (emp.employmentType == 'REGULAR') {
      await ensureOne(quarterlyPeriodId, emp);
    } else if (emp.employmentType == 'PROBATIONARY') {
      final periodIds = await repo.ensureProbationaryPeriodsForEmployee(
        companyId: companyId,
        employeeId: emp.id,
        employeeFullName: emp.fullName,
        hireDate: emp.hireDate,
        now: now,
      );
      for (final pid in periodIds) {
        await ensureOne(pid, emp);
      }
    }
    // Other employmentTypes are out of scope.
  }

  return (created: created, existed: existed);
}
