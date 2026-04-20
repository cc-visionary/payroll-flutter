import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../engine/compute_engine.dart';
import '../../engine/statutory_tables.dart';
import '../../engine/types.dart' as e;

/// Orchestrates a full payroll compute for a given run:
///   1. Load payroll run + pay period + calendar
///   2. Load all active employees + their role scorecards
///   3. For each employee, load attendance, manual adjustments, cash advances,
///      reimbursements, active penalty installments, previous YTD
///   4. Build `EmployeePayrollInput`s and call the engine (pure Dart)
///   5. Delete existing payslips for the run (cascade clears lines)
///   6. Insert fresh payslips + payslip_lines
///   7. Update payroll_runs totals + status to REVIEW
class PayrollComputeService {
  final SupabaseClient _client;
  PayrollComputeService(this._client);

  Future<ComputeOutcome> computeRun(
    String runId, {
    void Function(String step)? onStep,
  }) async {
    onStep?.call('Loading payroll run…');
    // Period + calendar fields were inlined into payroll_runs in
    // migration 20260418000001 — one table read covers everything.
    final runRow = await _client
        .from('payroll_runs')
        .select(
          'id, status, company_id, included_employee_ids, '
          'period_start, period_end, pay_date, pay_frequency',
        )
        .eq('id', runId)
        .single();
    final companyId = runRow['company_id'] as String;
    final includedIdsRaw = runRow['included_employee_ids'];
    final includedIds = includedIdsRaw is List
        ? includedIdsRaw.whereType<String>().toList()
        : <String>[];
    final periodStart = DateTime.parse(runRow['period_start'] as String);
    final periodEnd = DateTime.parse(runRow['period_end'] as String);
    final payFreq = _parsePayFreq(
        (runRow['pay_frequency'] as String?) ?? 'SEMI_MONTHLY');
    final payPeriodInput = e.PayPeriodInput(
      id: runRow['id'] as String,
      startDate: periodStart,
      endDate: periodEnd,
      cutoffDate: periodEnd,
      payDate: DateTime.parse(runRow['pay_date'] as String),
      // Derived, not stored: which period of the year this is (used by the
      // BIR withholding-tax annualisation math). Anchors on period_start.
      periodNumber: _derivePeriodNumber(periodStart, payFreq),
      payFrequency: payFreq,
    );

    onStep?.call('Loading employees…');
    // Active non-archived employees hired on or before the pay period end date.
    // When `included_employee_ids` is set on the run, restrict to that subset.
    final periodEndIso = payPeriodInput.endDate.toIso8601String().substring(0, 10);
    var empQuery = _client
        .from('employees')
        .select(
          'id, employee_number, hire_date, regularization_date, employment_type, '
          'is_rank_and_file, is_ot_eligible, is_nd_eligible, '
          'is_holiday_pay_eligible, tax_on_full_earnings, '
          'declared_wage_override, declared_wage_type, role_scorecard_id, '
          'role_scorecards(id, base_salary, wage_type, work_hours_per_day, '
          'work_days_per_week, shift_template_id)',
        )
        .eq('company_id', companyId)
        .eq('employment_status', 'ACTIVE')
        .isFilter('deleted_at', null)
        .lte('hire_date', periodEndIso);
    if (includedIds.isNotEmpty) {
      empQuery = empQuery.inFilter('id', includedIds);
    }
    final empRows = await empQuery;
    final employees = (empRows as List<dynamic>).cast<Map<String, dynamic>>();
    if (employees.isEmpty) {
      return const ComputeOutcome(
        employeeCount: 0,
        errors: [],
        warnings: ['No active employees for this pay period.'],
      );
    }

    onStep?.call('Loading attendance + adjunct data…');
    // Load shift templates once — small table, used to compute per-day
    // late-in / early-out deduction minutes from each attendance record's
    // clock-in/out vs the shift's scheduled start/end and grace windows.
    final shiftRows = await _client
        .from('shift_templates')
        .select(
          'id, start_time, end_time, grace_minutes_late, '
          'grace_minutes_early_out, break_minutes, is_overnight',
        )
        .eq('company_id', companyId);
    final shiftById = <String, Map<String, dynamic>>{
      for (final s in (shiftRows as List<dynamic>).cast<Map<String, dynamic>>())
        s['id'] as String: s,
    };

    // Load holidays authoritatively from calendar_events for this company's
    // holiday_calendars covering the pay period's range (may span two years).
    // Attendance records store a stale `day_type` at Lark-sync time; we use
    // this map to reclassify so newly-added holidays (or records imported
    // before the holiday existed) still get the correct premium / unworked
    // holiday pay treatment.
    final holidayByDate = await _loadHolidaysByDate(
      companyId,
      payPeriodInput.startDate,
      payPeriodInput.endDate,
    );

    // Do these in parallel for speed.
    final results = await Future.wait([
      _loadAttendance(employees.map((e) => e['id'] as String).toList(),
          payPeriodInput.startDate, payPeriodInput.endDate),
      _loadManualAdjustments(runId),
      _loadCashAdvances(companyId, payPeriodInput.startDate, payPeriodInput.endDate, runId),
      _loadReimbursements(companyId, payPeriodInput.startDate, payPeriodInput.endDate, runId),
      _loadActivePenaltyInstallments(
          employees.map((e) => e['id'] as String).toList(),
          payPeriodInput.endDate,
          runId),
      _loadPreviousYtd(
          employees.map((e) => e['id'] as String).toList(), payPeriodInput.endDate.year),
    ]);
    final attendanceByEmp = results[0] as Map<String, List<Map<String, dynamic>>>;
    final adjustmentsByEmp =
        results[1] as Map<String, List<Map<String, dynamic>>>;
    final cashAdvancesByEmp =
        results[2] as Map<String, List<Map<String, dynamic>>>;
    final reimbursementsByEmp =
        results[3] as Map<String, List<Map<String, dynamic>>>;
    final penaltiesByEmp =
        results[4] as Map<String, List<Map<String, dynamic>>>;
    final previousYtdByEmp = results[5] as Map<String, e.PreviousYtd>;

    // Reclassify attendance day_type when a calendar event exists on that
    // date. A worker who clocked in gets REGULAR_HOLIDAY (so the Holiday
    // Premium line pays 200%). A worker who didn't gets the unworked
    // Regular Holiday Pay (100% — paid even if not worked, per PH law).
    for (final rows in attendanceByEmp.values) {
      for (final r in rows) {
        final date = r['attendance_date'] as String;
        final iso = date.length >= 10 ? date.substring(0, 10) : date;
        final holiday = holidayByDate[iso];
        if (holiday != null) {
          r['day_type'] = holiday['day_type'];
          r['holiday_name'] = holiday['name'];
        }
      }
    }
    // Synthesize attendance rows for unworked-holiday dates so the engine
    // can pay the unworked Regular Holiday line (it only looks at rows in
    // the attendance list). Rest day + holiday on the same date uses the
    // holiday's day_type per PH law.
    for (final emp in employees) {
      final empId = emp['id'] as String;
      final rows =
          attendanceByEmp.putIfAbsent(empId, () => <Map<String, dynamic>>[]);
      final existingDates = {
        for (final r in rows) (r['attendance_date'] as String).substring(0, 10),
      };
      for (final entry in holidayByDate.entries) {
        if (existingDates.contains(entry.key)) continue;
        rows.add(<String, dynamic>{
          'id': 'synthetic-${empId}-${entry.key}',
          'employee_id': empId,
          'attendance_date': entry.key,
          'day_type': entry.value['day_type'],
          'holiday_name': entry.value['name'],
          'attendance_status': 'ABSENT',
          'actual_time_in': null,
          'actual_time_out': null,
          'approved_ot_minutes': 0,
          'shift_template_id': null,
        });
      }
    }

    onStep?.call('Building compute inputs…');
    final engineInputs = <e.EmployeePayrollInput>[];
    final warnings = <String>[];
    for (final row in employees) {
      try {
        engineInputs.add(_buildEmployeeInput(
          row: row,
          payPeriod: payPeriodInput,
          attendance: attendanceByEmp[row['id']] ?? const [],
          adjustments: adjustmentsByEmp[row['id']] ?? const [],
          cashAdvances: cashAdvancesByEmp[row['id']] ?? const [],
          reimbursements: reimbursementsByEmp[row['id']] ?? const [],
          penalties: penaltiesByEmp[row['id']] ?? const [],
          shifts: shiftById,
          previousYtd: previousYtdByEmp[row['id']] ??
              e.PreviousYtd(
                grossPay: Decimal.zero,
                taxableIncome: Decimal.zero,
                taxWithheld: Decimal.zero,
              ),
        ));
      } catch (err) {
        warnings.add('${row['employee_number']}: $err');
      }
    }

    onStep?.call('Running payroll engine…');
    // Always use the ANNUAL BIR tax table — `calculateWithholdingTax`
    // annualizes each period's income before looking up the bracket, so
    // feeding it the per-period tables (TAX_TABLE_MONTHLY /
    // TAX_TABLE_SEMI_MONTHLY) causes the annualized ₱131k income to land in
    // high semi-monthly brackets and produces wildly inflated withholding.
    final ruleset = e.RulesetInput(
      id: 'default-2026',
      version: 1,
      sssTable: SSS_TABLE,
      philhealthTable: PHILHEALTH_TABLE,
      pagibigTable: PAGIBIG_TABLE,
      taxTable: TAX_TABLE,
    );
    final result = computePayroll(payPeriodInput, ruleset, engineInputs);

    onStep?.call('Writing payslips…');
    // Recompute rule: only payslips whose Lark approval status is NULL may
    // be regenerated. Any payslip that has been sent to Lark (PENDING,
    // APPROVED, REJECTED there) is frozen — its numbers + lines stay as
    // they were. The user must Recall it (which also clears
    // lark_approval_status to NULL) before the next Recompute will touch it.
    final existingRows = await _client
        .from('payslips')
        .select('id, employee_id, lark_approval_status, gross_pay, '
            'total_deductions, net_pay')
        .eq('payroll_run_id', runId);
    final lockedEmployeeIds = <String>{};
    Decimal lockedGross = Decimal.zero;
    Decimal lockedDeductions = Decimal.zero;
    Decimal lockedNet = Decimal.zero;
    int lockedCount = 0;
    for (final r in (existingRows as List<dynamic>).cast<Map<String, dynamic>>()) {
      if (r['lark_approval_status'] != null) {
        lockedEmployeeIds.add(r['employee_id'] as String);
        lockedGross += _decOr(r['gross_pay']);
        lockedDeductions += _decOr(r['total_deductions']);
        lockedNet += _decOr(r['net_pay']);
        lockedCount++;
      }
    }

    // Delete payslips we're about to regenerate — i.e. the un-locked ones.
    // Locked payslips stay as-is; their cascaded payslip_lines are preserved.
    if (lockedEmployeeIds.isEmpty) {
      await _client.from('payslips').delete().eq('payroll_run_id', runId);
    } else {
      await _client
          .from('payslips')
          .delete()
          .eq('payroll_run_id', runId)
          .not('employee_id', 'in', '(${lockedEmployeeIds.join(',')})');
    }

    // Insert fresh payslips for employees that are NOT locked. Locked
    // employees' computed payslips from this run are discarded — their
    // on-disk frozen payslip continues to be the source of truth.
    int unlockedCount = 0;
    Decimal unlockedGross = Decimal.zero;
    Decimal unlockedDeductions = Decimal.zero;
    Decimal unlockedNet = Decimal.zero;
    for (final ps in result.payslips) {
      if (lockedEmployeeIds.contains(ps.employeeId)) continue;
      unlockedCount++;
      unlockedGross += ps.grossPay;
      unlockedDeductions += ps.totalDeductions;
      unlockedNet += ps.netPay;
      final payslipRow = await _client
          .from('payslips')
          .insert({
            'payroll_run_id': runId,
            'employee_id': ps.employeeId,
            'gross_pay': ps.grossPay.toString(),
            'total_earnings': ps.totalEarnings.toString(),
            'total_deductions': ps.totalDeductions.toString(),
            'net_pay': ps.netPay.toString(),
            'sss_ee': ps.sssEe.toString(),
            'sss_er': ps.sssEr.toString(),
            'philhealth_ee': ps.philhealthEe.toString(),
            'philhealth_er': ps.philhealthEr.toString(),
            'pagibig_ee': ps.pagibigEe.toString(),
            'pagibig_er': ps.pagibigEr.toString(),
            'withholding_tax': ps.withholdingTax.toString(),
            'ytd_gross_pay': ps.ytdGrossPay.toString(),
            'ytd_taxable_income': ps.ytdTaxableIncome.toString(),
            'ytd_tax_withheld': ps.ytdTaxWithheld.toString(),
            'pay_profile_snapshot': _snapshotToJson(ps.payProfileSnapshot),
            'approval_status': 'DRAFT_IN_REVIEW',
          })
          .select('id')
          .single();
      final payslipId = payslipRow['id'] as String;
      if (ps.lines.isNotEmpty) {
        final lineInserts = ps.lines
            .map((l) => {
                  'payslip_id': payslipId,
                  'category': l.category.name,
                  'description': l.description,
                  'quantity': ?l.quantity?.toString(),
                  'rate': ?l.rate?.toString(),
                  'multiplier': ?l.multiplier?.toString(),
                  'amount': l.amount.toString(),
                  'attendance_day_record_id': ?l.attendanceDayRecordId,
                  'manual_adjustment_id': ?l.manualAdjustmentId,
                  'penalty_installment_id': ?l.penaltyInstallmentId,
                  'cash_advance_id': ?l.cashAdvanceId,
                  'reimbursement_id': ?l.reimbursementId,
                  'rule_code': ?l.ruleCode,
                  'rule_description': ?l.ruleDescription,
                  'sort_order': l.sortOrder,
                })
            .toList();
        await _client.from('payslip_lines').insert(lineInserts);
      }
    }

    onStep?.call('Updating run totals…');
    // Run totals must include BOTH the newly-regenerated (unlocked) payslips
    // and any Lark-locked payslips we left untouched, so the summary card
    // matches the sum of on-disk payslips.
    final totalGross = unlockedGross + lockedGross;
    final totalDeductions = unlockedDeductions + lockedDeductions;
    final totalNet = unlockedNet + lockedNet;
    final totalCount = unlockedCount + lockedCount;
    await _client.from('payroll_runs').update({
      'status': 'REVIEW',
      'total_gross_pay': totalGross.toString(),
      'total_deductions': totalDeductions.toString(),
      'total_net_pay': totalNet.toString(),
      'employee_count': totalCount,
      'payslip_count': totalCount,
    }).eq('id', runId);

    onStep?.call('Done.');
    return ComputeOutcome(
      employeeCount: result.employeeCount,
      errors: [
        for (final err in result.errors) '${err.employeeId}: ${err.error}',
      ],
      warnings: warnings,
    );
  }

