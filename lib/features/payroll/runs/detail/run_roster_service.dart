import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/payroll_run.dart';
import 'run_roster.dart';

/// Reads and writes a payroll run's employee roster
/// (`payroll_runs.included_employee_ids`) after the run has been created.
///
/// Lives beside [PayrollComputeService] rather than in `PayrollRepository`
/// because it is run-detail orchestration, not a plain table accessor: every
/// method here reads, applies the pure rules in `run_roster.dart`, and writes
/// several tables back. All the decision-making is in those pure functions —
/// this class only does I/O.
class PayrollRosterService {
  final SupabaseClient _client;
  PayrollRosterService(this._client);

  /// Statuses whose roster may still be edited. A RELEASED run is final and a
  /// CANCELLED one is moot; both are also filtered out in the UI, this is the
  /// backstop.
  static const _editableStatuses = {'DRAFT', 'REVIEW'};

  /// Employees the compute engine would consider for [run] before
  /// `included_employee_ids` narrows the set. Mirrors the filters in
  /// [PayrollComputeService.computeRun] — active, not soft-deleted, hired on
  /// or before the period end. An employee hired after the period end would be
  /// skipped by the engine, so offering them in the picker would produce a
  /// roster entry that never grows a payslip.
  Future<List<Map<String, dynamic>>> _eligibleEmployees(PayrollRun run) async {
    final periodEndIso = run.periodEnd.toIso8601String().substring(0, 10);
    final rows = await _client
        .from('employees')
        .select('id, employee_number, first_name, middle_name, last_name')
        .eq('company_id', run.companyId)
        .eq('employment_status', 'ACTIVE')
        .isFilter('deleted_at', null)
        .lte('hire_date', periodEndIso);
    final out = (rows as List<dynamic>).cast<Map<String, dynamic>>();
    out.sort(_byEmployeeNumber);
    return out;
  }

  /// The run's roster as a concrete list of employee ids, materializing the
  /// "all active employees" catch-all when [stored] is null/empty.
  ///
  /// [stored] always comes from a fresh read of the row, never from the
  /// caller's [PayrollRun]: that model is a snapshot, and two removals in
  /// quick succession would otherwise compute the second from the pre-first
  /// roster and silently resurrect the first employee.
  List<String> _rosterOf(
    List<String>? stored,
    List<Map<String, dynamic>> eligible,
  ) => effectiveRoster(
    included: stored,
    allActiveIds: [for (final e in eligible) e['id'] as String],
  );

  /// The run's live `status` + `included_employee_ids`, straight from the row.
  Future<({String status, List<String>? included})> _readRunRow(
    String runId,
  ) async {
    final row = await _client
        .from('payroll_runs')
        .select('status, included_employee_ids')
        .eq('id', runId)
        .single();
    return (
      status: row['status'] as String,
      included: switch (row['included_employee_ids']) {
        final List<dynamic> ids => ids.whereType<String>().toList(),
        _ => null,
      },
    );
  }

  Future<List<String>?> _storedRoster(String runId) async =>
      (await _readRunRow(runId)).included;

  /// Employees who could be added to [run] but are not on its roster today.
  /// Feeds the "Add Employee" picker.
  Future<List<Map<String, dynamic>>> employeesEligibleToAdd(
    PayrollRun run,
  ) async {
    final eligible = await _eligibleEmployees(run);
    final roster = _rosterOf(await _storedRoster(run.id), eligible).toSet();
    return [
      for (final e in eligible)
        if (!roster.contains(e['id'] as String)) e,
    ];
  }

