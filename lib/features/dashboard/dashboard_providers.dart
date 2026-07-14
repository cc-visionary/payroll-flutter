import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/applicant.dart';
import '../../data/models/attendance_day.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/department.dart';
import '../../data/models/employee.dart';
import '../../data/models/hiring_entity.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/shift_template.dart';
import '../../data/pagination.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/department_repository.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/holiday_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/shift_template_repository.dart';
import '../attendance/attendance_row_vm.dart' show isoDate;
import '../auth/profile_provider.dart';
import 'dashboard_metrics.dart';
import 'dashboard_period.dart';
import 'leave_expansion.dart';

/// Everything the dashboard derived for one calendar year. Fetched once per
/// year; the selected month is a pure slice of this (see
/// [dashboardViewProvider]) so month-switching never hits the network.
class DashboardYearData {
  final int year;
  final List<MonthMetrics> months; // 12, January first
  final MonthMetrics yearTotal;
  final DashboardYearInput input;
  final int openApplicants;
  final DateTime generatedAt;

  const DashboardYearData({
    required this.year,
    required this.months,
    required this.yearTotal,
    required this.input,
    required this.openApplicants,
    required this.generatedAt,
  });
}

const _kClosedApplicantStatuses = {
  'HIRED',
  'REJECTED',
  'WITHDRAWN',
  'OFFER_DECLINED',
};

/// Fetch + derive one calendar year.
///
/// Keyed on the YEAR only — `.select((p) => p.year)` — so changing the month
/// re-slices without refetching. Watching the whole period here would refetch
/// the entire year on every month click.
final dashboardYearDataProvider = FutureProvider<DashboardYearData>((ref) async {
  // Subscribe to every reactive dependency BEFORE the first await. Riverpod
  // only registers `ref.watch` calls that execute synchronously on the first
  // pass; a watch after an await never subscribes, and the provider silently
  // stops invalidating. (This exact bug shipped once already, with the year
  // dropdown not refiltering.)
  final year = ref.watch(dashboardPeriodProvider.select((p) => p.year));
  final attendanceRepo = ref.watch(attendanceRepositoryProvider);
  final shiftRepo = ref.watch(shiftTemplateRepositoryProvider);
  final scorecardRepo = ref.watch(roleScorecardRepositoryProvider);
  final deptRepo = ref.watch(departmentRepositoryProvider);
  final entityRepo = ref.watch(hiringEntityRepositoryProvider);
  final holidayRepo = ref.watch(holidayRepositoryProvider);

  final profile = await ref.watch(userProfileProvider.future);
  final companyId = profile?.companyId;
  if (companyId == null || companyId.isEmpty) {
    throw StateError('No company on profile');
  }

  final client = Supabase.instance.client;
  final yearStart = DateTime(year, 1, 1);
  final yearEnd = DateTime(year, 12, 31);
  final startIso = _iso(yearStart);
  final endIso = _iso(yearEnd);

  final results = await Future.wait<dynamic>([
    // 0: employees — INCLUDING soft-deleted. Separation can stamp
    //    deleted_at, so filtering here would hide the separations we report.
    _fetchEmployees(client, companyId),
    // 1: attendance for the whole year (paginated inside the repository).
    attendanceRepo.listByRange(
        start: yearStart, end: yearEnd, companyId: companyId),
    // 2: shifts
    shiftRepo.list(),
    // 3: scorecards — onlyActive:false, or a separated employee's superseded
    //    scorecard won't resolve and their shift/work-days go missing.
    scorecardRepo.list(onlyActive: false),
    // 4: departments
    deptRepo.list(companyId),
    // 5: hiring entities
    entityRepo.list(companyId),
    // 6: approved leave requests overlapping the year
    _fetchLeave(client, companyId, startIso, endIso),
    // 7: payslips of RELEASED runs paid within the year
    _fetchPayslips(client, companyId, startIso, endIso),
    // 8: applicants
    _fetchApplicants(client, companyId),
    // 9: holidays for the year
    _fetchHolidays(holidayRepo, companyId, year),
  ]);

  final employees = results[0] as List<Employee>;
  final attendance = results[1] as List<AttendanceDay>;
  final shifts = results[2] as List<ShiftTemplate>;
  final scorecards = results[3] as List<RoleScorecard>;
  final departments = results[4] as List<Department>;
  final entities = results[5] as List<HiringEntity>;
  final leaveDays = results[6] as List<LeaveDayAllocation>;
  final payslips = results[7] as List<DashboardPayslip>;
  final applicants = results[8] as List<Applicant>;
  final holidays = results[9] as List<CalendarEvent>;

  final input = DashboardYearInput(
    year: year,
    employees: employees,
    scorecardsById: {for (final s in scorecards) s.id: s},
    shiftsById: {for (final s in shifts) s.id: s},
    departmentNames: {for (final d in departments) d.id: d.name},
    hiringEntityNames: {for (final e in entities) e.id: e.name},
    // Keyed with the shared `isoDate` helper (attendance_row_vm.dart) — the
    // same key format `buildAttendanceRows` uses to look holidays up. A
    // hand-rolled `substring(0,10)` here would silently zero every holiday.
    holidaysByDate: {for (final h in holidays) isoDate(h.date): h},
    attendance: attendance,
    leaveDays: leaveDays,
    payslips: payslips,
    applicants: applicants,
    // Must be the real wall clock. Task 5 passes `skipFutureDays: false` to
    // the attendance engine, relying on `today` here (not a fabricated one)
    // to clip each employee's window.
    today: DateTime.now(),
  );

  final months = computeMonthMetrics(input);
  final openApplicants = applicants
      .where((a) =>
          !_kClosedApplicantStatuses.contains(a.status.toUpperCase()))
      .length;

  return DashboardYearData(
    year: year,
    months: months,
    yearTotal: aggregateMonths(months, year),
    input: input,
    openApplicants: openApplicants,
    generatedAt: DateTime.now(),
  );
});

