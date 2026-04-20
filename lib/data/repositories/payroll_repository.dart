import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payroll_run.dart';
import '../models/payslip.dart';

/// Outcome of a `distributeThirteenthMonth` call — lets the UI show a
/// success summary (N employees, total payout, any skipped rows).
class DistributeThirteenthMonthResult {
  final int employeesDistributed;
  final Decimal totalPayout;
  final List<String> errors;
  const DistributeThirteenthMonthResult({
    required this.employeesDistributed,
    required this.totalPayout,
    required this.errors,
  });
}

class PayrollRepository {
  final SupabaseClient _client;
  PayrollRepository(this._client);

  /// Compute the 13th-month payout for a given accrued-basis amount.
  /// Formula: `basis / 12`, rounded to 2dp half-up. Negative input clamps
  /// to zero (defensive — shouldn't happen in practice).
  ///
  /// Exposed as a static so the distribution dialog can preview payouts
  /// without holding a repository reference.
  static Decimal thirteenthMonthPayout(Decimal basis) {
    if (basis <= Decimal.zero) return Decimal.zero;
    return (basis / Decimal.fromInt(12))
        .toDecimal(scaleOnInfinitePrecision: 10)
        .round(scale: 2);
  }

  Future<List<PayrollRun>> listRuns() async {
    // After the pay_periods drop, period + company fields live directly on
    // payroll_runs. Sort client-side rather than server-side so this query
    // still works before migration 20260418000001 has been applied — at
    // that point `pay_date` is not yet a real column and `.order('pay_date')`
    // would 400. `created_at` has always existed, so use it as the
    // baseline server-side sort.
    final rows = await _client
        .from('payroll_runs')
        .select(
          '*, '
          'created_by:user_emails!created_by_id(email), '
          'approved_by:user_emails!approved_by_id(email)',
        )
        .order('created_at', ascending: false) as List<dynamic>;
    final runs =
        rows.cast<Map<String, dynamic>>().map(PayrollRun.fromRow).toList();
    runs.sort((a, b) {
      final cmp = b.payDate.compareTo(a.payDate);
      return cmp != 0 ? cmp : b.createdAt.compareTo(a.createdAt);
    });
    return runs;
  }

  Future<PayrollRun?> byId(String id) async {
    final row = await _client
        .from('payroll_runs')
        .select(
          '*, created_by:user_emails!created_by_id(email), '
          'approved_by:user_emails!approved_by_id(email)',
        )
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return PayrollRun.fromRow(row);
  }

  Future<void> updateStatus(String id, String status) async {
    await _client.from('payroll_runs').update({'status': status}).eq('id', id);
  }

