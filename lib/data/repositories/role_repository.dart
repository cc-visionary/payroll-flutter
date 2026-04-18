import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/role.dart';

/// Canonical permission taxonomy — mirrors the strings seeded in
/// `supabase/seed/02_roles.sql`. Grouped for the permissions picker.
const Map<String, List<String>> kPermissionCatalog = {
  'Employees': [
    'employee:view',
    'employee:create',
    'employee:edit',
    'employee:view_sensitive',
  ],
  'Pay Profile': [
    'pay_profile:view',
    'pay_profile:edit',
  ],
  'Attendance': [
    'attendance:view',
    'attendance:import',
    'attendance:edit',
    'attendance:adjust',
    'attendance:approve_adjustment',
  ],
  'Leave': [
    'leave:view',
    'leave:approve',
    'leave_type:view',
    'leave_type:manage',
  ],
  'Department': [
    'department:view',
    'department:manage',
  ],
  'Payroll': [
    'payroll:view',
    'payroll:run',
    'payroll:edit',
    'payroll:approve',
    'payroll:release',
  ],
  'Payslips': [
    'payslip:view_all',
    'payslip:generate',
  ],
  'Benefits': [
    'cash_advance:view',
    'cash_advance:approve',
    'reimbursement:view',
    'reimbursement:approve',
  ],
  'Documents': [
    'document:generate',
    'document:view',
  ],
  'Exports & Reports': [
    'export:bank_file',
    'export:statutory',
    'export:payroll_register',
    'report:view',
  ],
};

class RoleRepository {
  final SupabaseClient _client;
  RoleRepository(this._client);

  Future<List<Role>> list() async {
    final rows = await _client.from('roles').select().order('is_system', ascending: false).order('name');
    return rows.cast<Map<String, dynamic>>().map(Role.fromRow).toList();
  }

  /// Returns a {role_id: user_count} map.
  Future<Map<String, int>> userCounts() async {
    final rows = await _client.from('user_roles').select('role_id');
    final out = <String, int>{};
    for (final r in rows.cast<Map<String, dynamic>>()) {
      final id = r['role_id'] as String?;
      if (id == null) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  Future<List<UserRoleAssignment>> listAssignments(String roleId) async {
    // user_roles -> users (for company scoping) -> employees (for display name)
    final rows = await _client
        .from('user_roles')
        .select('user_id, created_at')
        .eq('role_id', roleId);
    final out = <UserRoleAssignment>[];
    for (final r in rows.cast<Map<String, dynamic>>()) {
      final userId = r['user_id'] as String;
      String? name;
      String email = '';
      try {
        final emp = await _client
            .from('employees')
            .select('first_name, last_name, work_email')
            .eq('user_id', userId)
            .maybeSingle();
        if (emp != null) {
          name = '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim();
          email = (emp['work_email'] as String?) ?? '';
        }
      } catch (_) {}
      out.add(UserRoleAssignment(
        userId: userId,
        email: email,
        employeeName: (name == null || name.isEmpty) ? null : name,
        assignedAt: r['created_at'] == null
            ? null
            : DateTime.parse(r['created_at'] as String),
      ));
    }
    return out;
  }

  Future<void> upsert({
    String? id,
    required String code,
    required String name,
    String? description,
    required List<String> permissions,
    bool isSystem = false,
  }) async {
    final payload = {
      'code': code,
      'name': name,
      'description': description,
      'permissions': permissions,
      'is_system': isSystem,
    };
    if (id == null) {
      await _client.from('roles').insert(payload);
    } else {
      // Only update mutable fields for system roles (code/is_system stay fixed).
      final update = Map<String, dynamic>.from(payload)
        ..remove('is_system')
        ..remove('code');
      await _client.from('roles').update(update).eq('id', id);
    }
  }

  Future<void> deleteRole(String id) async {
    await _client.from('roles').delete().eq('id', id);
  }

  Future<void> assignUser(String userId, String roleId) async {
    await _client
        .from('user_roles')
        .upsert({'user_id': userId, 'role_id': roleId});
  }

  Future<void> removeUser(String userId, String roleId) async {
    await _client
        .from('user_roles')
        .delete()
        .eq('user_id', userId)
        .eq('role_id', roleId);
  }
}

final roleRepositoryProvider =
    Provider<RoleRepository>((ref) => RoleRepository(Supabase.instance.client));

final roleListProvider = FutureProvider<List<Role>>((ref) async {
  return ref.watch(roleRepositoryProvider).list();
});

final roleUserCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.watch(roleRepositoryProvider).userCounts();
});

final roleAssignmentsProvider =
    FutureProvider.family<List<UserRoleAssignment>, String>((ref, roleId) {
  return ref.watch(roleRepositoryProvider).listAssignments(roleId);
});
