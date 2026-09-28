import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/payroll/engine/effective_compensation.dart';
import '../models/compensation_change.dart';
import '../models/role_rate_change.dart';

/// Which of [employeeIds] are paid the ROLE default on [asOf]: those with no
/// compensation record of their own in effect. Everyone else keeps their own
/// pay, so a role rate change does not touch them.
List<String> roleDefaultEmployeeIds({
  required List<String> employeeIds,
  required Map<String, List<CompensationChange>> compByEmployee,
  required DateTime asOf,
}) => [
  for (final id in employeeIds)
    if (effectiveCompensation(compByEmployee[id] ?? const [], asOf) == null) id,
];

/// The rate `role_scorecards.base_salary` should hold after a change: the
/// newest change by effective date (ties to newest created). Documents, offer
/// letters and the hiring auto-fill read base_salary, so it tracks the latest
/// rate; payroll never trusts it for a past day (see `roleRateAsOf`).
Decimal latestRoleRate(List<RoleRateChange> history) {
  var best = history.first;
  for (final c in history.skip(1)) {
    final byDate = c.effectiveDate.compareTo(best.effectiveDate);
    if (byDate > 0 || (byDate == 0 && c.createdAt.isAfter(best.createdAt))) {
      best = c;
    }
  }
  return best.newBaseSalary;
}

class RoleRateChangeRepository {
  final SupabaseClient _client;
  RoleRateChangeRepository(this._client);

  Future<List<RoleRateChange>> listByScorecard(String scorecardId) async {
    final rows = await _client
        .from('role_rate_changes')
        .select('*')
        .eq('role_scorecard_id', scorecardId)
        .order('effective_date', ascending: false)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => RoleRateChange.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Active employees on [scorecardId] who are paid the role default on
  /// [asOf] — the people a rate change will actually reprice.
  Future<List<({String id, String name})>> roleDefaultHolders({
    required String scorecardId,
    required DateTime asOf,
  }) async {
    final emps = (await _client
            .from('employees')
            .select('id, first_name, last_name')
            .eq('role_scorecard_id', scorecardId)
            .eq('employment_status', 'ACTIVE')
            .isFilter('deleted_at', null) as List)
        .cast<Map<String, dynamic>>();
    if (emps.isEmpty) return const [];
    final compRows = (await _client
            .from('compensation_changes')
            .select('*')
            .isFilter('deleted_at', null)
            .inFilter('employee_id', emps.map((e) => e['id'] as String).toList())
        as List)
        .cast<Map<String, dynamic>>();
    final compByEmployee = <String, List<CompensationChange>>{};
    for (final r in compRows) {
      (compByEmployee[r['employee_id'] as String] ??= []).add(
        CompensationChange.fromRow(r),
      );
    }
    final ids = roleDefaultEmployeeIds(
      employeeIds: emps.map((e) => e['id'] as String).toList(),
      compByEmployee: compByEmployee,
      asOf: asOf,
    ).toSet();
    return [
      for (final e in emps)
        if (ids.contains(e['id']))
          (
            id: e['id'] as String,
            name: '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim(),
          ),
    ];
  }

  /// Records an effective-dated role rate change, moves
  /// `role_scorecards.base_salary` to the newest rate, and adds a
  /// SALARY_CHANGE timeline event for every role-default holder. Best-effort
  /// sequence, like `runCompensationChange`.
  Future<void> record({
    required String companyId,
    required String scorecardId,
    required DateTime effectiveDate,
    required Decimal? prevBaseSalary,
    required Decimal newBaseSalary,
    required String reason,
    required String initiatedById,
  }) async {
    final dateStr = effectiveDate.toIso8601String().substring(0, 10);
    final change = await _client
        .from('role_rate_changes')
        .insert({
          'company_id': companyId,
          'role_scorecard_id': scorecardId,
          'effective_date': dateStr,
          'prev_base_salary': prevBaseSalary?.toString(),
          'new_base_salary': newBaseSalary.toString(),
          'reason': reason,
          'initiated_by_id': initiatedById,
        })
        .select('id')
        .single();

    final history = await listByScorecard(scorecardId);
    await _client
        .from('role_scorecards')
        .update({'base_salary': latestRoleRate(history).toString()})
        .eq('id', scorecardId);

    final holders = await roleDefaultHolders(
      scorecardId: scorecardId,
      asOf: effectiveDate,
    );
    if (holders.isEmpty) return;
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    await _client.from('employment_events').insert([
      for (final h in holders)
        {
          'employee_id': h.id,
          'event_type': 'SALARY_CHANGE',
          'event_date': dateStr,
          'status': 'APPROVED',
          'payload': {
            'role_rate_change_id': change['id'],
            'source': 'ROLE_RATE',
            'reason': reason,
            'old_salary': prevBaseSalary?.toString(),
            'new_salary': newBaseSalary.toString(),
          },
          'requested_by_id': initiatedById,
          'approved_by_id': initiatedById,
          'approved_at': nowUtc,
        },
    ]);
  }
}

final roleRateChangeRepositoryProvider = Provider<RoleRateChangeRepository>(
  (ref) => RoleRateChangeRepository(Supabase.instance.client),
);

final roleRateChangesProvider =
    FutureProvider.family<List<RoleRateChange>, String>(
      (ref, scorecardId) => ref
          .read(roleRateChangeRepositoryProvider)
          .listByScorecard(scorecardId),
    );