  /// Drop [employeeId] from the run: rewrite the roster so a later recompute
  /// does not bring them back, delete their payslip (lines cascade), then
  /// re-sum the run's totals from the payslips that remain.
  ///
  /// No recompute — removing one employee cannot change anybody else's pay.
  ///
  /// Throws [RosterEditException] with a user-facing message when the run is
  /// not editable, when the payslip is live in a Lark approval, or when the
  /// removal would empty the roster.
  Future<void> removeEmployeeFromRun({
    required PayrollRun run,
    required String employeeId,
  }) async {
    final live = await _readRunRow(run.id);
    _assertEditable(live.status);

    // Frozen-payslip rule, same as recompute: a payslip that is out for Lark
    // approval must be recalled before it can be deleted, otherwise the Lark
    // instance would point at a row that no longer exists.
    final existing = await _client
        .from('payslips')
        .select('id, lark_approval_status')
        .eq('payroll_run_id', run.id)
        .eq('employee_id', employeeId)
        .maybeSingle();
    if (existing != null &&
        isLarkFrozen(existing['lark_approval_status'] as String?)) {
      throw const RosterEditException(
        'This payslip is out for Lark approval. Recall it from the Approvals '
        'tab before removing the employee.',
      );
    }

    final roster = _rosterOf(live.included, await _eligibleEmployees(run));

    // Roster first: if the payslip delete fails we are left with a run that
    // excludes the employee but still shows their payslip — visible and
    // fixable. The other order would silently re-add them on recompute.
    if (roster.contains(employeeId)) {
      await _writeRoster(
        run.id,
        rosterAfterRemoval(roster: roster, employeeId: employeeId),
      );
    } else if (existing == null) {
      throw const RosterEditException(
        'That employee is not part of this payroll run.',
      );
    }
    // else: an employee archived since the run computed is already outside the
    // roster — nothing to subtract, but their payslip still has to go.

    if (existing != null) {
      await _client.from('payslips').delete().eq('id', existing['id'] as String);
    }
    await _resyncTotals(run.id);
  }

  /// Add [employeeIds] to the run's roster. The caller is responsible for
  /// recomputing afterwards — that is what actually generates their payslips.
  Future<void> addEmployeesToRun({
    required PayrollRun run,
    required List<String> employeeIds,
  }) async {
    final live = await _readRunRow(run.id);
    _assertEditable(live.status);
    final roster = _rosterOf(live.included, await _eligibleEmployees(run));
    final next = rosterAfterAdditions(roster: roster, employeeIds: employeeIds);
    await _writeRoster(run.id, next);
  }

  void _assertEditable(String status) {
    if (!_editableStatuses.contains(status)) {
      throw RosterEditException(
        'A ${status.toLowerCase()} run\'s employees cannot be changed.',
      );
    }
  }

  Future<void> _writeRoster(String runId, List<String> roster) async {
    await _client
        .from('payroll_runs')
        .update({'included_employee_ids': roster})
        .eq('id', runId);
  }

  /// Re-derive `payroll_runs` money totals + counts from its payslips, so the
  /// Summary card keeps matching the sum of what is on disk.
  Future<void> _resyncTotals(String runId) async {
    final rows = await _client
        .from('payslips')
        .select('gross_pay, total_deductions, net_pay')
        .eq('payroll_run_id', runId);
    final totals = sumTotals(
      (rows as List<dynamic>).cast<Map<String, dynamic>>(),
    );
    await _client
        .from('payroll_runs')
        .update({
          'total_gross_pay': totals.gross.toString(),
          'total_deductions': totals.deductions.toString(),
          'total_net_pay': totals.net.toString(),
          'employee_count': totals.count,
          'payslip_count': totals.count,
        })
        .eq('id', runId);
  }

  static int _byEmployeeNumber(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final an = (a['employee_number'] as String? ?? '');
    final bn = (b['employee_number'] as String? ?? '');
    if (an.isEmpty && bn.isEmpty) return 0;
    if (an.isEmpty) return 1;
    if (bn.isEmpty) return -1;
    return an.compareTo(bn);
  }
}

final payrollRosterServiceProvider = Provider<PayrollRosterService>(
  (ref) => PayrollRosterService(Supabase.instance.client),
);
