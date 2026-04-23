import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/profile_provider.dart';

/// Dashboard's selected year. Drives every yearly aggregation on the
/// screen (Payroll Summary, Employee Movement totals, Attendance Overview
/// period). Defaults to the current calendar year; the Dashboard header
/// exposes a dropdown so HR can audit prior years.
final dashboardYearProvider =
    StateProvider<int>((ref) => DateTime.now().year);

/// Aggregated dashboard snapshot for the selected period (default: current
/// calendar month). All counts/amounts are computed on the server via single
/// scoped queries; we fan out queries in parallel and assemble the snapshot
/// here so the screen only watches one provider.
class DashboardData {
  // Workforce
  final int activeEmployees;
  final int totalEmployees;
  final double avgTenureMonths;
  final Map<String, int> headcountByDepartment;
  final Map<String, int> employmentTypeCounts;
  final Map<String, int> hiringEntityCounts;
  final Map<String, int> tenureBuckets; // <1 year, 1-2, 2-5, 5+

  // Recruitment
  final int openPositions;
  final int newApplicantsThisMonth;

  // Attendance (period)
  final int attendanceTotal;
  final int attendancePresent;
  final int attendanceAbsent;
  final int attendanceOnLeave;
  final int attendanceRestDay;
  final double attendanceRatePct;
  final double overtimeHours;
  final int avgLateMinutes;

  // Payroll (latest finalized run within period; falls back to most recent)
  final Decimal totalPayrollCost;
  final Decimal avgSalary;
  final Decimal sssTotal;
  final Decimal philhealthTotal;
  final Decimal pagibigTotal;
  final Decimal withholdingTaxTotal;

  // Movement
  final int newHiresThisMonth;
  final int separationsThisMonth;
  final int voluntaryYtd;
  final int involuntaryYtd;

  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime generatedAt;

  const DashboardData({
    required this.activeEmployees,
    required this.totalEmployees,
    required this.avgTenureMonths,
    required this.headcountByDepartment,
    required this.employmentTypeCounts,
    required this.hiringEntityCounts,
    required this.tenureBuckets,
    required this.openPositions,
    required this.newApplicantsThisMonth,
    required this.attendanceTotal,
    required this.attendancePresent,
    required this.attendanceAbsent,
    required this.attendanceOnLeave,
    required this.attendanceRestDay,
    required this.attendanceRatePct,
    required this.overtimeHours,
    required this.avgLateMinutes,
    required this.totalPayrollCost,
    required this.avgSalary,
    required this.sssTotal,
    required this.philhealthTotal,
    required this.pagibigTotal,
    required this.withholdingTaxTotal,
    required this.newHiresThisMonth,
    required this.separationsThisMonth,
    required this.voluntaryYtd,
    required this.involuntaryYtd,
    required this.periodStart,
    required this.periodEnd,
    required this.generatedAt,
  });
}

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

double _tenureMonths(DateTime hire, DateTime now) {
  return now.difference(hire).inDays / 30.4375;
}

String _tenureBucket(double months) {
  if (months < 12) return '< 1 year';
  if (months < 24) return '1-2 years';
  if (months < 60) return '2-5 years';
  return '5+ years';
}

