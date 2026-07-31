import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/payroll_run.dart';
import '../../../../data/repositories/payroll_repository.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../../data/repositories/shift_template_repository.dart';
import '../../leave/paid_leave_matcher.dart';
import 'warnings.dart';

/// Bundles the payroll run + aggregated statutory totals. Period fields are
/// read directly from `run` now that pay_periods has been dropped.
class PayrollRunDetail {
  final PayrollRun run;
  final int payslipCount;
  final Decimal totalSssEe;
  final Decimal totalSssEr;
  final Decimal totalPhilhealthEe;
  final Decimal totalPhilhealthEr;
  final Decimal totalPagibigEe;
  final Decimal totalPagibigEr;
  final Decimal totalWithholdingTax;
  const PayrollRunDetail({
    required this.run,
    required this.payslipCount,
    required this.totalSssEe,
    required this.totalSssEr,
    required this.totalPhilhealthEe,
    required this.totalPhilhealthEr,
    required this.totalPagibigEe,
    required this.totalPagibigEr,
    required this.totalWithholdingTax,
  });

  String get payPeriodCode =>
      '${_iso(run.periodStart)} - ${_iso(run.periodEnd)}';
  DateTime get payPeriodStart => run.periodStart;
  DateTime get payPeriodEnd => run.periodEnd;
  DateTime get payDate => run.payDate;

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);
}

Decimal _dec(Object? v) => Decimal.parse((v ?? '0').toString());

final payrollRunDetailProvider =
    FutureProvider.family<PayrollRunDetail?, String>((ref, runId) async {
  final repo = ref.watch(payrollRepositoryProvider);
  final run = await repo.byId(runId);
  if (run == null) return null;

  // Aggregate statutory totals from the payslips table (cheap: one query).
  final payslips = await repo.payslipsByRun(runId);
  var sssEe = Decimal.zero,
      sssEr = Decimal.zero,
      phEe = Decimal.zero,
      phEr = Decimal.zero,
      piEe = Decimal.zero,
      piEr = Decimal.zero,
      tax = Decimal.zero;
  for (final p in payslips) {
    sssEe += p.sssEe;
    phEe += p.philhealthEe;
    piEe += p.pagibigEe;
    tax += p.withholdingTax;
  }

  // Employer shares aren't on the model; pull them raw so the Summary tab
  // can show EE/ER pairs just like payrollos.
  // (A dedicated query keeps this tab cheap; listRun already returned the
  // row data but not ER fields.)
  // Grab them in one fly-by via REST.
  // We re-use payslipListForRun which already pulls all payslip columns.
  final raw = await repo.payslipListForRun(runId);
  for (final r in raw) {
    sssEr += _dec(r['sss_er']);
    phEr += _dec(r['philhealth_er']);
    piEr += _dec(r['pagibig_er']);
  }

  return PayrollRunDetail(
    run: run,
    payslipCount: payslips.length,
    totalSssEe: sssEe,
    totalSssEr: sssEr,
    totalPhilhealthEe: phEe,
    totalPhilhealthEr: phEr,
    totalPagibigEe: piEe,
    totalPagibigEr: piEr,
    totalWithholdingTax: tax,
  );
});

final payslipListForRunProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, runId) {
  return ref.watch(payrollRepositoryProvider).payslipListForRun(runId);
});

final larkApprovalCountsProvider =
    FutureProvider.family<Map<String, int>, String>((ref, runId) {
  return ref.watch(payrollRepositoryProvider).larkApprovalCounts(runId);
});

/// Live, ephemeral attendance-anomaly scan for a run. Reads the run's company +
/// period, loads that period's attendance and the shift templates, and runs the
/// pure [detectWarnings]. Re-runs whenever [payrollRunDetailProvider] changes
/// (recompute / realtime) or when invalidated by the tab's Refresh button.
final runWarningsProvider =
    FutureProvider.family<List<RunWarning>, String>((ref, runId) async {
  final detail = await ref.watch(payrollRunDetailProvider(runId).future);
  if (detail == null) return const <RunWarning>[];
  final run = detail.run;
  final records = await ref.watch(attendanceRepositoryProvider).listByRange(
        start: run.periodStart,
        end: run.periodEnd,
        companyId: run.companyId,
      );
  final shifts = await ref.watch(shiftTemplateListProvider.future);
  final shiftsById = {for (final s in shifts) s.id: s};
  final approvedLeavesByEmployee = await _fetchApprovedLeavesByEmployee(
    companyId: run.companyId,
    periodStart: run.periodStart,
    periodEnd: run.periodEnd,
  );
  return detectWarnings(
    records: records,
    shiftsById: shiftsById,
    today: DateTime.now(),
    approvedLeavesByEmployee: approvedLeavesByEmployee,
  );
});

/// APPROVED leave requests (paid or unpaid) overlapping the run's period,
/// grouped by employee — feeds [WarningType.leaveWithoutApprovedRequest].
/// Mirrors the per-employee query shape in `PayrollComputeService`
/// (compute_service.dart) but scoped to the whole company/run instead of one
/// employee, then grouped client-side by `employee_id`.
Future<Map<String, List<ApprovedLeaveDay>>> _fetchApprovedLeavesByEmployee({
  required String companyId,
  required DateTime periodStart,
  required DateTime periodEnd,
}) async {
  final rows = await Supabase.instance.client
      .from('leave_requests')
      .select('employee_id, start_date, end_date, leave_days, '
          'leave_types!inner(is_paid, name, code), employees!inner(company_id)')
      .eq('employees.company_id', companyId)
      .eq('status', 'APPROVED')
      .lte('start_date', periodEnd.toIso8601String().substring(0, 10))
      .gte('end_date', periodStart.toIso8601String().substring(0, 10));

  final out = <String, List<ApprovedLeaveDay>>{};
  for (final r in (rows as List).cast<Map<String, dynamic>>()) {
    final employeeId = r['employee_id'] as String;
    final types = r['leave_types'] as Map<String, dynamic>?;
    out.putIfAbsent(employeeId, () => []).add(ApprovedLeaveDay(
          start: DateTime.parse(r['start_date'] as String),
          end: DateTime.parse(r['end_date'] as String),
          isPaid: types?['is_paid'] as bool? ?? false,
          typeName: (types?['name'] as String?) ??
              (types?['code'] as String?) ??
              'Leave',
          leaveDays: Decimal.tryParse((r['leave_days'] ?? '1').toString()) ??
              Decimal.one,
        ));
  }
  return out;
}