/// What the screen renders. A pure re-slice of [dashboardYearDataProvider] —
/// clicking a month in the explorer costs nothing.
class DashboardView {
  final DashboardPeriod period;
  final MonthMetrics metrics; // selected month, or the year total
  final SnapshotMetrics snapshot;
  final List<MonthMetrics> months; // for the explorer
  final MonthMetrics yearTotal;
  final int openApplicants;
  final DateTime generatedAt;

  const DashboardView({
    required this.period,
    required this.metrics,
    required this.snapshot,
    required this.months,
    required this.yearTotal,
    required this.openApplicants,
    required this.generatedAt,
  });
}

final dashboardViewProvider = Provider<AsyncValue<DashboardView>>((ref) {
  final period = ref.watch(dashboardPeriodProvider);
  final async = ref.watch(dashboardYearDataProvider);
  return async.whenData((d) {
    final metrics =
        period.isYear ? d.yearTotal : d.months[period.month - 1];
    final asOf = period.endOn(DateTime.now());
    return DashboardView(
      period: period,
      metrics: metrics,
      snapshot: computeSnapshot(d.input, asOf),
      months: d.months,
      yearTotal: d.yearTotal,
      openApplicants: d.openApplicants,
      generatedAt: d.generatedAt,
    );
  });
});

// ---------------------------------------------------------------------------
// Fetch helpers
// ---------------------------------------------------------------------------

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

Decimal _dec(Object? v) => Decimal.parse((v ?? '0').toString());

Future<List<Employee>> _fetchEmployees(
    SupabaseClient client, String companyId) async {
  final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
    final page = await client
        .from('employees')
        .select()
        .eq('company_id', companyId)
        .order('id')
        .range(from, to);
    return (page as List<dynamic>).cast<Map<String, dynamic>>();
  });
  final out = <Employee>[];
  for (final r in rows) {
    try {
      out.add(Employee.fromRow(r));
    } catch (_) {
      // A single unparseable row must not blank the whole dashboard.
    }
  }
  return out;
}

/// Approved leave overlapping the year, expanded to per-date allocations.
/// Overlap (not containment) so a request straddling Dec→Jan still lands.
Future<List<LeaveDayAllocation>> _fetchLeave(
  SupabaseClient client,
  String companyId,
  String startIso,
  String endIso,
) async {
  try {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await client
          .from('leave_requests')
          .select(
              'employee_id, start_date, end_date, leave_days, start_half, '
              'end_half, status, leave_types(name, code), '
              'employees!inner(company_id)')
          .eq('employees.company_id', companyId)
          .eq('status', 'APPROVED')
          .lte('start_date', endIso)
          .gte('end_date', startIso)
          .order('id')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });

    final out = <LeaveDayAllocation>[];
    for (final r in rows) {
      final t = r['leave_types'] as Map?;
      final typeName =
          (t?['name'] ?? t?['code'] ?? 'Leave').toString();
      out.addAll(expandLeaveRequest(
        employeeId: r['employee_id'] as String,
        startDate: DateTime.parse(r['start_date'] as String),
        endDate: DateTime.parse(r['end_date'] as String),
        leaveDays:
            double.tryParse((r['leave_days'] ?? '0').toString()) ?? 0,
        startHalf: r['start_half'] as String?,
        endHalf: r['end_half'] as String?,
        leaveType: typeName,
      ));
    }
    return out;
  } catch (_) {
    // Degrade to zero leave rather than blanking the page.
    return const [];
  }
}

Future<List<DashboardPayslip>> _fetchPayslips(
  SupabaseClient client,
  String companyId,
  String startIso,
  String endIso,
) async {
  try {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await client
          .from('payslips')
          .select('employee_id, gross_pay, sss_ee, philhealth_ee, '
              'pagibig_ee, withholding_tax, '
              'payroll_runs!inner(company_id, status, pay_date)')
          .eq('payroll_runs.company_id', companyId)
          .eq('payroll_runs.status', 'RELEASED')
          .gte('payroll_runs.pay_date', startIso)
          .lte('payroll_runs.pay_date', endIso)
          .order('id')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    return [
      for (final r in rows)
        DashboardPayslip(
          employeeId: r['employee_id'] as String,
          payDate: DateTime.parse(
              (r['payroll_runs'] as Map)['pay_date'] as String),
          grossPay: _dec(r['gross_pay']),
          sssEe: _dec(r['sss_ee']),
          philhealthEe: _dec(r['philhealth_ee']),
          pagibigEe: _dec(r['pagibig_ee']),
          withholdingTax: _dec(r['withholding_tax']),
        ),
    ];
  } catch (_) {
    // Older schemas may lack payroll_runs.pay_date. Zeroed payroll KPIs beat
    // a dead dashboard.
    return const [];
  }
}

Future<List<Applicant>> _fetchApplicants(
    SupabaseClient client, String companyId) async {
  try {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await client
          .from('applicants')
          .select()
          .eq('company_id', companyId)
          .isFilter('deleted_at', null)
          .order('id')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    final out = <Applicant>[];
    for (final r in rows) {
      try {
        out.add(ApplicantFromRow.fromRow(r));
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return const [];
  }
}

Future<List<CalendarEvent>> _fetchHolidays(
  HolidayRepository repo,
  String companyId,
  int year,
) async {
  try {
    final cal = await repo.byYear(companyId, year);
    if (cal == null) return const [];
    return await repo.events(cal.id);
  } catch (_) {
    return const [];
  }
}
