import 'package:decimal/decimal.dart';

import '../../data/models/applicant.dart';
import '../../data/models/attendance_day.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/employee.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/shift_template.dart';
import '../attendance/attendance_row_vm.dart';
import 'leave_expansion.dart';

/// Payslip fields the dashboard needs, flattened with the run's `pay_date`
/// (which lives on payroll_runs, not payslips).
class DashboardPayslip {
  final String employeeId;
  final DateTime payDate;
  final Decimal grossPay;
  final Decimal sssEe;
  final Decimal philhealthEe;
  final Decimal pagibigEe;
  final Decimal withholdingTax;

  const DashboardPayslip({
    required this.employeeId,
    required this.payDate,
    required this.grossPay,
    required this.sssEe,
    required this.philhealthEe,
    required this.pagibigEe,
    required this.withholdingTax,
  });
}

/// Everything the dashboard fetched for one calendar year. [employees]
/// deliberately INCLUDES soft-deleted rows: separating an employee can stamp
/// `deleted_at`, so filtering them out here would hide the separations we
/// need to report. `isActiveAsOf` does the filtering that headcount wants.
class DashboardYearInput {
  final int year;
  final List<Employee> employees;
  final Map<String, RoleScorecard> scorecardsById;
  final Map<String, ShiftTemplate> shiftsById;
  final Map<String, String> departmentNames; // departmentId -> name
  final Map<String, String> hiringEntityNames; // hiringEntityId -> name
  final Map<String, CalendarEvent> holidaysByDate; // iso yyyy-MM-dd -> event
  final List<AttendanceDay> attendance;
  final List<LeaveDayAllocation> leaveDays;
  final List<DashboardPayslip> payslips;
  final List<Applicant> applicants;
  final DateTime today;

  const DashboardYearInput({
    required this.year,
    required this.employees,
    required this.scorecardsById,
    required this.shiftsById,
    required this.departmentNames,
    required this.hiringEntityNames,
    required this.holidaysByDate,
    required this.attendance,
    required this.leaveDays,
    required this.payslips,
    required this.applicants,
    required this.today,
  });
}

/// Period-scoped metrics for one month, or for a whole year when [month] is
/// null. Only additive, period-scoped figures live here — headcount, tenure
/// and employment-type distributions are point-in-time snapshots that do not
/// sum across months, so they live in [SnapshotMetrics] instead.
class MonthMetrics {
  final int year;
  final int? month; // 1..12; null = full-year aggregate

  // Attendance — all delegated to AttendanceStats (the payroll engine).
  final int workDays;
  final int presentDays;
  final int absentDays;
  final int restDays;
  final int regularHolidays;
  final int specialHolidays;
  final double lateUndertimeMinutes; // net of OT absorption
  final double overtimeMinutes; // net of late absorption

  // Leave — from leave_requests, not attendance rows.
  final double leaveDays;
  final Map<String, double> leaveDaysByType;

  // Movement — from employees.hire_date / separation_date.
  final int newHires;
  final int separations;
  final int voluntarySeparations;
  final int involuntarySeparations;

  // Payroll — RELEASED payslips bucketed by pay_date.
  final Decimal payrollGross;
  final Decimal sssTotal;
  final Decimal philhealthTotal;
  final Decimal pagibigTotal;
  final Decimal withholdingTaxTotal;

  /// Distinct employees paid in this period. Stored as a set, not a count,
  /// so the year aggregate can UNION rather than sum — an employee paid in
  /// twelve months is one employee, not twelve.
  final Set<String> payrollEmployeeIds;

  final int newApplicants;

  const MonthMetrics({
    required this.year,
    required this.month,
    required this.workDays,
    required this.presentDays,
    required this.absentDays,
    required this.restDays,
    required this.regularHolidays,
    required this.specialHolidays,
    required this.lateUndertimeMinutes,
    required this.overtimeMinutes,
    required this.leaveDays,
    required this.leaveDaysByType,
    required this.newHires,
    required this.separations,
    required this.voluntarySeparations,
    required this.involuntarySeparations,
    required this.payrollGross,
    required this.sssTotal,
    required this.philhealthTotal,
    required this.pagibigTotal,
    required this.withholdingTaxTotal,
    required this.payrollEmployeeIds,
    required this.newApplicants,
  });

