/// Pure roster math for editing which employees a payroll run covers.
///
/// The run's roster lives in `payroll_runs.included_employee_ids`, whose
/// semantics have one sharp edge (see migration 20260416000004):
///
///   NULL / []  → compute for ALL active employees of the company
///   [...]      → compute only for those ids
///
/// So "remove one person" is never a subtraction from the stored column: when
/// the column is null we must first materialize the concrete list of active
/// employees, THEN subtract. Writing an empty array back would flip the run to
/// the catch-all and silently re-add everybody on the next recompute — which is
/// why [rosterAfterRemoval] refuses to remove the last employee.
///
/// Everything here is pure so it can be tested without Supabase; the
/// repository does the reads and writes.
library;

import 'package:decimal/decimal.dart';

/// Raised when an edit would leave the run in an incoherent state.
/// The message is user-facing — it goes straight into a SnackBar.
class RosterEditException implements Exception {
  final String message;
  const RosterEditException(this.message);
  @override
  String toString() => message;
}

/// The run's roster as a concrete list of employee ids.
///
/// [included] is the stored `included_employee_ids` column; [allActiveIds] is
/// every employee eligible for the run today. A null/empty column materializes
/// to the full active list. An explicit roster is intersected with the active
/// list so an employee archived since the run was created is not resurrected
/// by us rewriting the column.
List<String> effectiveRoster({
  required List<String>? included,
  required List<String> allActiveIds,
}) {
  if (included == null || included.isEmpty) {
    return _dedupe(allActiveIds);
  }
  final active = allActiveIds.toSet();
  return _dedupe(included.where(active.contains));
}

/// The roster with [employeeId] taken out.
///
/// Throws [RosterEditException] when the employee isn't on the roster, or when
/// removing them would empty it.
List<String> rosterAfterRemoval({
  required List<String> roster,
  required String employeeId,
}) {
  if (!roster.contains(employeeId)) {
    throw const RosterEditException(
      'That employee is not part of this payroll run.',
    );
  }
  if (roster.length <= 1) {
    throw const RosterEditException(
      'Cannot remove the last employee from a run — cancel the run instead.',
    );
  }
  return [
    for (final id in roster)
      if (id != employeeId) id,
  ];
}

/// The roster with [employeeIds] appended, skipping any already on it.
///
/// Throws [RosterEditException] when nothing would actually be added.
List<String> rosterAfterAdditions({
  required List<String> roster,
  required Iterable<String> employeeIds,
}) {
  final existing = roster.toSet();
  final fresh = _dedupe(employeeIds.where((id) => !existing.contains(id)));
  if (fresh.isEmpty) {
    throw const RosterEditException('No new employees to add.');
  }
  return [...roster, ...fresh];
}

/// Whether a payslip is frozen because it is live in a Lark approval.
///
/// Mirrors [PayrollComputeService]'s recompute rule exactly: recalling an
/// approval sets `lark_approval_status` back to NULL, so ANY value means the
/// payslip is still out there. Removing such an employee would delete a
/// payslip Lark still references — the user must recall it first.
bool isLarkFrozen(String? larkApprovalStatus) => larkApprovalStatus != null;

/// Run-level money totals, re-summed from the payslips that remain.
class RunTotals {
  final Decimal gross;
  final Decimal deductions;
  final Decimal net;
  final int count;
  const RunTotals({
    required this.gross,
    required this.deductions,
    required this.net,
    required this.count,
  });
}

/// Re-derive the run's totals from its payslip rows.
///
/// Used after a removal so `payroll_runs` matches the sum of on-disk payslips
/// without paying for a full recompute — dropping one employee cannot change
/// anybody else's numbers.
RunTotals sumTotals(List<Map<String, dynamic>> payslipRows) {
  var gross = Decimal.zero;
  var deductions = Decimal.zero;
  var net = Decimal.zero;
  for (final r in payslipRows) {
    gross += _dec(r['gross_pay']);
    deductions += _dec(r['total_deductions']);
    net += _dec(r['net_pay']);
  }
  return RunTotals(
    gross: gross,
    deductions: deductions,
    net: net,
    count: payslipRows.length,
  );
}

Decimal _dec(Object? v) =>
    v == null ? Decimal.zero : (Decimal.tryParse(v.toString()) ?? Decimal.zero);

List<String> _dedupe(Iterable<String> ids) {
  final seen = <String>{};
  return [
    for (final id in ids)
      if (seen.add(id)) id,
  ];
}
