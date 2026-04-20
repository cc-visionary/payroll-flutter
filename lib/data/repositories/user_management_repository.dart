import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/managed_user.dart';

class UserManagementRepository {
  final SupabaseClient _client;
  UserManagementRepository(this._client);

  /// Lists every user in the caller's company. RLS on `user_emails` already
  /// scopes to the caller's company_id.
  Future<List<ManagedUser>> list() async {
    final rows = await _client
        .from('user_emails')
        .select(
            'id, email, status, must_change_password, invited_at, invited_by, last_sign_in_at, app_role')
        .order('email');

    final userIds = rows.map((r) => r['id'] as String).toList();
    if (userIds.isEmpty) return const [];

    // Fetch employee links + names in one round-trip.
    final emps = await _client
        .from('employees')
        .select('id, user_id, first_name, last_name')
        .inFilter('user_id', userIds);
    final empByUser = <String, Map<String, dynamic>>{
      for (final e in emps) (e['user_id'] as String): e,
    };

    return rows.map<ManagedUser>((r) {
      final id = r['id'] as String;
      final emp = empByUser[id];
      final name = emp == null
          ? null
          : '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim();
      return ManagedUser(
        userId: id,
        email: (r['email'] as String?) ?? '',
        roleCode: r['app_role'] as String?,
        status: (r['status'] as String?) ?? 'ACTIVE',
        mustChangePassword: (r['must_change_password'] as bool?) ?? false,
        invitedAt: r['invited_at'] == null
            ? null
            : DateTime.parse(r['invited_at'] as String),
        invitedBy: r['invited_by'] as String?,
        lastSignInAt: r['last_sign_in_at'] == null
            ? null
            : DateTime.parse(r['last_sign_in_at'] as String),
        linkedEmployeeId: emp?['id'] as String?,
        linkedEmployeeName: (name == null || name.isEmpty) ? null : name,
      );
    }).toList();
  }

  /// Employees in the caller's company that aren't linked to any user yet.
  /// `includeUserId` keeps the currently-linked employee in the list when
  /// editing an existing user's link.
  Future<List<UnlinkedEmployee>> unlinkedEmployees(
      {String? includeUserId}) async {
    final rows = await _client
        .from('employees')
        .select('id, first_name, last_name, user_id')
        .order('first_name');
    return rows
        .where((e) {
          final uid = e['user_id'] as String?;
          return uid == null || uid == includeUserId;
        })
        .map<UnlinkedEmployee>((e) => UnlinkedEmployee(
              id: e['id'] as String,
              name: '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim(),
            ))
        .toList();
  }

  Future<void> _invoke(String action, Map<String, dynamic> payload) async {
    final res = await _client.functions.invoke('manage-user', body: {
      'action': action,
      ...payload,
    });
    final data = (res.data as Map?) ?? const {};
    if (data['ok'] != true) {
      throw UserManagementException(
        data['error']?.toString() ?? 'manage-user failed',
        code: data['code']?.toString(),
      );
    }
  }

  Future<void> create({
    required String email,
    required String password,
    required String roleCode,
    String? employeeId,
  }) =>
      _invoke('create', {
        'email': email,
        'password': password,
        'role_code': roleCode,
        if (employeeId != null) 'employee_id': employeeId,
      });

  Future<void> setPassword(String userId, String password) =>
      _invoke('set_password', {'user_id': userId, 'password': password});

  Future<void> updateRole(String userId, String roleCode) =>
      _invoke('update_role', {'user_id': userId, 'role_code': roleCode});

  Future<void> linkEmployee(String userId, String? employeeId) =>
      _invoke('link_employee', {'user_id': userId, 'employee_id': employeeId});

  Future<void> deactivate(String userId) =>
      _invoke('deactivate', {'user_id': userId});

  Future<void> reactivate(String userId) =>
      _invoke('reactivate', {'user_id': userId});
}

class UserManagementException implements Exception {
  final String message;
  final String? code;
  UserManagementException(this.message, {this.code});
  @override
  String toString() => code == null ? message : '$message ($code)';
}

final userManagementRepositoryProvider = Provider<UserManagementRepository>(
  (ref) => UserManagementRepository(Supabase.instance.client),
);

final managedUsersProvider = FutureProvider<List<ManagedUser>>((ref) async {
  return ref.watch(userManagementRepositoryProvider).list();
});

final unlinkedEmployeesProvider =
    FutureProvider.family<List<UnlinkedEmployee>, String?>(
  (ref, includeUserId) => ref
      .watch(userManagementRepositoryProvider)
      .unlinkedEmployees(includeUserId: includeUserId),
);
