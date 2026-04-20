import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lookup providers used by the employee profile screen for fields that only
/// exist as IDs on the employees row (department, hiring entity, manager).

final departmentNameProvider =
    FutureProvider.family<String?, String>((ref, id) async {
  final row = await Supabase.instance.client
      .from('departments')
      .select('name')
      .eq('id', id)
      .maybeSingle();
  return row?['name'] as String?;
});

final hiringEntityNameProvider =
    FutureProvider.family<String?, String>((ref, id) async {
  final row = await Supabase.instance.client
      .from('hiring_entities')
      .select('name')
      .eq('id', id)
      .maybeSingle();
  return row?['name'] as String?;
});

final managerNameProvider =
    FutureProvider.family<String?, String>((ref, id) async {
  final row = await Supabase.instance.client
      .from('employees')
      .select('first_name, last_name')
      .eq('id', id)
      .maybeSingle();
  if (row == null) return null;
  return [row['first_name'], row['last_name']]
      .where((s) => s != null && (s as String).isNotEmpty)
      .join(' ');
});

// --- Financials (penalties / cash advances / reimbursements) --------------

enum FinancialKind { penalties, cashAdvances, reimbursements }

extension FinancialKindTable on FinancialKind {
  String get table => switch (this) {
        FinancialKind.penalties => 'penalties',
        FinancialKind.cashAdvances => 'cash_advances',
        FinancialKind.reimbursements => 'reimbursements',
      };
  String get amountKey => switch (this) {
        FinancialKind.penalties => 'total_amount',
        FinancialKind.cashAdvances => 'amount',
        FinancialKind.reimbursements => 'amount',
      };
}

class FinancialsQuery {
  final String employeeId;
  final FinancialKind kind;
  const FinancialsQuery({required this.employeeId, required this.kind});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FinancialsQuery &&
          other.employeeId == employeeId &&
          other.kind == kind);

  @override
  int get hashCode => Object.hash(employeeId, kind);
}

final financialsByEmployeeProvider =
    FutureProvider.family<List<Map<String, dynamic>>, FinancialsQuery>(
        (ref, q) async {
  // Penalty rows embed their installments so the UI can show "X paid of N"
  // + progress bar without a second round trip. CA/Reimbursement kinds
  // don't have installment tables so we fetch plain rows, then enrich with
  // the consuming payslip id (resolved via payslip_lines) so the Financials
  // tab can render a "View payslip →" link for already-deducted records.
  final client = Supabase.instance.client;
  final fields = q.kind == FinancialKind.penalties
      ? '*, penalty_installments(id, installment_number, amount, is_deducted)'
      : '*';
  final rawRows = await client
      .from(q.kind.table)
      .select(fields)
      .eq('employee_id', q.employeeId)
      .order('created_at', ascending: false)
      .limit(200);
  final rows = (rawRows as List<dynamic>).cast<Map<String, dynamic>>();

  if (q.kind == FinancialKind.penalties) return rows;

  // Enrichment: for deducted CA or paid reimbursement rows, fetch the
  // payslip_lines whose FK points at them and attach the payslip id. One
  // extra roundtrip, only when there are settled rows to resolve.
  final fkColumn = q.kind == FinancialKind.cashAdvances
      ? 'cash_advance_id'
      : 'reimbursement_id';
  final settledFlag = q.kind == FinancialKind.cashAdvances
      ? 'is_deducted'
      : 'is_paid';
  final settledIds = rows
      .where((r) => r[settledFlag] == true)
      .map((r) => r['id'] as String)
      .toList();
  if (settledIds.isEmpty) return rows;

  final lineRows = await client
      .from('payslip_lines')
      .select('$fkColumn, payslip_id')
      .inFilter(fkColumn, settledIds);
  final payslipByFk = <String, String>{};
  for (final lr in (lineRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    final fk = lr[fkColumn] as String?;
    final payslipId = lr['payslip_id'] as String?;
    if (fk != null && payslipId != null) payslipByFk[fk] = payslipId;
  }
  return rows.map((r) {
    final pid = payslipByFk[r['id'] as String];
    return pid == null ? r : {...r, '_payslip_id': pid};
  }).toList();
});

// --- Leave balances -------------------------------------------------------

class LeaveBalanceQuery {
  final String employeeId;
  final int year;
  const LeaveBalanceQuery({required this.employeeId, required this.year});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LeaveBalanceQuery &&
          other.employeeId == employeeId &&
          other.year == year);

  @override
  int get hashCode => Object.hash(employeeId, year);
}

final leaveBalancesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, LeaveBalanceQuery>(
        (ref, q) async {
  final rows = await Supabase.instance.client
      .from('leave_balances')
      .select('*, leave_types!inner(code, name)')
      .eq('employee_id', q.employeeId)
      .eq('year', q.year);
  return (rows as List<dynamic>).cast<Map<String, dynamic>>();
});

// --- Employee documents ---------------------------------------------------

final employeeDocumentsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, employeeId) async {
  final rows = await Supabase.instance.client
      .from('employee_documents')
      .select()
      .eq('employee_id', employeeId)
      .isFilter('deleted_at', null)
      .order('created_at', ascending: false);
  return (rows as List<dynamic>).cast<Map<String, dynamic>>();
});

// --- Timeline aggregation -------------------------------------------------

enum TimelineKind {
  event,
  payslip,
  leave,
  penalty,
  cashAdvance,
  reimbursement,
  document,
}