  /// Present out of the days the employee was expected in and NOT on leave.
  /// AttendanceStats only increments present/absent on non-leave work days,
  /// so this denominator cannot be polluted by leave or by a work day
  /// carrying some other status.
  double get attendanceRatePct {
    final chargeable = presentDays + absentDays;
    if (chargeable <= 0) return 0;
    return (presentDays / chargeable) * 100.0;
  }

  /// Late/UT spread over every scheduled work day. The old "avg late minutes"
  /// divided by the number of *late samples*, so it went UP when fewer people
  /// were late.
  double get avgLateMinutesPerWorkDay {
    if (workDays <= 0) return 0;
    return lateUndertimeMinutes / workDays;
  }

  double get overtimeHours => overtimeMinutes / 60.0;

  int get payrollEmployeeCount => payrollEmployeeIds.length;

  Decimal get avgGrossPerEmployee {
    final n = payrollEmployeeIds.length;
    if (n == 0) return Decimal.zero;
    return (payrollGross / Decimal.fromInt(n)).toDecimal(
      scaleOnInfinitePrecision: 2,
    );
  }

  bool get isEmpty =>
      workDays == 0 &&
      presentDays == 0 &&
      absentDays == 0 &&
      leaveDays == 0 &&
      newHires == 0 &&
      separations == 0 &&
      payrollGross == Decimal.zero;
}

/// Point-in-time distributions, valid only "as of" a given date.
class SnapshotMetrics {
  final DateTime asOf;
  final int activeEmployees;
  final int totalEmployees;
  final double avgTenureMonths;
  final Map<String, int> headcountByDepartment;
  final Map<String, int> employmentTypeCounts;
  final Map<String, int> hiringEntityCounts;
  final Map<String, int> tenureBuckets;

  const SnapshotMetrics({
    required this.asOf,
    required this.activeEmployees,
    required this.totalEmployees,
    required this.avgTenureMonths,
    required this.headcountByDepartment,
    required this.employmentTypeCounts,
    required this.hiringEntityCounts,
    required this.tenureBuckets,
  });
}

const _kVoluntary = {'RESIGNED', 'RETIRED'};

/// AWOL is treated as employer-side: in practice abandonment resolves to
/// termination for cause.
const _kInvoluntary = {'TERMINATED', 'END_OF_CONTRACT', 'AWOL', 'DECEASED'};

/// An employee counts toward headcount "as of" [asOf] when they were hired on
/// or before that date and had not yet separated. Rows that were
/// administratively archived (`deleted_at`) without ever being separated are
/// excluded — those are data cleanups, not people.
bool isActiveAsOf(Employee e, DateTime asOf) {
  final hire = DateTime(e.hireDate.year, e.hireDate.month, e.hireDate.day);
  final d = DateTime(asOf.year, asOf.month, asOf.day);
  if (hire.isAfter(d)) return false;
  final sep = e.separationDate;
  if (sep != null) {
    final s = DateTime(sep.year, sep.month, sep.day);
    // `!isBefore` (>=), NOT `isAfter` (>). The separation date is the
    // employee's LAST DAY — they are still active ON it, and only inactive
    // from the day AFTER. Rewriting this as `s.isAfter(d)` looks equivalent
    // but silently drops every employee from the headcount snapshot taken on
    // their own final day. Do not "simplify" it back.
    return !s.isBefore(d);
  }
  return e.deletedAt == null;
}

/// An archived row with no separation date is a data cleanup, not a person —
/// it must not accrue work days or count as a hire. (Employees archived AS
/// PART OF separation keep their separation_date and DO still count, in the
/// month they left.)
bool _isRealEmployee(Employee e) =>
    e.deletedAt == null || e.separationDate != null;

double _tenureMonths(DateTime hire, DateTime asOf) =>
    asOf.difference(hire).inDays / 30.4375;

