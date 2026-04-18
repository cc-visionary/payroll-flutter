import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/payroll_run.dart';
import '../../../../data/repositories/payroll_repository.dart';

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