class TimelineEntry {
  final TimelineKind kind;
  final DateTime date;
  final String title;
  final String status;
  final String? subtitle;
  final String? code;
  final String? dateRange;
  final String? amountText;
  const TimelineEntry({
    required this.kind,
    required this.date,
    required this.title,
    required this.status,
    this.subtitle,
    this.code,
    this.dateRange,
    this.amountText,
  });
}

final timelineProvider =
    FutureProvider.family<List<TimelineEntry>, String>((ref, employeeId) async {
  final client = Supabase.instance.client;
  final entries = <TimelineEntry>[];

  // Payslips with pay period range (period fields now live on payroll_runs).
  final payslipRows = await client
      .from('payslips')
      .select('id, net_pay, approval_status, created_at, '
          'payroll_runs!inner(period_start, period_end, pay_date)')
      .eq('employee_id', employeeId)
      .order('created_at', ascending: false)
      .limit(50);
  for (final r in (payslipRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    final run = r['payroll_runs'] as Map<String, dynamic>?;
    final start = run?['period_start'] as String?;
    final end = run?['period_end'] as String?;
    entries.add(TimelineEntry(
      kind: TimelineKind.payslip,
      date: DateTime.parse(r['created_at'] as String),
      title: 'Payslip — ${start ?? '?'} – ${end ?? '?'}',
      status: r['approval_status'] as String? ?? 'DRAFT_IN_REVIEW',
      subtitle: 'Payslip',
      dateRange: (start != null && end != null) ? '$start – $end' : null,
      amountText: r['net_pay']?.toString(),
    ));
  }

  // Leave requests
  final leaveRows = await client
      .from('leave_requests')
      .select('*, leave_types(name, code)')
      .eq('employee_id', employeeId)
      .order('start_date', ascending: false)
      .limit(50);
  for (final r in (leaveRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    final type = (r['leave_types'] as Map?)?['name'] ??
        (r['leave_types'] as Map?)?['code'] ??
        'Leave';
    entries.add(TimelineEntry(
      kind: TimelineKind.leave,
      date: DateTime.parse(r['start_date'] as String),
      title: 'Leave — $type',
      status: r['status'] as String? ?? 'PENDING',
      subtitle: 'Leave',
      dateRange: '${r['start_date']} – ${r['end_date']}',
    ));
  }

  // Penalties
  final penaltyRows = await client
      .from('penalties')
      .select()
      .eq('employee_id', employeeId)
      .order('created_at', ascending: false)
      .limit(50);
  for (final r in (penaltyRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    entries.add(TimelineEntry(
      kind: TimelineKind.penalty,
      date: DateTime.parse(r['created_at'] as String),
      title: (r['custom_description'] as String?) ?? 'Penalty',
      status: r['status'] as String? ?? 'ACTIVE',
      subtitle: 'Penalty',
      amountText: r['total_amount']?.toString(),
    ));
  }

  // Cash advances
  final caRows = await client
      .from('cash_advances')
      .select()
      .eq('employee_id', employeeId)
      .order('created_at', ascending: false)
      .limit(50);
  for (final r in (caRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    entries.add(TimelineEntry(
      kind: TimelineKind.cashAdvance,
      date: DateTime.parse(r['created_at'] as String),
      title: (r['reason'] as String?) ?? 'Cash Advance',
      status: r['status'] as String? ?? 'PENDING',
      subtitle: 'Cash Advance',
      amountText: r['amount']?.toString(),
    ));
  }

  // Reimbursements
  final rbRows = await client
      .from('reimbursements')
      .select()
      .eq('employee_id', employeeId)
      .order('created_at', ascending: false)
      .limit(50);
  for (final r in (rbRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    entries.add(TimelineEntry(
      kind: TimelineKind.reimbursement,
      date: DateTime.parse(r['created_at'] as String),
      title: (r['reason'] as String?) ??
          (r['reimbursement_type'] as String?) ??
          'Reimbursement',
      status: r['status'] as String? ?? 'PENDING',
      subtitle: 'Reimbursement',
      amountText: r['amount']?.toString(),
    ));
  }

  // Employment events
  final eventRows = await client
      .from('employment_events')
      .select()
      .eq('employee_id', employeeId)
      .order('event_date', ascending: false)
      .limit(50);
  for (final r in (eventRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    entries.add(TimelineEntry(
      kind: TimelineKind.event,
      date: DateTime.parse(r['event_date'] as String),
      title: (r['event_type'] as String? ?? 'Event').replaceAll('_', ' '),
      status: r['status'] as String? ?? 'PENDING',
      subtitle: 'Event',
    ));
  }

  // Documents generated for this employee
  final docRows = await client
      .from('employee_documents')
      .select()
      .eq('employee_id', employeeId)
      .isFilter('deleted_at', null)
      .order('created_at', ascending: false)
      .limit(50);
  for (final r in (docRows as List<dynamic>).cast<Map<String, dynamic>>()) {
    final type = (r['document_type'] as String?)?.replaceAll('_', ' ');
    final title = (r['title'] as String?) ??
        (r['file_name'] as String?) ??
        type ??
        'Document';
    entries.add(TimelineEntry(
      kind: TimelineKind.document,
      date: DateTime.parse(r['created_at'] as String),
      title: 'Document — $title',
      status: r['status'] as String? ?? 'ISSUED',
      subtitle: type ?? 'Document',
    ));
  }

  entries.sort((a, b) => b.date.compareTo(a.date));
  return entries;
});