  // ----- loaders ----------------------------------------------------------

  /// Authoritative holiday classification for the pay-period range.
  /// Returns a map keyed by ISO date (yyyy-mm-dd) → {day_type, name}.
  /// Pulls `calendar_events` across every holiday_calendars row that the
  /// company owns whose year touches the range (handles Dec→Jan spans).
  Future<Map<String, Map<String, String>>> _loadHolidaysByDate(
      String companyId, DateTime start, DateTime end) async {
    final years = <int>{
      for (var y = start.year; y <= end.year; y++) y,
    };
    final calRows = await _client
        .from('holiday_calendars')
        .select('id, year')
        .eq('company_id', companyId)
        .inFilter('year', years.toList());
    final calIds = (calRows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((r) => r['id'] as String)
        .toList();
    if (calIds.isEmpty) return <String, Map<String, String>>{};
    final startIso = start.toIso8601String().substring(0, 10);
    final endIso = end.toIso8601String().substring(0, 10);
    final eventRows = await _client
        .from('calendar_events')
        .select('date, day_type, name')
        .inFilter('calendar_id', calIds)
        .gte('date', startIso)
        .lte('date', endIso);
    final out = <String, Map<String, String>>{};
    for (final r
        in (eventRows as List<dynamic>).cast<Map<String, dynamic>>()) {
      final d = (r['date'] as String);
      final iso = d.length >= 10 ? d.substring(0, 10) : d;
      final dayType = (r['day_type'] as String?) ?? 'WORKDAY';
      final name = (r['name'] as String?) ?? '';
      // Regular Holiday wins if two events land on the same date.
      if (out[iso] == null || dayType == 'REGULAR_HOLIDAY') {
        out[iso] = {'day_type': dayType, 'name': name};
      }
    }
    return out;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadAttendance(
      List<String> employeeIds, DateTime start, DateTime end) async {
    final rows = await _client
        .from('attendance_day_records')
        .select()
        .inFilter('employee_id', employeeIds)
        .gte('attendance_date', start.toIso8601String().substring(0, 10))
        .lte('attendance_date', end.toIso8601String().substring(0, 10));
    return _groupBy(rows, 'employee_id');
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadManualAdjustments(
      String runId) async {
    final rows = await _client
        .from('manual_adjustment_lines')
        .select()
        .eq('payroll_run_id', runId);
    return _groupBy(rows, 'employee_id');
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadCashAdvances(
      String companyId,
      DateTime periodStart,
      DateTime periodEnd,
      String runId) async {
    // Local `status` is cash_advance_status enum: PENDING / DEDUCTED / CANCELLED.
    // "Approved in Lark, not yet deducted by payroll" = status == PENDING AND
    // lark_approval_status == 'APPROVED' AND is_deducted == false.
    //
    // Date rule: only pull advances approved inside the pay period. An advance
    // approved on Mar 25 must not land in a Jan 1-15 run.
    final startIso = periodStart.toIso8601String();
    // End-of-period = endDate + 1 day (exclusive upper bound handles timezones
    // around midnight and approvals timestamped at 23:59:59.xxx).
    final endExclusiveIso = periodEnd
        .add(const Duration(days: 1))
        .toIso8601String();
    final rows = await _client
        .from('cash_advances')
        .select()
        .eq('company_id', companyId)
        .eq('status', 'PENDING')
        .eq('lark_approval_status', 'APPROVED')
        .eq('is_deducted', false)
        .gte('lark_approved_at', startIso)
        .lt('lark_approved_at', endExclusiveIso);
    // Skip-list filter — mirrors the penalty installment pattern. If HR has
    // deferred this advance for the current run, drop it; the record is
    // untouched (`is_deducted` stays false) so the next run still sees it.
    final filtered = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((r) {
      final skipped = r['skipped_payroll_run_ids'];
      return !(skipped is List && skipped.contains(runId));
    }).toList();
    return _groupBy(filtered, 'employee_id');
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadReimbursements(
      String companyId,
      DateTime periodStart,
      DateTime periodEnd,
      String runId) async {
    // Same pattern as cash advances — local status is reimbursement_status enum
    // (PENDING / PAID / CANCELLED). The "ready to pay" filter is PENDING +
    // Lark-approved + not yet paid.
    //
    // Date rule: only pull reimbursements whose `transaction_date` (when the
    // expense was incurred) falls inside the pay period.
    final startIso = periodStart.toIso8601String().substring(0, 10);
    final endIso = periodEnd.toIso8601String().substring(0, 10);
    final rows = await _client
        .from('reimbursements')
        .select()
        .eq('company_id', companyId)
        .eq('status', 'PENDING')
        .eq('lark_approval_status', 'APPROVED')
        .eq('is_paid', false)
        .gte('transaction_date', startIso)
        .lte('transaction_date', endIso);
    final filtered = (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((r) {
      final skipped = r['skipped_payroll_run_ids'];
      return !(skipped is List && skipped.contains(runId));
    }).toList();
    return _groupBy(filtered, 'employee_id');
  }

  Future<Map<String, List<Map<String, dynamic>>>>
      _loadActivePenaltyInstallments(
          List<String> employeeIds, DateTime periodEnd, String runId) async {
    // `penalty_installments` tracks per-row lifecycle via `is_deducted`.
    // The `status` filter belongs on the parent `penalties` row
    // (enum penalty_status: ACTIVE / COMPLETED / CANCELLED) — we only pull
    // installments whose parent penalty is still ACTIVE.
    //
    // Date rule: the parent penalty's `effective_date` must be on or before
    // the period end. A penalty dated Jan 20 gets picked up by a Jan 15-30
    // run but not by a Jan 1-14 run that ran earlier.
    //
    // One-per-run rule: for multi-installment penalties, only the
    // lowest-numbered pending installment applies per payroll run. Pulling
    // all pending installments at once would collapse a 3-pay-period
    // schedule into a single deduction. We order by installment_number
    // ascending and dedupe on penalty_id in Dart — PostgREST doesn't
    // support DISTINCT ON over a joined relation.
    //
    // Completion + total_deducted are maintained by trigger
    // `_penalty_installments_totals` (migration 20260418000008) — the
    // status filter above does the work of "stop pulling once satisfied".
    final periodEndIso = periodEnd.toIso8601String().substring(0, 10);
    final rows = await _client
        .from('penalty_installments')
        .select(
            '*, penalties!inner(employee_id, custom_description, status, effective_date)')
        .eq('is_deducted', false)
        .eq('penalties.status', 'ACTIVE')
        .lte('penalties.effective_date', periodEndIso)
        .inFilter('penalties.employee_id', employeeIds)
        .order('installment_number', ascending: true);

    final annotated = <Map<String, dynamic>>[];
    final seenPenalty = <String>{};
    for (final r in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
      // Skip list filter: if HR explicitly deferred this installment for
      // the current run, treat it as unavailable — the lowest remaining
      // installment (if any) takes its place, or the whole penalty waits
      // one period. Applied before the penalty-id dedupe so a skipped
      // installment #1 correctly yields to #2 (if #2 isn't also skipped).
      final skipped = r['skipped_payroll_run_ids'];
      if (skipped is List && skipped.contains(runId)) continue;

      final penaltyId = r['penalty_id'] as String;
      if (!seenPenalty.add(penaltyId)) continue; // keep lowest # only
      final p = r['penalties'] as Map<String, dynamic>?;
      r['employee_id'] = p?['employee_id'];
      r['description'] = p?['custom_description'] ?? 'Penalty';
      annotated.add(r);
    }
    return _groupBy(annotated, 'employee_id');
  }

  Future<Map<String, e.PreviousYtd>> _loadPreviousYtd(
      List<String> employeeIds, int year) async {
    // Use the latest payslip for the employee in the same calendar year
    // whose run is RELEASED. The count of prior released payslips determines
    // the tax period number — this is robust to company-specific pay-period
    // schedules (e.g. 15-30 split) where calendar-day heuristics lie.
    final rows = await _client
        .from('payslips')
        .select(
          'employee_id, ytd_gross_pay, ytd_taxable_income, ytd_tax_withheld, '
          'created_at, payroll_runs!inner(status)',
        )
        .inFilter('employee_id', employeeIds)
        .eq('payroll_runs.status', 'RELEASED')
        .gte('created_at', '$year-01-01')
        .order('created_at', ascending: false);
    final out = <String, e.PreviousYtd>{};
    final priorCounts = <String, int>{};
    final newestRow = <String, Map<String, dynamic>>{};
    for (final r in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
      final id = r['employee_id'] as String;
      priorCounts[id] = (priorCounts[id] ?? 0) + 1;
      newestRow.putIfAbsent(id, () => r);
    }
    for (final id in newestRow.keys) {
      final r = newestRow[id]!;
      out[id] = e.PreviousYtd(
        grossPay: Decimal.parse((r['ytd_gross_pay'] ?? '0').toString()),
        taxableIncome:
            Decimal.parse((r['ytd_taxable_income'] ?? '0').toString()),
        taxWithheld:
            Decimal.parse((r['ytd_tax_withheld'] ?? '0').toString()),
        priorPeriodCount: priorCounts[id] ?? 0,
      );
    }
    return out;
  }

  Map<String, List<Map<String, dynamic>>> _groupBy(
      dynamic rows, String key) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
      final id = r[key] as String?;
      if (id == null) continue;
      out.putIfAbsent(id, () => []).add(r);
    }
    return out;
  }

  // ----- input builder ----------------------------------------------------

  e.EmployeePayrollInput _buildEmployeeInput({
    required Map<String, dynamic> row,
    required e.PayPeriodInput payPeriod,
    required List<Map<String, dynamic>> attendance,
    required List<Map<String, dynamic>> adjustments,
    required List<Map<String, dynamic>> cashAdvances,
    required List<Map<String, dynamic>> reimbursements,
    required List<Map<String, dynamic>> penalties,
    required Map<String, Map<String, dynamic>> shifts,
    required e.PreviousYtd previousYtd,
  }) {
    final employeeId = row['id'] as String;
    final roleCard = row['role_scorecards'] as Map<String, dynamic>?;
    if (roleCard == null) {
      throw StateError(
        'Employee ${row['employee_number']} has no role scorecard — '
        'assign one before running payroll.',
      );
    }
    // Wage resolution:
    //   - Role scorecard is ALWAYS the basis for actual payroll earnings.
    //     (base_salary + wage_type drive the per-day Basic Pay.)
    //   - The declared-wage override is a STATUTORY/TAX-only lever. It flows
    //     into the engine's `statutoryOverride` field, where the engine uses
    //     it exclusively for SSS/PhilHealth/Pag-IBIG contribution bases and
    //     the tax-basic-pay calculation. The override must NEVER appear in
    //     the employee's actual gross earnings.
    //
    //   The override is applied only when BOTH the amount AND the type are
    //   set AND the amount is strictly positive — avoids partial-override
    //   mismatches and zero-value passthrough.
    final wageTypeStr = (roleCard['wage_type'] as String?) ?? 'DAILY';
    final baseRate =
        Decimal.tryParse((roleCard['base_salary'] ?? '0').toString()) ??
            Decimal.zero;
    final wageType = _parseWageType(wageTypeStr);

    final overrideRaw = row['declared_wage_override'];
    final overrideTypeRaw = row['declared_wage_type'];
    final overrideAmount = overrideRaw == null
        ? null
        : Decimal.tryParse(overrideRaw.toString());
    final statutoryOverride = (overrideTypeRaw != null &&
            overrideAmount != null &&
            overrideAmount > Decimal.zero)
        ? e.StatutoryOverride(
            baseRate: overrideAmount,
            wageType: _parseWageType(overrideTypeRaw as String),
          )
        : null;
    final hoursPerDay = (roleCard['work_hours_per_day'] as int?) ?? 8;

    final profile = e.PayProfileInput(
      employeeId: employeeId,
      wageType: wageType,
      baseRate: baseRate,
      payFrequency: payPeriod.payFrequency,
      standardWorkDaysPerMonth: 26,
      standardHoursPerDay: hoursPerDay,
      isBenefitsEligible: true,
      isOtEligible: row['is_ot_eligible'] as bool? ?? true,
      isNdEligible: row['is_nd_eligible'] as bool? ?? true,
      riceSubsidy: Decimal.zero,
      clothingAllowance: Decimal.zero,
      laundryAllowance: Decimal.zero,
      medicalAllowance: Decimal.zero,
      transportationAllowance: Decimal.zero,
      mealAllowance: Decimal.zero,
      communicationAllowance: Decimal.zero,
    );

    final regularization = e.EmployeeRegularizationInput(
      employeeId: employeeId,
      employmentType: _parseEmploymentType(row['employment_type'] as String),
      regularizationDate: row['regularization_date'] == null
          ? null
          : DateTime.parse(row['regularization_date'] as String),
      hireDate: DateTime.parse(row['hire_date'] as String),
    );

    // Employee's default shift via role scorecard — used as fallback for
    // attendance rows that don't carry their own shift_template_id (common
    // for Lark-synced attendance without a specific per-day shift link).
    // Mirrors the UI behaviour in attendance_tab.dart _buildRows.
    final defaultShiftId = roleCard['shift_template_id'] as String?;
    final defaultShift =
        defaultShiftId == null ? null : shifts[defaultShiftId];

    final attendanceInputs =
        attendance
            .map((r) => _attendanceFromRow(r, shifts, defaultShift))
            .whereType<e.AttendanceDayInput>()
            .toList();

    final manualAdjustments = adjustments.map((a) {
      final cat = a['category'] as String;
      final isEarning = cat == 'ADJUSTMENT_ADD';
      return e.ManualAdjustment(
        id: a['id'] as String?,
        employeeId: employeeId,
        type: isEarning ? 'EARNING' : 'DEDUCTION',
        category: isEarning
            ? e.PayslipLineCategory.ADJUSTMENT_ADD
            : e.PayslipLineCategory.ADJUSTMENT_DEDUCT,
        description: a['description'] as String? ?? '',
        amount: Decimal.parse((a['amount'] ?? '0').toString()),
        remarks: a['remarks'] as String?,
      );
    }).toList();

    final reimbursementInputs = reimbursements.map((r) => e.ReimbursementInput(
          id: r['id'] as String,
          amount: Decimal.parse((r['amount'] ?? '0').toString()),
          description: (r['reason'] as String?) ??
              (r['reimbursement_type'] as String?) ??
              'Reimbursement',
        )).toList();

    final cashAdvanceLines = cashAdvances.map((c) => e.CashAdvanceDeductionLine(
          cashAdvanceId: c['id'] as String,
          description: (c['reason'] as String?) ?? 'Cash Advance',
          amount: Decimal.parse((c['amount'] ?? '0').toString()),
        )).toList();

    final penaltyLines = penalties.map((p) => e.PenaltyDeduction(
          installmentId: p['id'] as String,
          penaltyId: p['penalty_id'] as String,
          description: (p['description'] as String?) ?? 'Penalty',
          amount: Decimal.parse((p['amount'] ?? p['installment_amount'] ?? '0').toString()),
        )).toList();

    return e.EmployeePayrollInput(
      profile: profile,
      regularization: regularization,
      attendance: attendanceInputs,
      manualAdjustments: manualAdjustments,
      reimbursements: reimbursementInputs,
      cashAdvanceDeductions: cashAdvanceLines,
      previousYtd: previousYtd,
      taxOnFullEarnings: row['tax_on_full_earnings'] as bool? ?? false,
      statutoryOverride: statutoryOverride,
      penaltyDeductions: penaltyLines,
    );
  }

  e.AttendanceDayInput? _attendanceFromRow(
    Map<String, dynamic> r,
    Map<String, Map<String, dynamic>> shifts,
    Map<String, dynamic>? defaultShift,
  ) {
    // Day-type rule, mirrors AttendanceRowVm.dayType:
    //   - Holiday day types (REGULAR_HOLIDAY / SPECIAL_HOLIDAY /
    //     SPECIAL_WORKING) are authoritative — keep them.
    //   - Otherwise, the per-record `shift_template_id` decides:
    //     null → REST_DAY (no scheduled work, even if the row's stored
    //     day_type still says WORKDAY from a stale import).
    //     non-null → WORKDAY (scheduled, even if stored day_type says
    //     REST_DAY because admin manually added a shift later).
    //   Aligns with how Lark sync sets these two columns at import time
    //   and prevents premium-pay drift when the columns disagree.
    final rawDayType = _parseDayType(r['day_type'] as String);
    final hasShiftAssigned = (r['shift_template_id'] as String?) != null;
    final dayType = (rawDayType == e.DayType.REGULAR_HOLIDAY ||
            rawDayType == e.DayType.SPECIAL_HOLIDAY ||
            rawDayType == e.DayType.SPECIAL_WORKING)
        ? rawDayType
        : (hasShiftAssigned ? e.DayType.WORKDAY : e.DayType.REST_DAY);
    final inAt = r['actual_time_in'] == null
        ? null
        : DateTime.parse(r['actual_time_in'] as String);
    final outAt = r['actual_time_out'] == null
        ? null
        : DateTime.parse(r['actual_time_out'] as String);
    double worked = 0;
    if (inAt != null && outAt != null) {
      // Seconds/60 preserves fractional minutes — `.inMinutes` truncates.
      worked = outAt.difference(inAt).inSeconds / 60.0;
      if (worked < 0) worked = 0;
      // Subtract break minutes so `workedMinutes` reflects paid work time
      // only. `break_minutes_applied` on the attendance row is the per-day
      // override ("no break today" → 0). Fall back to the shift template's
      // default when no override is set. Mirrors `_RowVM.workedMinutes` in
      // attendance_tab.dart so the admin-visible number matches the payslip.
      final shiftId0 = r['shift_template_id'] as String?;
      final s0 = (shiftId0 == null ? null : shifts[shiftId0]) ?? defaultShift;
      final breakApplied = (r['break_minutes_applied'] as int?)?.toDouble();
      final breakMin = breakApplied ??
          (s0?['break_minutes'] as int?)?.toDouble() ??
          60.0;
      worked = (worked - breakMin).clamp(0.0, worked);
    }
    final status = (r['attendance_status'] as String? ?? '').toUpperCase();
    final isAbsent = status == 'ABSENT';
    final approvedOtMinutes =
        ((r['approved_ot_minutes'] as int?) ?? 0).toDouble();

    // Late/Undertime deduction — deficit model ported from payrollos
    // (`lib/utils/timezone.ts:425-453`). Collapses late-in + early-out +
    // lunch into a single "shortfall against expected work hours":
    //
    //   expectedWorkMinutes = shiftDuration - shiftBreak
    //   schedIn  = max(actualIn,  schedStart)
    //   schedOut = min(actualOut, schedEnd)
    //   schedGross = max(0, schedOut - schedIn)
    //   schedBreak = schedGross > 300 ? breakMinutesApplied|shiftBreak : 0
    //   schedWorked = max(0, schedGross - schedBreak)
    //   deduction  = max(0, expectedWorkMinutes - schedWorked)
    //
    // Holiday / rest-day rule: a non-WORKDAY does not produce a deduction —
    // the day's worked time is paid at holiday/rest premium, not regular
    // shift hours. Only WORKDAY rows go through the deficit calc.
    //
    // OT minutes (manual via approval flags) are still derived per-side from
    // clock vs schedule.
    double deductionMinutes = 0;
    double derivedOtMinutes = 0;
    final shiftId = r['shift_template_id'] as String?;
    // Fall back to the employee's role-scorecard default shift when the
    // attendance record doesn't have its own shift linked. This matches the
    // UI stats — without the fallback, Lark-synced rows (which never carry
    // a shift_template_id) would compute zero late/UT minutes.
    final shift =
        (shiftId == null ? null : shifts[shiftId]) ?? defaultShift;
    if (shift != null && dayType == e.DayType.WORKDAY) {
      final date = DateTime.parse(r['attendance_date'] as String);
      final startTime = shift['start_time'] as String?;
      final endTime = shift['end_time'] as String?;
      final isOvernight = shift['is_overnight'] as bool? ?? false;
      final shiftBreakMinutes =
          ((shift['break_minutes'] as int?) ?? 60).toDouble();
      final breakMinutesApplied =
          (r['break_minutes_applied'] as int?)?.toDouble();
      final lateInApproved = r['late_in_approved'] as bool? ?? false;
      final earlyOutApproved = r['early_out_approved'] as bool? ?? false;
      final earlyInApproved = r['early_in_approved'] as bool? ?? false;
      final lateOutApproved = r['late_out_approved'] as bool? ?? false;

      DateTime? schedStart;
      DateTime? schedEnd;
      if (startTime != null) schedStart = _applyHhMm(date, startTime);
      if (endTime != null) {
        schedEnd = _applyHhMm(date, endTime);
        if (isOvernight) {
          schedEnd = schedEnd.add(const Duration(days: 1));
        }
      }

      // Deficit-model deduction (lateIn + earlyOut + lunch in one number).
      // Also surfaces IMPLICIT OT: when the applied break is shorter than
      // the shift's default break, the employee worked through part of
      // their break — any schedWorked above expectedWorkMinutes becomes OT.
      // A no-break 9am-6pm day registers as 60 min OT instead of 60 min
      // of invisible extra work. The late-vs-OT netting downstream then
      // nets undertime against this implicit OT.
      if (inAt != null &&
          outAt != null &&
          schedStart != null &&
          schedEnd != null) {
        final shiftMins =
            schedEnd.difference(schedStart).inSeconds / 60.0;
        if (shiftMins > 0) {
          final expectedWorkMinutes = shiftMins - shiftBreakMinutes;
          final actualBreak = breakMinutesApplied ?? shiftBreakMinutes;
          final tInLocal = inAt.toLocal();
          final tOutLocal = outAt.toLocal();
          final effectiveIn = lateInApproved
              ? schedStart
              : (tInLocal.isAfter(schedStart) ? tInLocal : schedStart);
          final effectiveOut = earlyOutApproved
              ? schedEnd
              : (tOutLocal.isBefore(schedEnd) ? tOutLocal : schedEnd);
          final schedGross =
              effectiveOut.difference(effectiveIn).inSeconds / 60.0;
          if (schedGross <= 0) {
            deductionMinutes = expectedWorkMinutes;
          } else {
            final schedBreak = schedGross > 300 ? actualBreak : 0.0;
            final schedWorked = schedGross - schedBreak;
            final deficit = expectedWorkMinutes - schedWorked;
            if (deficit > 0) {
              deductionMinutes = deficit;
            } else if (deficit < 0) {
              derivedOtMinutes += -deficit;
            }
          }
        }
      }

      // Manual OT via approval flags (admin toggled "Approve Early In OT" /
      // "Approve Late Out OT" in the edit dialog).
      if (inAt != null && earlyInApproved && schedStart != null) {
        final diff =
            schedStart.difference(inAt.toLocal()).inSeconds / 60.0;
        if (diff > 0) derivedOtMinutes += diff;
      }
      if (outAt != null && lateOutApproved && schedEnd != null) {
        final diff =
            outAt.toLocal().difference(schedEnd).inSeconds / 60.0;
        if (diff > 0) derivedOtMinutes += diff;
      }
    }

    // Effective OT priority (mirrors AttendanceRowVm.overtimeMinutes):
    //   1. Lark-approved duration (`approved_ot_minutes > 0`) — hard cap at
    //      the approved amount, ignoring any clock-out overage. A 36-min
    //      approval with a 37-min actual stay pays 36.
    //   2. Admin-toggled flags (`late_out_approved` / `early_in_approved`)
    //      with no stored duration — compute from clock diffs. No ceiling
    //      because the dialog doesn't capture one.
    //   3. Implicit break-through OT rolled into derivedOtMinutes.
    //
    // Zero when the employee didn't clock in — protects against stale
    // Lark-synced OT on unworked days.
    double ot;
    if (inAt == null) {
      ot = 0;
    } else if (approvedOtMinutes > 0) {
      ot = approvedOtMinutes;
    } else {
      ot = derivedOtMinutes;
    }

    // Per-day rate override — honored by every engine branch that calls
    // `getDayRates(...)`. Without this plumbing, batch-edit rate overrides
    // were silently ignored and compute would use the scorecard's base rate.
    Decimal? dailyRateOverride;
    final rateRaw = r['daily_rate_override'];
    if (rateRaw != null) {
      final parsed = Decimal.tryParse(rateRaw.toString());
      if (parsed != null) dailyRateOverride = parsed;
    }

    // Night-differential minutes — the intersection of the employee's
    // effective work window with PH's 22:00–06:00 ND band. "Effective"
    // means we clamp clock-in to shift start when early-in is NOT approved,
    // and clamp clock-out to shift end when late-out is NOT approved — so
    // unapproved OT past 22:00 doesn't sneak in. Approved OT naturally
    // extends the window and contributes ND minutes as expected.
    double ndMinutes = 0;
    if (inAt != null && outAt != null) {
      final tInLocal = inAt.toLocal();
      final tOutLocal = outAt.toLocal();
      DateTime effIn = tInLocal;
      DateTime effOut = tOutLocal;
      final earlyInApproved = r['early_in_approved'] as bool? ?? false;
      final lateOutApproved = r['late_out_approved'] as bool? ?? false;
      if (shift != null) {
        final date = DateTime.parse(r['attendance_date'] as String);
        final startTime = shift['start_time'] as String?;
        final endTime = shift['end_time'] as String?;
        final isOvernight = shift['is_overnight'] as bool? ?? false;
        if (startTime != null && !earlyInApproved) {
          final shiftStart = _applyHhMm(date, startTime);
          if (tInLocal.isBefore(shiftStart)) effIn = shiftStart;
        }
        if (endTime != null && !lateOutApproved) {
          var shiftEnd = _applyHhMm(date, endTime);
          if (isOvernight) shiftEnd = shiftEnd.add(const Duration(days: 1));
          if (tOutLocal.isAfter(shiftEnd)) effOut = shiftEnd;
        }
      }
      ndMinutes = _nightDiffMinutesInRange(effIn, effOut);
    }

    return e.AttendanceDayInput(
      id: r['id'] as String,
      attendanceDate: DateTime.parse(r['attendance_date'] as String),
      dayType: dayType,
      holidayName: r['holiday_name'] as String?,
      workedMinutes: worked,
      deductionMinutes: deductionMinutes,
      absentMinutes: isAbsent ? 480.0 : 0.0,
      otMinutes: dayType == e.DayType.WORKDAY ? ot : 0.0,
      otEarlyInMinutes: 0.0,
      otLateOutMinutes: 0.0,
      overtimeRestDayMinutes: dayType == e.DayType.REST_DAY ? ot : 0.0,
      overtimeHolidayMinutes:
          dayType == e.DayType.REGULAR_HOLIDAY ||
                  dayType == e.DayType.SPECIAL_HOLIDAY
              ? ot
              : 0.0,
      earlyInApproved: r['early_in_approved'] as bool? ?? false,
      lateOutApproved: r['late_out_approved'] as bool? ?? false,
      nightDiffMinutes: ndMinutes,
      isOnLeave: status.contains('LEAVE'),
      leaveIsPaid: false,
      dailyRateOverride: dailyRateOverride,
    );
  }

  /// Sum of minutes inside `[start, end]` that fall within PH's night-diff
  /// window of `22:00–06:00` local time. Handles multi-day spans (e.g.
  /// overnight shifts) by walking each calendar day the window touches and
  /// intersecting with its evening ND segment (`22:00 → 06:00 next day`).
  double _nightDiffMinutesInRange(DateTime start, DateTime end) {
    if (!end.isAfter(start)) return 0;
    double total = 0;
    var cursor = DateTime(start.year, start.month, start.day);
    // Iterate every calendar day the [start, end] span overlaps so we
    // catch ND segments that begin the previous day (e.g. 22:00 yesterday
    // → 06:00 today still contributes when `start` is 05:00 today).
    final stop = DateTime(end.year, end.month, end.day)
        .add(const Duration(days: 2));
    while (cursor.isBefore(stop)) {
      final ndStart = DateTime(cursor.year, cursor.month, cursor.day, 22);
      final ndEnd = ndStart.add(const Duration(hours: 8));
      if (ndEnd.isBefore(start) || ndStart.isAfter(end)) {
        cursor = cursor.add(const Duration(days: 1));
        continue;
      }
      final s = ndStart.isAfter(start) ? ndStart : start;
      final e = ndEnd.isBefore(end) ? ndEnd : end;
      if (e.isAfter(s)) total += e.difference(s).inSeconds / 60.0;
      cursor = cursor.add(const Duration(days: 1));
    }
    return total;
  }

  /// Combine a calendar date with a `HH:MM[:SS]` time string (local TZ) into
  /// a DateTime at that local wall-clock time. Used by late/undertime
  /// calculations against shift scheduled times.
  DateTime _applyHhMm(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  /// Lenient Decimal parse — accepts null / String / num and returns
  /// Decimal.zero on any failure. Used when reading numeric columns
  /// from Postgres that can come back as string OR number.
  Decimal _decOr(Object? v) {
    if (v == null) return Decimal.zero;
    return Decimal.tryParse(v.toString()) ?? Decimal.zero;
  }

  // ----- enum parsing -----------------------------------------------------

  e.PayFrequency _parsePayFreq(String s) => switch (s.toUpperCase()) {
        'MONTHLY' => e.PayFrequency.MONTHLY,
        'SEMI_MONTHLY' || 'SEMI-MONTHLY' => e.PayFrequency.SEMI_MONTHLY,
        'BI_WEEKLY' || 'BI-WEEKLY' || 'BIWEEKLY' => e.PayFrequency.BI_WEEKLY,
        'WEEKLY' => e.PayFrequency.WEEKLY,
        _ => e.PayFrequency.SEMI_MONTHLY,
      };

  /// Which period of the year `periodStart` falls into, 1-based. Used by
  /// the BIR withholding-tax annualisation math in `statutory_calculator`
  /// — projected annual tax = (YTD taxable / periodNumber) × totalPeriods.
  ///
  ///   - MONTHLY       → month of year                          (1..12)
  ///   - SEMI_MONTHLY  → (month × 2) − 1 if day ≤ 15, else × 2   (1..24)
  ///   - BI_WEEKLY     → ⌈day-of-year / 14⌉                     (1..27)
  ///   - WEEKLY        → ⌈day-of-year / 7⌉                      (1..53)
  int _derivePeriodNumber(DateTime periodStart, e.PayFrequency freq) {
    switch (freq) {
      case e.PayFrequency.MONTHLY:
        return periodStart.month;
      case e.PayFrequency.SEMI_MONTHLY:
        return (periodStart.month - 1) * 2 + (periodStart.day <= 15 ? 1 : 2);
      case e.PayFrequency.BI_WEEKLY:
        final doy = periodStart
                .difference(DateTime(periodStart.year, 1, 1))
                .inDays +
            1;
        return ((doy - 1) ~/ 14) + 1;
      case e.PayFrequency.WEEKLY:
        final doy = periodStart
                .difference(DateTime(periodStart.year, 1, 1))
                .inDays +
            1;
        return ((doy - 1) ~/ 7) + 1;
    }
  }

  e.WageType _parseWageType(String s) => switch (s.toUpperCase()) {
        'MONTHLY' => e.WageType.MONTHLY,
        'DAILY' => e.WageType.DAILY,
        'HOURLY' => e.WageType.HOURLY,
        _ => e.WageType.DAILY,
      };

  e.EmploymentType _parseEmploymentType(String s) => switch (s.toUpperCase()) {
        'REGULAR' => e.EmploymentType.REGULAR,
        'PROBATIONARY' => e.EmploymentType.PROBATIONARY,
        'CONTRACTUAL' => e.EmploymentType.CONTRACTUAL,
        'CONSULTANT' => e.EmploymentType.CONSULTANT,
        'INTERN' => e.EmploymentType.INTERN,
        _ => e.EmploymentType.PROBATIONARY,
      };

  e.DayType _parseDayType(String s) => switch (s.toUpperCase()) {
        'WORKDAY' => e.DayType.WORKDAY,
        'REST_DAY' => e.DayType.REST_DAY,
        'REGULAR_HOLIDAY' => e.DayType.REGULAR_HOLIDAY,
        'SPECIAL_HOLIDAY' => e.DayType.SPECIAL_HOLIDAY,
        'SPECIAL_WORKING' || 'SPECIAL_WORKING_DAY' =>
          e.DayType.SPECIAL_WORKING,
        _ => e.DayType.WORKDAY,
      };

  Map<String, dynamic> _snapshotToJson(e.PayProfileInput p) => {
        'employeeId': p.employeeId,
        'wageType': p.wageType.name,
        'baseRate': p.baseRate.toString(),
        'payFrequency': p.payFrequency.name,
        'standardWorkDaysPerMonth': p.standardWorkDaysPerMonth,
        'standardHoursPerDay': p.standardHoursPerDay,
        'isBenefitsEligible': p.isBenefitsEligible,
        'isOtEligible': p.isOtEligible,
        'isNdEligible': p.isNdEligible,
      };
}

/// Outcome of a compute run — used by the UI to show success / warnings / errors.
class ComputeOutcome {
  final int employeeCount;
  final List<String> errors;
  final List<String> warnings;
  const ComputeOutcome({
    required this.employeeCount,
    required this.errors,
    required this.warnings,
  });
  bool get hasProblems => errors.isNotEmpty || warnings.isNotEmpty;
}

final payrollComputeServiceProvider = Provider<PayrollComputeService>(
  (ref) => PayrollComputeService(Supabase.instance.client),
);