  /// Counts per payslip approval_status for the run (used for the gate to release).
  Future<Map<String, int>> payslipApprovalCounts(String runId) async {
    final rows = await _client
        .from('payslips')
        .select('approval_status')
        .eq('payroll_run_id', runId) as List<dynamic>;
    final counts = <String, int>{};
    for (final r in rows.cast<Map<String, dynamic>>()) {
      final s = r['approval_status'] as String;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// Dispatch DRAFT_IN_REVIEW payslips in the run to Lark for approval.
  /// Calls the `send-payslip-approvals` Edge Function which creates approval
  /// instances server-side.
  ///
  /// The Lark approval template (shared with the payrollos app) has a
  /// required PDF attachment widget, so the caller must supply the encoded
  /// payslip PDF for each payslip being dispatched in [pdfsByPayslipId]
  /// (base64 strings, keyed by payslip id). The edge function uploads each
  /// PDF to Lark's file API and references it as `attachmentV2` on the
  /// approval form.
  ///
  /// Pass [payslipIds] to scope the dispatch to a subset (from the Approvals
  /// tab selection). Omit to dispatch every DRAFT_IN_REVIEW payslip in the
  /// run — but note that even in that case the caller still needs to supply
  /// PDFs for every payslip that'll be dispatched.
  Future<Map<String, dynamic>> sendPayslipApprovals(
    String runId, {
    List<String>? payslipIds,
    required Map<String, String> pdfsByPayslipId,
  }) async {
    final res = await _client.functions.invoke(
      'send-payslip-approvals',
      body: {
        'run_id': runId,
        if (payslipIds != null && payslipIds.isNotEmpty)
          'payslip_ids': payslipIds,
        'pdfs_base64': pdfsByPayslipId,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Pull fresh Lark approval status for every payslip in the run that has
  /// already been dispatched (has a `lark_approval_instance_code`). Calls the
  /// `sync-payslip-approvals` Edge Function.
  ///
  /// Pass [payslipIds] to scope the sync to a selected subset. The webhook
  /// keeps these in sync in near-realtime when deployed; this is the explicit
  /// "refresh now" path that also backfills missed webhook events.
  Future<Map<String, dynamic>> syncPayslipApprovals(
    String runId, {
    List<String>? payslipIds,
  }) async {
    final res = await _client.functions.invoke(
      'sync-payslip-approvals',
      body: {
        'run_id': runId,
        if (payslipIds != null && payslipIds.isNotEmpty)
          'payslip_ids': payslipIds,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Payslip?> payslipById(String id) async {
    final row = await _client.from('payslips').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    final lineRows = await _client
        .from('payslip_lines')
        .select()
        .eq('payslip_id', id)
        .order('sort_order') as List<dynamic>;
    final lines = lineRows.cast<Map<String, dynamic>>().map(PayslipLine.fromRow).toList();
    return Payslip.fromRow(row, lines: lines);
  }

  /// Full payslip record for the detail screen: payslip row with joined
  /// employee/department/role, payroll run (which now owns the period +
  /// pay_frequency fields directly), and its ordered payslip_lines.
  ///
  /// Embeds `payroll_runs!inner(*)` rather than listing specific columns so
  /// the query works both before and after migration 20260418000001 —
  /// PostgREST returns whatever columns actually exist on `payroll_runs`.
  Future<Map<String, dynamic>?> payslipDetailById(String id) async {
    final row = await _client
        .from('payslips')
        .select(
          '*, '
          'employees!inner(id, employee_number, first_name, middle_name, last_name, '
          'job_title, department_id, role_scorecard_id, '
          'departments!employees_department_id_fkey(name), role_scorecards(job_title, base_salary, wage_type, work_hours_per_day, work_days_per_week)), '
          'payroll_runs!inner(*)',
        )
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final lineRows = await _client
        .from('payslip_lines')
        .select()
        .eq('payslip_id', id)
        .order('sort_order');
    row['__lines'] = (lineRows as List<dynamic>).cast<Map<String, dynamic>>();
    return row;
  }

  /// Manual adjustments for a specific (run, employee). Used on the Payslip
  /// detail's Commissions & Adjustments tab.
  Future<List<Map<String, dynamic>>> manualAdjustments(
    String runId,
    String employeeId,
  ) async {
    final rows = await _client
        .from('manual_adjustment_lines')
        .select()
        .eq('payroll_run_id', runId)
        .eq('employee_id', employeeId)
        .order('created_at');
    return (rows as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> insertManualAdjustment({
    required String runId,
    required String employeeId,
    required String category, // ADJUSTMENT_ADD or ADJUSTMENT_DEDUCT
    required String description,
    required String amount, // stringified Decimal
    String? remarks,
    String? createdById,
  }) async {
    final row = await _client
        .from('manual_adjustment_lines')
        .insert({
          'payroll_run_id': runId,
          'employee_id': employeeId,
          'category': category,
          'description': description,
          'amount': amount,
          'remarks': ?remarks,
          'created_by_id': ?createdById,
        })
        .select()
        .single();
    return row;
  }

  Future<Map<String, dynamic>> updateManualAdjustment({
    required String id,
    required String category,
    required String description,
    required String amount,
    String? remarks,
  }) async {
    final row = await _client
        .from('manual_adjustment_lines')
        .update({
          'category': category,
          'description': description,
          'amount': amount,
          'remarks': remarks,
        })
        .eq('id', id)
        .select()
        .single();
    return row;
  }

  Future<void> deleteManualAdjustment(String id) async {
    await _client.from('manual_adjustment_lines').delete().eq('id', id);
  }

  Future<List<Payslip>> payslipsByRun(String runId) async {
    final rows = await _client
        .from('payslips')
        .select()
        .eq('payroll_run_id', runId)
        .order('created_at') as List<dynamic>;
    return rows.cast<Map<String, dynamic>>().map((r) => Payslip.fromRow(r)).toList();
  }

  /// Raw payslip rows with joined employee + role + department info for the
  /// run detail screen. Returns the raw maps so the UI can render without
  /// hopping through more round-trips.
  Future<List<Map<String, dynamic>>> payslipListForRun(String runId) async {
    final rows = await _client
        .from('payslips')
        .select(
          '*, employees!inner(id, employee_number, first_name, middle_name, '
          'last_name, department_id, role_scorecard_id, hiring_entity_id, '
          'accrued_thirteenth_month_basis, '
          'departments!employees_department_id_fkey(name), hiring_entities(code, name), '
          'role_scorecards(department_id, departments(name)), '
          'employee_bank_accounts(bank_code, bank_name, account_number, account_name, account_type, is_primary, deleted_at)), '
          'payslip_lines(id, category)',
        )
        .eq('payroll_run_id', runId);
    final out = (rows as List<dynamic>).cast<Map<String, dynamic>>();
    out.sort((a, b) {
      final an = (a['employees'] as Map<String, dynamic>?)?['employee_number']
              as String? ??
          '';
      final bn = (b['employees'] as Map<String, dynamic>?)?['employee_number']
              as String? ??
          '';
      if (an.isEmpty && bn.isEmpty) return 0;
      if (an.isEmpty) return 1;
      if (bn.isEmpty) return -1;
      return an.compareTo(bn);
    });
    return out;
  }

  /// Aggregated Lark approval counts for a run (for the Approvals tab header).
  Future<Map<String, int>> larkApprovalCounts(String runId) async {
    final rows = await _client
        .from('payslips')
        .select('lark_approval_status')
        .eq('payroll_run_id', runId) as List<dynamic>;
    final counts = <String, int>{};
    for (final r in rows.cast<Map<String, dynamic>>()) {
      final s = (r['lark_approval_status'] as String?) ?? 'NOT_SENT';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// Update the payment source for a payslip (used by Disbursement tab
  /// dropdown while run is in REVIEW). Writes both the new uuid FK
  /// (`pay_source_account_id`) and the legacy string column
  /// (`payment_source_account`) so the app can be rolled back safely during
  /// the FK transition. Either side can be null (e.g. if the dropdown picks a
  /// new account that has no legacy mapping).
  Future<void> updatePayslipDisbursement(
    String payslipId, {
    String? sourceAccount,
    String? paySourceAccountId,
  }) async {
    final payload = <String, dynamic>{};
    payload['payment_source_account'] = sourceAccount;
    payload['pay_source_account_id'] = paySourceAccountId;
    await _client
        .from('payslips')
        .update(payload)
        .eq('id', payslipId);
  }

  /// Defer a specific penalty installment out of the given payroll run. The
  /// installment is added to `skipped_payroll_run_ids` so the next compute
  /// for that run excludes it; subsequent runs still pick it up because
  /// `is_deducted` is untouched. Caller is expected to trigger a Recompute
  /// afterwards so the payslip_lines are rebuilt without the skipped row.
  ///
  /// [skip] = true to add the run id; false to remove it (undo).
  Future<void> setPenaltyInstallmentSkip({
    required String installmentId,
    required String runId,
    required bool skip,
  }) async {
    final row = await _client
        .from('penalty_installments')
        .select('skipped_payroll_run_ids')
        .eq('id', installmentId)
        .single();
    final current =
        (row['skipped_payroll_run_ids'] as List?)?.cast<String>() ?? const [];
    final next = skip
        ? {...current, runId}.toList()
        : current.where((id) => id != runId).toList();
    await _client
        .from('penalty_installments')
        .update({'skipped_payroll_run_ids': next})
        .eq('id', installmentId);
  }

  /// Defer a specific cash advance out of the given payroll run. The
  /// advance is added to `skipped_payroll_run_ids` so the next compute
  /// for that run excludes it; subsequent runs still pick it up because
  /// `is_deducted` is untouched. Caller is expected to trigger a Recompute
  /// afterwards so the payslip_lines are rebuilt without the skipped row.
  ///
  /// [skip] = true to add the run id; false to remove it (undo).
  Future<void> setCashAdvanceSkip({
    required String advanceId,
    required String runId,
    required bool skip,
  }) async {
    final row = await _client
        .from('cash_advances')
        .select('skipped_payroll_run_ids')
        .eq('id', advanceId)
        .single();
    final current =
        (row['skipped_payroll_run_ids'] as List?)?.cast<String>() ?? const [];
    final next = skip
        ? {...current, runId}.toList()
        : current.where((id) => id != runId).toList();
    await _client
        .from('cash_advances')
        .update({'skipped_payroll_run_ids': next})
        .eq('id', advanceId);
  }

  /// Release a run: move status → RELEASED, stamp released_at, and lock
  /// attendance rows that fall within the pay period (server-side RLS/
  /// triggers handle the cascade where configured).
  /// Finalize a payroll run. This does four things in sequence, best-effort
  /// without transactional guarantees (Supabase PostgREST doesn't expose
  /// multi-statement transactions to the client):
  ///   1. Lock the attendance rows that belong to this run's employees and
  ///      fall within the pay period's start..end range.
  ///   2. Mark the cash advances referenced by payslip_lines as deducted.
  ///   3. Mark the reimbursements referenced by payslip_lines as paid.
  ///   4. Mark the penalty installments referenced by payslip_lines as
  ///      deducted.
  ///   5. Flip the run's status to RELEASED and stamp `released_at`.
  /// Throws on the first failure; earlier steps are not rolled back. In
  /// practice the cleanest migration path is a server-side RPC — the caller
  /// gets a single promise here either way.
  Future<void> releaseRun(String runId) async {
    // Period bounds live on payroll_runs directly after migration
    // 20260418000001.
    final runRow = await _client
        .from('payroll_runs')
        .select('id, period_start, period_end')
        .eq('id', runId)
        .single();
    final startIso = runRow['period_start'] as String;
    final endIso = runRow['period_end'] as String;

    // Collect employee + adjunct ids from payslip_lines in this run.
    final lineRows = await _client
        .from('payslip_lines')
        .select(
          'cash_advance_id, reimbursement_id, penalty_installment_id, '
          'payslips!inner(employee_id, payroll_run_id)',
        )
        .eq('payslips.payroll_run_id', runId);
    final cashAdvanceIds = <String>{};
    final reimbursementIds = <String>{};
    final penaltyInstallmentIds = <String>{};
    final employeeIds = <String>{};
    for (final r in (lineRows as List<dynamic>).cast<Map<String, dynamic>>()) {
      final ca = r['cash_advance_id'] as String?;
      final rb = r['reimbursement_id'] as String?;
      final pi = r['penalty_installment_id'] as String?;
      final emp = (r['payslips'] as Map<String, dynamic>)['employee_id'] as String?;
      if (ca != null) cashAdvanceIds.add(ca);
      if (rb != null) reimbursementIds.add(rb);
      if (pi != null) penaltyInstallmentIds.add(pi);
      if (emp != null) employeeIds.add(emp);
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();

    // 1. Lock attendance
    if (employeeIds.isNotEmpty) {
      await _client
          .from('attendance_day_records')
          .update({
            'is_locked': true,
            'locked_by_payroll_run_id': runId,
          })
          .inFilter('employee_id', employeeIds.toList())
          .gte('attendance_date', startIso)
          .lte('attendance_date', endIso);
    }

    // 2. Mark cash advances as deducted
    if (cashAdvanceIds.isNotEmpty) {
      await _client
          .from('cash_advances')
          .update({
            'is_deducted': true,
            'deducted_at': nowIso,
            'payroll_run_id': runId,
          })
          .inFilter('id', cashAdvanceIds.toList());
    }

    // 3. Mark reimbursements as paid
    if (reimbursementIds.isNotEmpty) {
      await _client
          .from('reimbursements')
          .update({
            'is_paid': true,
            'paid_at': nowIso,
            'payroll_run_id': runId,
          })
          .inFilter('id', reimbursementIds.toList());
    }

    // 4. Mark penalty installments as deducted
    if (penaltyInstallmentIds.isNotEmpty) {
      await _client
          .from('penalty_installments')
          .update({
            'is_deducted': true,
            'deducted_at': nowIso,
          })
          .inFilter('id', penaltyInstallmentIds.toList());
    }

    // 4.5 Tick up 13th-month accrual: sum each payslip's BASIC_PAY line
    // amount and add it to that employee's running basis. Done before the
    // status flip so a partial failure leaves the run in REVIEW state and
    // the operator can retry. The status-machine guards double-releases
    // on the same run, so no double-counting risk.
    final basicPayRows = await _client
        .from('payslip_lines')
        .select('amount, payslips!inner(employee_id, payroll_run_id)')
        .eq('payslips.payroll_run_id', runId)
        .eq('category', 'BASIC_PAY');
    final basicByEmp = <String, Decimal>{};
    for (final r
        in (basicPayRows as List<dynamic>).cast<Map<String, dynamic>>()) {
      final emp = (r['payslips'] as Map<String, dynamic>)['employee_id']
          as String;
      final amt = Decimal.tryParse((r['amount'] ?? '0').toString()) ??
          Decimal.zero;
      basicByEmp[emp] = (basicByEmp[emp] ?? Decimal.zero) + amt;
    }
    if (basicByEmp.isNotEmpty) {
      // PostgREST has no scalar-add; read-modify-write per employee.
      final empRows = await _client
          .from('employees')
          .select('id, accrued_thirteenth_month_basis')
          .inFilter('id', basicByEmp.keys.toList());
      for (final row
          in (empRows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final empId = row['id'] as String;
        final current = Decimal.tryParse(
                (row['accrued_thirteenth_month_basis'] ?? '0').toString()) ??
            Decimal.zero;
        final delta = basicByEmp[empId] ?? Decimal.zero;
        final next = current + delta;
        await _client
            .from('employees')
            .update({'accrued_thirteenth_month_basis': next.toString()})
            .eq('id', empId);
      }
    }

    // 5. Flip the run to RELEASED
    await _client.from('payroll_runs').update({
      'status': 'RELEASED',
      'released_at': nowIso,
    }).eq('id', runId);
  }

  Future<void> cancelRun(String runId, {String? reason}) async {
    await _client.from('payroll_runs').update({
      'status': 'CANCELLED',
      if (reason != null && reason.isNotEmpty) 'remarks': reason,
    }).eq('id', runId);
  }

  /// Distribute 13th-month pay on the given run for the given employees.
  ///
  /// For each employee:
  ///   1. Insert a `THIRTEENTH_MONTH_PAY` payslip_lines row on their payslip
  ///      in this run (amount = accruedBasis / 12, rounded to 2dp).
  ///   2. Zero their `accrued_thirteenth_month_basis`.
  ///   3. Add the payout to `payslips.gross_pay` and `payslips.net_pay` so
  ///      Summary tab totals reflect the new amount without a recompute.
  /// Finally, flip `payroll_runs.is_thirteenth_month_distribution = true`.
  ///
  /// Skips employees who already have a `THIRTEENTH_MONTH_PAY` line on this
  /// run's payslip (idempotent re-click).
  Future<DistributeThirteenthMonthResult> distributeThirteenthMonth({
    required String runId,
    required List<String> employeeIds,
  }) async {
    final errors = <String>[];
    if (employeeIds.isEmpty) {
      return DistributeThirteenthMonthResult(
        employeesDistributed: 0,
        totalPayout: Decimal.zero,
        errors: const [],
      );
    }

    // Fetch current basis per employee.
    final empRows = await _client
        .from('employees')
        .select('id, accrued_thirteenth_month_basis')
        .inFilter('id', employeeIds);
    final basisByEmp = <String, Decimal>{
      for (final r in (empRows as List<dynamic>).cast<Map<String, dynamic>>())
        r['id'] as String: Decimal.tryParse(
                (r['accrued_thirteenth_month_basis'] ?? '0').toString()) ??
            Decimal.zero,
    };

    // Fetch each employee's payslip on this run + current totals for the
    // running-total update.
    final payslipRows = await _client
        .from('payslips')
        .select('id, employee_id, gross_pay, net_pay')
        .eq('payroll_run_id', runId)
        .inFilter('employee_id', employeeIds);
    final payslipByEmp = <String, Map<String, dynamic>>{
      for (final r
          in (payslipRows as List<dynamic>).cast<Map<String, dynamic>>())
        r['employee_id'] as String: r,
    };

    // Detect payslips that already carry a distribution line so re-click
    // doesn't double-post.
    final payslipIds =
        payslipByEmp.values.map((p) => p['id'] as String).toList();
    final alreadyDistributedPayslipIds = <String>{};
    if (payslipIds.isNotEmpty) {
      final existingLineRows = await _client
          .from('payslip_lines')
          .select('payslip_id')
          .inFilter('payslip_id', payslipIds)
          .eq('category', 'THIRTEENTH_MONTH_PAY');
      for (final r in (existingLineRows as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
        alreadyDistributedPayslipIds.add(r['payslip_id'] as String);
      }
    }

    int distributed = 0;
    Decimal totalPayout = Decimal.zero;

    for (final empId in employeeIds) {
      final payslip = payslipByEmp[empId];
      if (payslip == null) {
        errors.add('$empId: no payslip on run');
        continue;
      }
      if (alreadyDistributedPayslipIds.contains(payslip['id'])) {
        errors.add('$empId: already distributed on this run');
        continue;
      }
      final basis = basisByEmp[empId] ?? Decimal.zero;
      final payout = thirteenthMonthPayout(basis);
      if (payout <= Decimal.zero) {
        errors.add('$empId: zero basis');
        continue;
      }

      try {
        // 1. Insert the payslip line.
        await _client.from('payslip_lines').insert({
          'payslip_id': payslip['id'],
          'category': 'THIRTEENTH_MONTH_PAY',
          'description': '13th Month Pay (distribution)',
          'amount': payout.toString(),
          'quantity': '1',
          'rate': payout.toString(),
          'sort_order': 450,
        });

        // 2. Zero the accrual.
        await _client
            .from('employees')
            .update({'accrued_thirteenth_month_basis': '0'})
            .eq('id', empId);

        // 3. Update payslip totals.
        final currentGross = Decimal.tryParse(
                (payslip['gross_pay'] ?? '0').toString()) ??
            Decimal.zero;
        final currentNet = Decimal.tryParse(
                (payslip['net_pay'] ?? '0').toString()) ??
            Decimal.zero;
        await _client.from('payslips').update({
          'gross_pay': (currentGross + payout).toString(),
          'net_pay': (currentNet + payout).toString(),
        }).eq('id', payslip['id']);

        distributed++;
        totalPayout += payout;
      } catch (e) {
        errors.add('$empId: $e');
      }
    }

    if (distributed > 0) {
      try {
        await _client
            .from('payroll_runs')
            .update({'is_thirteenth_month_distribution': true})
            .eq('id', runId);
      } catch (_) {
        // Metadata-only flag; swallow if it fails.
      }
    }

    return DistributeThirteenthMonthResult(
      employeesDistributed: distributed,
      totalPayout: totalPayout,
      errors: errors,
    );
  }

  /// Permanently delete a payroll run. Only allowed when status == CANCELLED
  /// (safety guard — DRAFT/REVIEW/RELEASED runs hold integrity-sensitive
  /// links to cash advances, attendance locks, and payslips).
  ///
  /// `payslips` cascade-delete via the FK. Cancelled runs don't hold
  /// attendance locks or benefit deduction references, so a straight delete
  /// is safe.
  Future<void> deleteRun(String runId) async {
    final row = await _client
        .from('payroll_runs')
        .select('status')
        .eq('id', runId)
        .maybeSingle();
    if (row == null) return;
    final status = row['status'] as String?;
    if (status != 'CANCELLED') {
      throw Exception(
        'Only CANCELLED runs can be deleted (current status: ${status ?? "?"}). '
        'Cancel the run first.',
      );
    }
    // Sweep referencing rows first — the original FKs lacked cascade on
    // several tables, so a raw DELETE fails. Migration 20260418000006
    // hardens this at the schema level; this code also handles DBs that
    // haven't been migrated yet.
    //
    // Order matters: payslip_lines.manual_adjustment_id references
    // manual_adjustment_lines without cascade, so we nullify those first
    // via a parent-scoped update, then nuke the adjustments.
    final payslipIds = await _client
        .from('payslips')
        .select('id')
        .eq('payroll_run_id', runId);
    final ids = (payslipIds as List<dynamic>)
        .map((e) => (e as Map<String, dynamic>)['id'] as String)
        .toList();
    if (ids.isNotEmpty) {
      await _client
          .from('payslip_lines')
          .update({'manual_adjustment_id': null})
          .inFilter('payslip_id', ids);
    }
    await _client
        .from('manual_adjustment_lines')
        .delete()
        .eq('payroll_run_id', runId);
    // Standalone records (cash advances, reimbursements, penalty
    // installments) should survive the run deletion — just unlink them.
    await _client
        .from('cash_advances')
        .update({'payroll_run_id': null, 'is_deducted': false})
        .eq('payroll_run_id', runId);
    await _client
        .from('reimbursements')
        .update({'payroll_run_id': null, 'is_paid': false})
        .eq('payroll_run_id', runId);
    await _client
        .from('penalty_installments')
        .update({'payroll_run_id': null, 'is_deducted': false})
        .eq('payroll_run_id', runId);
    // payslips cascade-delete via FK; attendance_day_records.locked_by
    // needs unlinking too (CANCELLED runs shouldn't hold attendance locks
    // but this is defensive).
    await _client
        .from('attendance_day_records')
        .update({'locked_by_payroll_run_id': null, 'is_locked': false})
        .eq('locked_by_payroll_run_id', runId);
    await _client.from('payroll_runs').delete().eq('id', runId);
  }

  // ----- Run creation ------------------------------------------------------

  /// Returns the set of employee IDs already covered by non-CANCELLED runs
  /// whose period overlaps the supplied range. Prevents creating a second
  /// run that overlaps employees with an existing active run on overlapping
  /// dates.
  Future<Set<String>> employeesCoveredByActiveRuns({
    required String companyId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final startIso = periodStart.toIso8601String().substring(0, 10);
    final endIso = periodEnd.toIso8601String().substring(0, 10);
    final runs = await _client
        .from('payroll_runs')
        .select('id, status, included_employee_ids, period_start, period_end')
        .eq('company_id', companyId)
        .neq('status', 'CANCELLED')
        // Overlap test: existing.start <= new.end AND existing.end >= new.start.
        .lte('period_start', endIso)
        .gte('period_end', startIso);
    final covered = <String>{};
    bool hasCatchAllRun = false;
    for (final r in (runs as List<dynamic>).cast<Map<String, dynamic>>()) {
      final raw = r['included_employee_ids'];
      if (raw is List && raw.isNotEmpty) {
        for (final id in raw.whereType<String>()) {
          covered.add(id);
        }
      } else {
        // Legacy run (null/empty) = all active company employees at the time.
        hasCatchAllRun = true;
      }
    }
    if (hasCatchAllRun) {
      final rows = await _client
          .from('employees')
          .select('id')
          .eq('company_id', companyId)
          .eq('employment_status', 'ACTIVE')
          .isFilter('deleted_at', null);
      for (final e in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
        covered.add(e['id'] as String);
      }
    }
    return covered;
  }

  /// Look up employee display info for a batch of ids. Used to format the
  /// employee-overlap error with human-readable names.
  Future<List<Map<String, dynamic>>> employeesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _client
        .from('employees')
        .select('id, employee_number, first_name, last_name')
        .inFilter('id', ids);
    return (rows as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Create a DRAFT run for the given date range. Returns the new run id so
  /// callers can navigate straight to the detail page.
  ///
  /// Pass [includedEmployeeIds] to scope the run to a subset of active
  /// employees — the compute engine will only process those on recompute.
  /// Omit (null) to include all active employees of the company.
  Future<String> createRun({
    required String companyId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime payDate,
    String payFrequency = 'SEMI_MONTHLY',
    String? createdById,
    List<String>? includedEmployeeIds,
  }) async {
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    final row = await _client
        .from('payroll_runs')
        .insert({
          'company_id': companyId,
          'period_start': iso(periodStart),
          'period_end': iso(periodEnd),
          'pay_date': iso(payDate),
          'pay_frequency': payFrequency,
          'status': 'DRAFT',
          if (createdById != null) 'created_by_id': createdById,
          if (includedEmployeeIds != null && includedEmployeeIds.isNotEmpty)
            'included_employee_ids': includedEmployeeIds,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Active employees with attendance_day_records in [from, to]. Returns a
  /// list of maps sorted by last name / first name, each containing:
  ///   id, employee_number, first_name, last_name, attendance_days
  ///
  /// Used by the "New Payroll Run" dialog to let the user pick exactly which
  /// employees the run should cover.
  Future<List<Map<String, dynamic>>> employeesWithAttendance({
    required String companyId,
    required DateTime from,
    required DateTime to,
  }) async {
    final fromIso = from.toIso8601String().substring(0, 10);
    final toIso = to.toIso8601String().substring(0, 10);
    // Fetch attendance rows first, then the employee rows. Two round-trips
    // keeps the query simple and avoids PostgREST's embed-filtering quirks.
    final attRows = await _client
        .from('attendance_day_records')
        .select('employee_id, attendance_date')
        .gte('attendance_date', fromIso)
        .lte('attendance_date', toIso);
    final counts = <String, int>{};
    for (final r in (attRows as List<dynamic>).cast<Map<String, dynamic>>()) {
      final id = r['employee_id'] as String?;
      if (id == null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];

    final empRows = await _client
        .from('employees')
        .select('id, employee_number, first_name, last_name')
        .eq('company_id', companyId)
        .eq('employment_status', 'ACTIVE')
        .isFilter('deleted_at', null)
        .inFilter('id', counts.keys.toList());
    final out = (empRows as List<dynamic>).cast<Map<String, dynamic>>().map((e) {
      return {
        ...e,
        'attendance_days': counts[e['id']] ?? 0,
      };
    }).toList();
    out.sort((a, b) {
      final an = (a['employee_number'] as String? ?? '');
      final bn = (b['employee_number'] as String? ?? '');
      if (an.isEmpty && bn.isEmpty) return 0;
      if (an.isEmpty) return 1;
      if (bn.isEmpty) return -1;
      return an.compareTo(bn);
    });
    return out;
  }

  /// Fetch payslips for a single employee within a date range. Period bounds
  /// now live on payroll_runs directly, so a single embed is enough.
  Future<List<PayslipWithPeriod>> payslipsByEmployee(
    String employeeId, {
    required DateTime from,
    required DateTime to,
  }) async {
    // Filter client-side on the new period_* columns so the call still works
    // pre-migration (the columns may not exist yet).
    final rows = await _client
        .from('payslips')
        .select(
          '*, payroll_runs!inner(period_start, period_end, pay_date)',
        )
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false) as List<dynamic>;
    final out = <PayslipWithPeriod>[];
    for (final raw in rows.cast<Map<String, dynamic>>()) {
      try {
        final run = raw['payroll_runs'] as Map<String, dynamic>?;
        final pStart = run?['period_start'] == null
            ? null
            : DateTime.parse(run!['period_start'] as String);
        final pEnd = run?['period_end'] == null
            ? null
            : DateTime.parse(run!['period_end'] as String);
        // Client-side range filter (replaces the server-side .gte/.lte
        // that only worked post-migration). Keep rows with no period info
        // so they stay visible until the migration lands.
        if (pEnd != null && pEnd.isBefore(from)) continue;
        if (pStart != null && pStart.isAfter(to)) continue;
        out.add(PayslipWithPeriod(
          payslip: Payslip.fromRow(raw),
          periodStart: pStart,
          periodEnd: pEnd,
          payDate: run?['pay_date'] == null
              ? null
              : DateTime.parse(run!['pay_date'] as String),
        ));
      } catch (e) {
        // ignore a malformed row rather than break the whole tab
        // ignore: avoid_print
        print('payslipsByEmployee row parse failed: $e row=$raw');
      }
    }
    return out;
  }

  /// Recall PENDING_APPROVAL payslips in the run back to editable state.
  ///
  /// Dispatches to the `recall-payslip-approvals` Edge Function which
  /// cancels each open Lark approval instance (using the admin as
  /// canceller — only the initiator can cancel), then flips the local
  /// rows to `approval_status='RECALLED'` with `lark_approval_status=NULL`
  /// so a subsequent send/recompute will regenerate them.
  ///
  /// Pass [payslipIds] to recall a specific subset (row-level or selection
  /// bulk). Omit to recall every PENDING_APPROVAL row in the run.
  ///
  /// Returns the edge function's response payload
  /// (`{ ok, recalled, failed, errors }`).
  Future<Map<String, dynamic>> recallPayslipApprovals(
    String runId, {
    List<String>? payslipIds,
  }) async {
    final res = await _client.functions.invoke(
      'recall-payslip-approvals',
      body: {
        'run_id': runId,
        if (payslipIds != null && payslipIds.isNotEmpty)
          'payslip_ids': payslipIds,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }
}

final payrollRepositoryProvider =
    Provider<PayrollRepository>((ref) => PayrollRepository(Supabase.instance.client));

final payrollRunsProvider =
    FutureProvider<List<PayrollRun>>((ref) => ref.watch(payrollRepositoryProvider).listRuns());

final payslipApprovalCountsProvider =
    FutureProvider.family<Map<String, int>, String>((ref, runId) {
  return ref.watch(payrollRepositoryProvider).payslipApprovalCounts(runId);
});

/// Payslip with its pay-period dates attached — used by the employee profile
/// Payslips tab to render "from/to" ranges without a second round-trip.
class PayslipWithPeriod {
  final Payslip payslip;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? payDate;
  const PayslipWithPeriod({
    required this.payslip,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
  });
}

class PayslipsByEmployeeQuery {
  final String employeeId;
  final DateTime from;
  final DateTime to;
  const PayslipsByEmployeeQuery({
    required this.employeeId,
    required this.from,
    required this.to,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PayslipsByEmployeeQuery &&
          other.employeeId == employeeId &&
          other.from == from &&
          other.to == to);

  @override
  int get hashCode => Object.hash(employeeId, from, to);
}

final payslipsByEmployeeProvider =
    FutureProvider.family<List<PayslipWithPeriod>, PayslipsByEmployeeQuery>(
        (ref, q) {
  return ref.watch(payrollRepositoryProvider).payslipsByEmployee(
        q.employeeId,
        from: q.from,
        to: q.to,
      );
});