String _tenureBucket(double months) {
  if (months < 12) return '< 1 year';
  if (months < 24) return '1-2 years';
  if (months < 60) return '2-5 years';
  return '5+ years';
}

/// Department name for an employee. The role scorecard's department is the
/// source of truth for "who belongs where"; fall back to the employee's own
/// link, then 'Unassigned'.
String _departmentNameFor(Employee e, DashboardYearInput input) {
  final scId = e.roleScorecardId;
  if (scId != null) {
    final deptId = input.scorecardsById[scId]?.departmentId;
    if (deptId != null) {
      final name = input.departmentNames[deptId];
      if (name != null) return name;
    }
  }
  final own = e.departmentId;
  if (own != null) {
    final name = input.departmentNames[own];
    if (name != null) return name;
  }
  return 'Unassigned';
}

/// Bucket a year's raw data into 12 months. Index 0 is January.
///
/// Attendance is NOT recomputed here — it is delegated to
/// `buildAttendanceRows` + `AttendanceStats.from`, the same engine the
/// payslip PDF and the employee Attendance tab use. That is the whole point:
/// a figure on this dashboard must equal the figure on the payslip.
List<MonthMetrics> computeMonthMetrics(DashboardYearInput input) {
  final year = input.year;
  final yearStart = DateTime(year, 1, 1);
  final yearEnd = DateTime(year, 12, 31);
  final today = DateTime(input.today.year, input.today.month, input.today.day);

  // Per-month accumulators.
  final workDays = List<int>.filled(12, 0);
  final present = List<int>.filled(12, 0);
  final absent = List<int>.filled(12, 0);
  final rest = List<int>.filled(12, 0);
  final regHol = List<int>.filled(12, 0);
  final specHol = List<int>.filled(12, 0);
  final lateMin = List<double>.filled(12, 0);
  final otMin = List<double>.filled(12, 0);
  final leave = List<double>.filled(12, 0);
  final leaveByType = List.generate(12, (_) => <String, double>{});
  final hires = List<int>.filled(12, 0);
  final seps = List<int>.filled(12, 0);
  final vol = List<int>.filled(12, 0);
  final invol = List<int>.filled(12, 0);
  final gross = List<Decimal>.filled(12, Decimal.zero);
  final sss = List<Decimal>.filled(12, Decimal.zero);
  final ph = List<Decimal>.filled(12, Decimal.zero);
  final pg = List<Decimal>.filled(12, Decimal.zero);
  final wh = List<Decimal>.filled(12, Decimal.zero);
  final payEmp = List.generate(12, (_) => <String>{});
  final applicants = List<int>.filled(12, 0);

  // ---- Attendance, per employee, over their employment window ----
  final byEmployee = <String, List<AttendanceDay>>{};
  for (final r in input.attendance) {
    (byEmployee[r.employeeId] ??= []).add(r);
  }

  for (final e in input.employees) {
    if (!_isRealEmployee(e)) continue;
    final sc = e.roleScorecardId == null
        ? null
        : input.scorecardsById[e.roleScorecardId!];
    final workDaysPerWeek = sc?.workDaysPerWeek;
    final defaultShift = sc?.shiftTemplateId == null
        ? null
        : input.shiftsById[sc!.shiftTemplateId!];

    // Clip the window to employment. Without this, a July hire would accrue
    // six months of scheduled-but-absent days.
    final hire = DateTime(e.hireDate.year, e.hireDate.month, e.hireDate.day);
    var start = hire.isAfter(yearStart) ? hire : yearStart;
    var end = yearEnd;
    final sep = e.separationDate;
    if (sep != null) {
      final s = DateTime(sep.year, sep.month, sep.day);
      if (s.isBefore(end)) end = s;
    }
    if (today.isBefore(end)) end = today;
    if (end.isBefore(start)) continue;

    final rows = buildAttendanceRows(
      start: start,
      end: end,
      records: byEmployee[e.id] ?? const [],
      shifts: input.shiftsById,
      holidays: input.holidaysByDate,
      defaultShift: defaultShift,
      workDaysPerWeek: workDaysPerWeek,
      // input.today is authoritative and already clips `end` above; the
      // wall-clock cutoff inside buildAttendanceRows would be redundant at
      // best and, in tests, a silent dependency on the real clock.
      skipFutureDays: false,
    );

    // Group this employee's rows by month, then hand each month's rows to
    // AttendanceStats so its work-day / holiday / rest-day rules apply.
    final rowsByMonth = List.generate(12, (_) => <AttendanceRowVm>[]);
    for (final row in rows) {
      rowsByMonth[row.date.month - 1].add(row);
    }
    for (var m = 0; m < 12; m++) {
      if (rowsByMonth[m].isEmpty) continue;
      final st = AttendanceStats.from(
        rowsByMonth[m],
        workDaysPerWeek: workDaysPerWeek,
      );
      workDays[m] += st.workDays;
      present[m] += st.present;
      absent[m] += st.absent;
      rest[m] += st.restDays;
      regHol[m] += st.regularHoliday;
      specHol[m] += st.specialHoliday;
      lateMin[m] += st.lateUndertimeMinutes;
      otMin[m] += st.otMinutes;
    }
  }

  // ---- Leave (already expanded to per-date allocations) ----
  for (final a in input.leaveDays) {
    if (a.date.year != year) continue;
    final m = a.date.month - 1;
    leave[m] += a.days;
    leaveByType[m][a.leaveType] = (leaveByType[m][a.leaveType] ?? 0) + a.days;
  }

  // ---- Movement, from employees (NOT employment_events) ----
  for (final e in input.employees) {
    if (!_isRealEmployee(e)) continue;
    if (e.hireDate.year == year) hires[e.hireDate.month - 1]++;
    final sep = e.separationDate;
    final status = e.employmentStatus.toUpperCase();
    if (sep != null && sep.year == year && status != 'ACTIVE') {
      final m = sep.month - 1;
      seps[m]++;
      if (_kVoluntary.contains(status)) {
        vol[m]++;
      } else if (_kInvoluntary.contains(status)) {
        invol[m]++;
      }
    }
  }

  // ---- Payroll ----
  for (final p in input.payslips) {
    if (p.payDate.year != year) continue;
    final m = p.payDate.month - 1;
    gross[m] += p.grossPay;
    sss[m] += p.sssEe;
    ph[m] += p.philhealthEe;
    pg[m] += p.pagibigEe;
    wh[m] += p.withholdingTax;
    payEmp[m].add(p.employeeId);
  }

  // ---- Applicants ----
  for (final a in input.applicants) {
    if (a.appliedAt.year == year) applicants[a.appliedAt.month - 1]++;
  }

  return [
    for (var m = 0; m < 12; m++)
      MonthMetrics(
        year: year,
        month: m + 1,
        workDays: workDays[m],
        presentDays: present[m],
        absentDays: absent[m],
        restDays: rest[m],
        regularHolidays: regHol[m],
        specialHolidays: specHol[m],
        lateUndertimeMinutes: lateMin[m],
        overtimeMinutes: otMin[m],
        leaveDays: leave[m],
        leaveDaysByType: Map.unmodifiable(leaveByType[m]),
        newHires: hires[m],
        separations: seps[m],
        voluntarySeparations: vol[m],
        involuntarySeparations: invol[m],
        payrollGross: gross[m],
        sssTotal: sss[m],
        philhealthTotal: ph[m],
        pagibigTotal: pg[m],
        withholdingTaxTotal: wh[m],
        payrollEmployeeIds: Set.unmodifiable(payEmp[m]),
        newApplicants: applicants[m],
      ),
  ];
}

