import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_provider.dart';

enum AppRole {
  SUPER_ADMIN,
  ADMIN,
  PAYROLL_ADMIN,
  HR,
  HR_ADMIN,
  MANAGER,
  FINANCE_MANAGER,
  EMPLOYEE,
}

AppRole _parseRole(String? s) {
  switch (s) {
    case 'SUPER_ADMIN':
      return AppRole.SUPER_ADMIN;
    case 'ADMIN':
      return AppRole.ADMIN;
    case 'PAYROLL_ADMIN':
      return AppRole.PAYROLL_ADMIN;
    case 'HR':
      return AppRole.HR;
    case 'HR_ADMIN':
      return AppRole.HR_ADMIN;
    case 'MANAGER':
      return AppRole.MANAGER;
    case 'FINANCE_MANAGER':
      return AppRole.FINANCE_MANAGER;
    default:
      return AppRole.EMPLOYEE;
  }
}

/// The inverse of [_parseRole] -- the `app_role` code an [AppRole] was
/// parsed from. Exists so [kPerformanceAdminRoleCodes] (a set of server-side
/// role CODES, the vocabulary `auth_app_role()` and RLS policies speak) can
/// be checked against a client-side [AppRole] without a second, hand-written
/// mapping that could drift from this one.
String appRoleCode(AppRole role) => switch (role) {
  AppRole.SUPER_ADMIN => 'SUPER_ADMIN',
  AppRole.ADMIN => 'ADMIN',
  AppRole.PAYROLL_ADMIN => 'PAYROLL_ADMIN',
  AppRole.HR => 'HR',
  AppRole.HR_ADMIN => 'HR_ADMIN',
  AppRole.MANAGER => 'MANAGER',
  AppRole.FINANCE_MANAGER => 'FINANCE_MANAGER',
  AppRole.EMPLOYEE => 'EMPLOYEE',
};

/// The RLS authority for `employee_reviews`/`kpi_results` full-company
/// visibility -- `auth_is_performance_admin_for_cycle`
/// (20260717000009_performance_rls_and_cascade_fixes.sql), which grants
/// SUPER_ADMIN, ADMIN, HR and HR_ADMIN full visibility and nobody else.
/// PAYROLL_ADMIN and FINANCE_MANAGER are DELIBERATELY excluded: they are
/// payroll-scoped roles, not performance-management roles, and the RLS
/// policy this constant must mirror never grants them full-review
/// visibility -- unlike `auth_is_hr_or_admin()`
/// (20260423000004_rls_recognize_new_roles.sql), the broader admin-ish-table
/// authority `isAdmin`/`isHrOrAdmin` below are built from, which DOES
/// include both.
///
/// This is the single source both [UserProfile.isPerformanceAdmin] (gates
/// the `/kpi-results` route, and therefore Recompute) and
/// `ReviewCycleRepository._kFullReviewVisibilityRoles` (gates what
/// `allReviews()` actually returns) are built from -- not two separately
/// written lists that happen to agree today. A PAYROLL_ADMIN used to pass
/// the route guard (via `isHrOrAdmin`, which includes PAYROLL_ADMIN) but
/// fail the review-visibility check (which never did), so `Recompute`
/// silently overwrote every review-sourced ON_TRACK/OFF_TRACK row with
/// NO_DATA for that caller. Sharing one Set makes that divergence
/// structurally impossible rather than merely policed by convention.
const kPerformanceAdminRoleCodes = {'SUPER_ADMIN', 'ADMIN', 'HR', 'HR_ADMIN'};

class UserProfile {
  final String userId;
  final String email;
  final String companyId;
  final String? employeeId;
  final AppRole appRole;
  final bool mustChangePassword;

  const UserProfile({
    required this.userId,
    required this.email,
    required this.companyId,
    required this.employeeId,
    required this.appRole,
    required this.mustChangePassword,
  });

  bool get isAdmin =>
      appRole == AppRole.SUPER_ADMIN ||
      appRole == AppRole.ADMIN ||
      appRole == AppRole.PAYROLL_ADMIN ||
      appRole == AppRole.HR_ADMIN;

  bool get isHrOrAdmin => isAdmin || appRole == AppRole.HR;

  /// Whether this caller's role is one the server-side RLS authority
  /// (`auth_is_performance_admin_for_cycle`) grants full-company
  /// `employee_reviews` visibility -- see [kPerformanceAdminRoleCodes]'s doc
  /// comment. Narrower than [isHrOrAdmin]: PAYROLL_ADMIN passes
  /// [isHrOrAdmin] but not this, on purpose. Gates the `/kpi-results` route
  /// (`app/router.dart`), because that screen's Recompute action silently
  /// mis-scores every review-sourced KPI result for a caller this returns
  /// false for -- narrower access here is what prevents that, not merely
  /// what documents it.
  bool get isPerformanceAdmin =>
      kPerformanceAdminRoleCodes.contains(appRoleCode(appRole));

  bool get canManageEmployees => isHrOrAdmin;
  bool get canRunPayroll => isHrOrAdmin || appRole == AppRole.PAYROLL_ADMIN;
  bool get canEditTaxTables => appRole == AppRole.SUPER_ADMIN;
}

/// Loads the authenticated user's app-level profile (users row + employee_id +
/// app_role claim from JWT + must_change_password flag). Null while logged out.
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final session = ref.watch(authStateProvider).value;
  if (session == null) return null;

  final client = Supabase.instance.client;
  final userId = session.user.id;
  final email = session.user.email ?? '';

  final claims = session.accessToken.isEmpty
      ? <String, dynamic>{}
      : _decodeJwtPayload(session.accessToken);
  final appRole = _parseRole(
    (claims['app_role'] ?? claims['app_metadata']?['app_role']) as String?,
  );

  Map<String, dynamic>? userRow;
  try {
    userRow = await client
        .from('user_emails')
        .select('company_id, must_change_password')
        .eq('id', userId)
        .maybeSingle();
  } catch (_) {
    userRow = null;
  }

  String? employeeId;
  try {
    final emp = await client
        .from('employees')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();
    employeeId = emp?['id'] as String?;
  } catch (_) {
    employeeId = null;
  }

  return UserProfile(
    userId: userId,
    email: email,
    companyId: userRow?['company_id'] as String? ?? '',
    employeeId: employeeId,
    appRole: appRole,
    mustChangePassword: (userRow?['must_change_password'] as bool?) ?? false,
  );
});

Map<String, dynamic> _decodeJwtPayload(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return {};
    final normalized = _b64NormalizePad(parts[1]);
    final decoded = String.fromCharCodes(_base64Decode(normalized));
    final obj = _parseJson(decoded);
    return obj is Map<String, dynamic> ? obj : {};
  } catch (_) {
    return {};
  }
}

String _b64NormalizePad(String s) {
  var out = s.replaceAll('-', '+').replaceAll('_', '/');
  while (out.length % 4 != 0) {
    out += '=';
  }
  return out;
}

List<int> _base64Decode(String s) => base64.decode(s);

dynamic _parseJson(String s) => jsonDecode(s);
