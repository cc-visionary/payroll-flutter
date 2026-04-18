import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/department.dart';
import '../../features/auth/profile_provider.dart';

class DepartmentRepository {
  final SupabaseClient _client;
  DepartmentRepository(this._client);

  Future<List<Department>> list(String companyId) async {
    final rows = await _client
        .from('departments')
        .select()
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    return rows.cast<Map<String, dynamic>>().map(Department.fromRow).toList();
  }

  /// Returns a {department_id: employee_count} map for active employees.
  ///
  /// Employees link to departments indirectly via their role scorecard:
  ///   employees.role_scorecard_id -> role_scorecards.department_id
  /// Employees without a scorecard, or with a scorecard lacking a
  /// department_id, are excluded.
  Future<Map<String, int>> employeeCounts(String companyId) async {
    final scorecards = await _client
        .from('role_scorecards')
        .select('id, department_id')
        .eq('company_id', companyId);
    final scorecardToDept = <String, String>{};
    for (final r in scorecards.cast<Map<String, dynamic>>()) {
      final deptId = r['department_id'] as String?;
      if (deptId == null) continue;
      scorecardToDept[r['id'] as String] = deptId;
    }
    if (scorecardToDept.isEmpty) return const {};

    final employees = await _client
        .from('employees')
        .select('role_scorecard_id')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .not('role_scorecard_id', 'is', null);
    final out = <String, int>{};
    for (final r in employees.cast<Map<String, dynamic>>()) {
      final deptId = scorecardToDept[r['role_scorecard_id'] as String];
      if (deptId == null) continue;
      out[deptId] = (out[deptId] ?? 0) + 1;
    }
    return out;
  }

  Future<void> upsert({
    String? id,
    required String companyId,
    required String code,
    required String name,
    String? parentDepartmentId,
    String? costCenterCode,
    String? managerId,
  }) async {
    final payload = {
      'company_id': companyId,
      'code': code,
      'name': name,
      'parent_department_id': parentDepartmentId,
      'cost_center_code': costCenterCode,
      'manager_id': managerId,
    };
    if (id == null) {
      await _client.from('departments').insert(payload);
    } else {
      await _client.from('departments').update(payload).eq('id', id);
    }
  }

  /// Soft-delete — sets deleted_at. Callers must verify employee count == 0
  /// before invoking.
  Future<void> delete(String id) async {
    await _client
        .from('departments')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }
}

final departmentRepositoryProvider = Provider<DepartmentRepository>(
    (ref) => DepartmentRepository(Supabase.instance.client));

final departmentListProvider = FutureProvider<List<Department>>((ref) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null) return const [];
  return ref.watch(departmentRepositoryProvider).list(profile.companyId);
});

final departmentEmployeeCountsProvider =
    FutureProvider<Map<String, int>>((ref) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null) return const {};
  return ref.watch(departmentRepositoryProvider).employeeCounts(profile.companyId);
});