/// Roll 12 months into the year total. Everything additive sums; payroll
/// employees UNION (one person paid in twelve months is one person).
MonthMetrics aggregateMonths(List<MonthMetrics> months, int year) {
  final leaveByType = <String, double>{};
  final payEmp = <String>{};
  var workDays = 0,
      present = 0,
      absent = 0,
      rest = 0,
      regHol = 0,
      specHol = 0,
      hires = 0,
      seps = 0,
      vol = 0,
      invol = 0,
      applicants = 0;
  var lateMin = 0.0, otMin = 0.0, leave = 0.0;
  var gross = Decimal.zero,
      sss = Decimal.zero,
      ph = Decimal.zero,
      pg = Decimal.zero,
      wh = Decimal.zero;

  for (final m in months) {
    workDays += m.workDays;
    present += m.presentDays;
    absent += m.absentDays;
    rest += m.restDays;
    regHol += m.regularHolidays;
    specHol += m.specialHolidays;
    lateMin += m.lateUndertimeMinutes;
    otMin += m.overtimeMinutes;
    leave += m.leaveDays;
    m.leaveDaysByType.forEach((k, v) {
      leaveByType[k] = (leaveByType[k] ?? 0) + v;
    });
    hires += m.newHires;
    seps += m.separations;
    vol += m.voluntarySeparations;
    invol += m.involuntarySeparations;
    gross += m.payrollGross;
    sss += m.sssTotal;
    ph += m.philhealthTotal;
    pg += m.pagibigTotal;
    wh += m.withholdingTaxTotal;
    payEmp.addAll(m.payrollEmployeeIds);
    applicants += m.newApplicants;
  }

  return MonthMetrics(
    year: year,
    month: null,
    workDays: workDays,
    presentDays: present,
    absentDays: absent,
    restDays: rest,
    regularHolidays: regHol,
    specialHolidays: specHol,
    lateUndertimeMinutes: lateMin,
    overtimeMinutes: otMin,
    leaveDays: leave,
    leaveDaysByType: Map.unmodifiable(leaveByType),
    newHires: hires,
    separations: seps,
    voluntarySeparations: vol,
    involuntarySeparations: invol,
    payrollGross: gross,
    sssTotal: sss,
    philhealthTotal: ph,
    pagibigTotal: pg,
    withholdingTaxTotal: wh,
    payrollEmployeeIds: Set.unmodifiable(payEmp),
    newApplicants: applicants,
  );
}

