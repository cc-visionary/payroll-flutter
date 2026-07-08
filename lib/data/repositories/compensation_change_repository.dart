import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/compensation_change.dart';

/// Pure builder for the INSERT payload. Kept top-level (no Supabase dependency)
/// so it is unit-testable in isolation, mirroring `buildInsertPayload` in
/// employee_document_repository.dart. `effective_date` is written date-only.
Map<String, dynamic> buildCompensationChangeInsert({
  required String id,
  required String companyId,
  required String employeeId,
  required String changeType,
  required String status,
  required DateTime effectiveDate,
  Decimal? prevBaseSalary,
  Decimal? newBaseSalary,
  String? prevWageType,
  String? newWageType,
  String? prevScorecardId,
  String? newScorecardId,
  required String reason,
  required String initiatedById,
}) {
  return {
    'id': id,
    'company_id': companyId,
    'employee_id': employeeId,
    'change_type': changeType,
    'status': status,
    'effective_date': effectiveDate.toIso8601String().substring(0, 10),
    'prev_base_salary': prevBaseSalary?.toString(),
    'new_base_salary': newBaseSalary?.toString(),
    'prev_wage_type': prevWageType,
    'new_wage_type': newWageType,
    'prev_scorecard_id': prevScorecardId,
    'new_scorecard_id': newScorecardId,
    'reason': reason,
    'initiated_by_id': initiatedById,
    if (status == 'APPLIED') 'applied_at': DateTime.now().toUtc().toIso8601String(),
  };
}

class CompensationChangeRepository {
  final SupabaseClient _client;
  CompensationChangeRepository(this._client);

  Future<CompensationChange> insert({
    required String companyId,
    required String employeeId,
    required String changeType,
    required DateTime effectiveDate,
    Decimal? prevBaseSalary,
    Decimal? newBaseSalary,
    String? prevWageType,
    String? newWageType,
    String? prevScorecardId,
    String? newScorecardId,
    required String reason,
    required String initiatedById,
    required bool applyImmediately,
  }) async {
    final id = const Uuid().v4();
    final payload = buildCompensationChangeInsert(
      id: id,
      companyId: companyId,
      employeeId: employeeId,
      changeType: changeType,
      status: applyImmediately ? 'APPLIED' : 'SCHEDULED',
      effectiveDate: effectiveDate,
      prevBaseSalary: prevBaseSalary,
      newBaseSalary: newBaseSalary,
      prevWageType: prevWageType,
      newWageType: newWageType,
      prevScorecardId: prevScorecardId,
      newScorecardId: newScorecardId,
      reason: reason,
      initiatedById: initiatedById,
    );
    final row = await _client
        .from('compensation_changes')
        .insert(payload)
        .select('*')
        .single();
    return CompensationChange.fromRow(row);
  }

  Future<List<CompensationChange>> listByEmployee(String employeeId) async {
    final rows = await _client
        .from('compensation_changes')
        .select('*')
        .eq('employee_id', employeeId)
        .isFilter('deleted_at', null)
        .order('effective_date', ascending: false);
    return (rows as List)
        .map((r) => CompensationChange.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<CompensationChange>> pendingByEmployee(String employeeId) async {
    final rows = await _client
        .from('compensation_changes')
        .select('*')
        .eq('employee_id', employeeId)
        .eq('status', 'SCHEDULED')
        .isFilter('deleted_at', null)
        .order('effective_date', ascending: true);
    return (rows as List)
        .map((r) => CompensationChange.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> linkWorkflow({
    required String id,
    required String workflowId,
    required String documentId,
  }) async {
    await _client
        .from('compensation_changes')
        .update({'workflow_id': workflowId, 'document_id': documentId})
        .eq('id', id);
  }

  Future<void> cancel(String id) async {
    await _client
        .from('compensation_changes')
        .update({'status': 'CANCELLED'})
        .eq('id', id);
  }

  /// Materializes every SCHEDULED change due on or before [asOf]: repoints the
  /// employee's role_scorecard_id when the change moves the role, then marks
  /// the change APPLIED. Called at the start of a payroll compute (no cron).
  Future<int> applyDue({
    required String companyId,
    required DateTime asOf,
  }) async {
    final due = await _client
        .from('compensation_changes')
        .select('id, employee_id, new_scorecard_id, prev_scorecard_id')
        .eq('company_id', companyId)
        .eq('status', 'SCHEDULED')
        .isFilter('deleted_at', null)
        .lte('effective_date', asOf.toIso8601String().substring(0, 10))
        // Process oldest→newest so that when several changes are due for the
        // same employee, the chronologically latest-effective change is applied
        // last and wins the repoint. `created_at` is the stable tiebreaker for
        // same-day changes, matching the resolver in effective_compensation.dart.
        .order('effective_date', ascending: true)
        .order('created_at', ascending: true);
    var count = 0;
    for (final r in (due as List).cast<Map<String, dynamic>>()) {
      final newScorecardId = r['new_scorecard_id'] as String?;
      final prevScorecardId = r['prev_scorecard_id'] as String?;
      if (newScorecardId != null && newScorecardId != prevScorecardId) {
        await _client
            .from('employees')
            .update({'role_scorecard_id': newScorecardId})
            .eq('id', r['employee_id'] as String);
      }
      await _client.from('compensation_changes').update({
        'status': 'APPLIED',
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', r['id'] as String);
      count++;
    }
    return count;
  }
}

final compensationChangeRepositoryProvider =
    Provider<CompensationChangeRepository>(
        (ref) => CompensationChangeRepository(Supabase.instance.client));

final compensationChangesByEmployeeProvider =
    FutureProvider.family<List<CompensationChange>, String>((ref, employeeId) =>
        ref.read(compensationChangeRepositoryProvider).listByEmployee(employeeId));

final pendingCompensationChangesProvider =
    FutureProvider.family<List<CompensationChange>, String>((ref, employeeId) =>
        ref.read(compensationChangeRepositoryProvider).pendingByEmployee(employeeId));