final dashboardDataProvider = FutureProvider<DashboardData>((ref) async {
  // IMPORTANT: subscribe to every reactive dependency *before* any await.
  // Riverpod only tracks `ref.watch` calls that execute synchronously on
  // the first pass — watches after an await don't register a subscription,
  // so changes to them never invalidate this provider. That bit us with
  // the year dropdown silently not refiltering.
  final selectedYear = ref.watch(dashboardYearProvider);
  final profile = await ref.watch(userProfileProvider.future);
  final companyId = profile?.companyId;
  if (companyId == null || companyId.isEmpty) {
    throw StateError('No company on profile');
  }

  final client = Supabase.instance.client;
  final now = DateTime.now();
  final isCurrentYear = selectedYear == now.year;
  final periodStart = isCurrentYear
      ? DateTime(now.year, now.month, 1)
      : DateTime(selectedYear, 1, 1);
  final periodEnd = isCurrentYear
      ? DateTime(now.year, now.month + 1, 0)
      : DateTime(selectedYear, 12, 31);
  final ytdStart = DateTime(selectedYear, 1, 1);
  final ytdEnd = DateTime(selectedYear, 12, 31);
  final periodStartIso = _isoDate(periodStart);
  final periodEndIso = _isoDate(periodEnd);
  final ytdStartIso = _isoDate(ytdStart);
  final ytdEndIso = _isoDate(ytdEnd);

  // Payroll summary always spans the selected calendar year; monthly toggle
  // removed per 2026-04 UX pass.
  final payrollStartIso = ytdStartIso;
  final payrollEndIso = ytdEndIso;

  // Run independent queries in parallel.
  final results = await Future.wait<dynamic>([
    // 0: employees — join department through role_scorecards so headcount
    // reflects the currently linked role's department. Falls back to the
    // employee's own department_id when no role is linked.
    client
        .from('employees')
        .select(
            'id, employment_type, employment_status, hire_date, separation_date, '
            'department_id, hiring_entity_id, role_scorecard_id, deleted_at, '
            'departments!employees_department_id_fkey(name), '
            'hiring_entities!employees_hiring_entity_id_fkey(name), '
            'role_scorecards(department_id, departments(name))')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null),
    // 1: applicants — open pipeline + new this month
    client
        .from('applicants')
        .select('id, status, applied_at, deleted_at')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null),
    // 2: attendance for the period (joined to scoped employees)
    client
        .from('attendance_day_records')
        .select(
            'attendance_status, day_type, actual_time_in, actual_time_out, '
            'approved_ot_minutes, employees!inner(company_id)')
        .eq('employees.company_id', companyId)
        .gte('attendance_date', periodStartIso)
        .lte('attendance_date', periodEndIso),
    // 3: payslips aggregated into the payroll KPI tile. Wrapped so a failure
    //    here (e.g. migration 20260418000001 not yet applied → period_* columns
    //    missing on payroll_runs) doesn't take down the whole dashboard.
    _safePayslipsForPeriod(client, companyId, payrollStartIso, payrollEndIso),
    // 4: employment events (movement)
    client
        .from('employment_events')
        .select('event_type, event_date, payload, employees!inner(company_id)')
        .eq('employees.company_id', companyId)
        .gte('event_date', ytdStartIso),
  ], eagerError: false);

  // ---- 0. Employees ----
  final emps = (results[0] as List).cast<Map<String, dynamic>>();
  int active = 0;
  final tenureSum = <double>[];
  final dept = <String, int>{};
  final type = <String, int>{};
  final entity = <String, int>{};
  final tenure = <String, int>{
    '< 1 year': 0,
    '1-2 years': 0,
    '2-5 years': 0,
    '5+ years': 0,
  };
  for (final e in emps) {
    final status = e['employment_status'] as String? ?? '';
    if (status == 'ACTIVE') active++;
    final hire = DateTime.parse(e['hire_date'] as String);
    final monthsT = _tenureMonths(hire, now);
    if (status == 'ACTIVE') {
      tenureSum.add(monthsT);
      tenure[_tenureBucket(monthsT)] = (tenure[_tenureBucket(monthsT)] ?? 0) + 1;
      // Prefer the role scorecard's department — that's the source of truth
      // for "who belongs where". Fall back to the employee's own dept link,
      // then 'Unassigned'.
      final roleCard = e['role_scorecards'] as Map?;
      final roleDeptName = (roleCard?['departments'] as Map?)?['name'] as String?;
      final ownDeptName = (e['departments'] as Map?)?['name'] as String?;
      final deptName = roleDeptName ?? ownDeptName ?? 'Unassigned';
      dept[deptName] = (dept[deptName] ?? 0) + 1;
      final t = (e['employment_type'] as String?) ?? 'UNKNOWN';
      type[t] = (type[t] ?? 0) + 1;
      final entName = (e['hiring_entities'] as Map?)?['name'] as String? ?? 'Unassigned';
      entity[entName] = (entity[entName] ?? 0) + 1;
    }
  }
  final avgTenure = tenureSum.isEmpty
      ? 0.0
      : tenureSum.reduce((a, b) => a + b) / tenureSum.length;

  // ---- 1. Applicants ----
  final applicants = (results[1] as List).cast<Map<String, dynamic>>();
  int openPositions = 0;
  int newApplicants = 0;
  for (final a in applicants) {
    final status = (a['status'] as String? ?? '').toUpperCase();
    final isClosed = status == 'HIRED' ||
        status == 'REJECTED' ||
        status == 'WITHDRAWN' ||
        status == 'OFFER_DECLINED';
    if (!isClosed) openPositions++;
    final applied = DateTime.parse(a['applied_at'] as String);
    if (!applied.isBefore(periodStart) && !applied.isAfter(periodEnd)) {
      newApplicants++;
    }
  }

  // ---- 2. Attendance ----
  final attRows = (results[2] as List).cast<Map<String, dynamic>>();
  int aTotal = 0, aPresent = 0, aAbsent = 0, aLeave = 0, aRestDay = 0;
  int otMinutes = 0;
  int latePresentSamples = 0;
  int lateMinutesSum = 0;
  for (final r in attRows) {
    aTotal++;
    final s = (r['attendance_status'] as String? ?? '').toUpperCase();
    switch (s) {
      case 'PRESENT':
      case 'HALF_DAY':
        aPresent++;
        break;
      case 'ABSENT':
        aAbsent++;
        break;
      case 'ON_LEAVE':
        aLeave++;
        break;
      case 'REST_DAY':
        aRestDay++;
        break;
    }
    final ot = r['approved_ot_minutes'];
    if (ot is int) otMinutes += ot;
    if (ot is num) otMinutes += ot.toInt();

    // Rough "late" sample: clock in after 09:00 local on a workday.
    final inRaw = r['actual_time_in'] as String?;
    final dt = (r['day_type'] as String?)?.toUpperCase();
    if (inRaw != null && dt == 'WORKDAY') {
      final t = DateTime.parse(inRaw).toLocal();
      if (t.hour > 9 || (t.hour == 9 && t.minute > 0)) {
        latePresentSamples++;
        lateMinutesSum +=
            ((t.hour - 9) * 60 + t.minute).clamp(0, 8 * 60);
      }
    }
  }
  // Attendance rate: present out of (total minus rest day & on-leave) — i.e.
  // chargeable working days only.
  final chargeable = aTotal - aRestDay - aLeave;
  final attendanceRate = chargeable <= 0
      ? 0.0
      : (aPresent / chargeable) * 100.0;
  final avgLate = latePresentSamples == 0
      ? 0
      : (lateMinutesSum / latePresentSamples).round();

  // ---- 3. Payroll (sum across payslips for the period) ----
  final payslips = (results[3] as List).cast<Map<String, dynamic>>();
  Decimal d(Object? v) => Decimal.parse((v ?? '0').toString());
  Decimal totalGross = Decimal.zero;
  Decimal sssTot = Decimal.zero;
  Decimal phTot = Decimal.zero;
  Decimal pgTot = Decimal.zero;
  Decimal whTot = Decimal.zero;
  for (final p in payslips) {
    totalGross += d(p['gross_pay']);
    sssTot += d(p['sss_ee']);
    phTot += d(p['philhealth_ee']);
    pgTot += d(p['pagibig_ee']);
    whTot += d(p['withholding_tax']);
  }
  final avgSalary = payslips.isEmpty
      ? Decimal.zero
      : (totalGross / Decimal.fromInt(payslips.length))
          .toDecimal(scaleOnInfinitePrecision: 2);

  // ---- 4. Employment events ----
  // All Employee Movement counts are now yearly (spans the selected year).
  // The "This Month" framing was removed in the 2026-04 dashboard pass.
  final events = (results[4] as List).cast<Map<String, dynamic>>();
  int newHires = 0, separations = 0, voluntary = 0, involuntary = 0;
  for (final ev in events) {
    final t = (ev['event_type'] as String? ?? '').toUpperCase();
    final dStr = ev['event_date'] as String;
    final eventDate = DateTime.parse(dStr);
    final inYear = !eventDate.isBefore(ytdStart) &&
        !eventDate.isAfter(ytdEnd);
    if (!inYear) continue;
    if (t == 'HIRE' || t == 'NEW_HIRE') {
      newHires++;
    } else if (t == 'SEPARATION' ||
        t == 'TERMINATION' ||
        t == 'RESIGNATION' ||
        t == 'END_OF_CONTRACT') {
      separations++;
      final payload = ev['payload'] as Map<String, dynamic>? ?? const {};
      final kind = (payload['kind'] as String? ?? t).toUpperCase();
      if (t == 'RESIGNATION' || kind.contains('VOLUNTARY')) {
        voluntary++;
      } else {
        involuntary++;
      }
    }
  }

  return DashboardData(
    activeEmployees: active,
    totalEmployees: emps.length,
    avgTenureMonths: avgTenure,
    headcountByDepartment: dept,
    employmentTypeCounts: type,
    hiringEntityCounts: entity,
    tenureBuckets: tenure,
    openPositions: openPositions,
    newApplicantsThisMonth: newApplicants,
    attendanceTotal: aTotal,
    attendancePresent: aPresent,
    attendanceAbsent: aAbsent,
    attendanceOnLeave: aLeave,
    attendanceRestDay: aRestDay,
    attendanceRatePct: attendanceRate,
    overtimeHours: otMinutes / 60.0,
    avgLateMinutes: avgLate,
    totalPayrollCost: totalGross,
    avgSalary: avgSalary,
    sssTotal: sssTot,
    philhealthTotal: phTot,
    pagibigTotal: pgTot,
    withholdingTaxTotal: whTot,
    newHiresThisMonth: newHires,
    separationsThisMonth: separations,
    voluntaryYtd: voluntary,
    involuntaryYtd: involuntary,
    periodStart: periodStart,
    periodEnd: periodEnd,
    generatedAt: DateTime.now(),
  );
});

/// Defensive payslip fetch for RELEASED runs whose pay_date falls inside
/// the given range. Joins through payroll_runs so the company + status
/// filter is enforced server-side. Swallows join-shape failures (older
/// schemas missing `period_start` / `pay_date`) so the rest of the
/// dashboard still renders with 0-valued payroll KPIs.
Future<List<dynamic>> _safePayslipsForPeriod(
  SupabaseClient client,
  String companyId,
  String periodStartIso,
  String periodEndIso,
) async {
  try {
    return await client
        .from('payslips')
        .select(
            'gross_pay, total_deductions, sss_ee, philhealth_ee, pagibig_ee, '
            'withholding_tax, '
            'payroll_runs!inner(company_id, status, pay_date)')
        .eq('payroll_runs.company_id', companyId)
        .eq('payroll_runs.status', 'RELEASED')
        .gte('payroll_runs.pay_date', periodStartIso)
        .lte('payroll_runs.pay_date', periodEndIso) as List<dynamic>;
  } catch (_) {
    return const <dynamic>[];
  }
}