/// Point-in-time distributions as of [asOf].
SnapshotMetrics computeSnapshot(DashboardYearInput input, DateTime asOf) {
  final dept = <String, int>{};
  final type = <String, int>{};
  final entity = <String, int>{};
  final tenure = <String, int>{
    '< 1 year': 0,
    '1-2 years': 0,
    '2-5 years': 0,
    '5+ years': 0,
  };
  final tenures = <double>[];
  var active = 0;

  for (final e in input.employees) {
    if (!isActiveAsOf(e, asOf)) continue;
    active++;

    final months = _tenureMonths(e.hireDate, asOf);
    tenures.add(months);
    final bucket = _tenureBucket(months);
    tenure[bucket] = (tenure[bucket] ?? 0) + 1;

    final deptName = _departmentNameFor(e, input);
    dept[deptName] = (dept[deptName] ?? 0) + 1;

    final t = e.employmentType.isEmpty ? 'UNKNOWN' : e.employmentType;
    type[t] = (type[t] ?? 0) + 1;

    final entId = e.hiringEntityId;
    final entName =
        (entId == null ? null : input.hiringEntityNames[entId]) ?? 'Unassigned';
    entity[entName] = (entity[entName] ?? 0) + 1;
  }

  final avgTenure = tenures.isEmpty
      ? 0.0
      : tenures.reduce((a, b) => a + b) / tenures.length;

  return SnapshotMetrics(
    asOf: asOf,
    activeEmployees: active,
    // "Total" = every non-archived employee row, separated or not.
    totalEmployees: input.employees.where((e) => e.deletedAt == null).length,
    avgTenureMonths: avgTenure,
    headcountByDepartment: Map.unmodifiable(dept),
    employmentTypeCounts: Map.unmodifiable(type),
    hiringEntityCounts: Map.unmodifiable(entity),
    tenureBuckets: Map.unmodifiable(tenure),
  );
}
