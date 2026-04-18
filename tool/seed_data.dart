// Seed constants — ported from supabase/seed/*.sql + create_admin_users.ts.
// Kept in one place so the one-command seeder is self-describing.

import 'dart:convert';
import 'dart:io';

const seedCompanyId = '11111111-1111-1111-1111-000000000001';

// -----------------------------------------------------------------------------
// JSON fixture loaders (xlsx-extracted data lives in tool/seed_fixtures/)
// -----------------------------------------------------------------------------

List<Map<String, Object?>> _loadFixture(String name) {
  final file = File('tool/seed_fixtures/$name.json');
  if (!file.existsSync()) {
    throw StateError('Missing fixture: ${file.path}');
  }
  final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  return raw.cast<Map<String, dynamic>>().map((m) => Map<String, Object?>.from(m)).toList();
}

List<Map<String, Object?>> loadRoleScorecards() => _loadFixture('role_scorecards');
List<Map<String, Object?>> loadEmployees() => _loadFixture('employees');
List<Map<String, Object?>> loadEmployeeStatutoryIds() => _loadFixture('employee_statutory_ids');

// -----------------------------------------------------------------------------
// Companies + hiring entities
// -----------------------------------------------------------------------------

final seedCompany = <String, Object>{
  'id': seedCompanyId,
  'code': 'GAMECOVE',
  'name': 'GameCove Inc.',
  'trade_name': 'GameCove',
  'country': 'PH',
};

final seedHiringEntities = <Map<String, Object>>[
  {
    'id': '00000000-0000-0000-0000-000000000001',
    'company_id': seedCompanyId,
    'code': 'GC',
    'name': 'GameCove Inc.',
    'trade_name': 'GameCove',
    'tin': '000-000-000-000',
    'rdo_code': '044',
    'sss_employer_id': '00-0000000-0',
    'philhealth_employer_id': '00-000000000-0',
    'pagibig_employer_id': '0000-0000-0000',
    'address_line1': 'Unit 123, Sample Building',
    'address_line2': 'Sample Street, Sample Barangay',
    'city': 'Makati City',
    'province': 'Metro Manila',
    'zip_code': '1234',
    'phone_number': '+63 2 1234 5678',
    'email': 'hr@gamecove.ph',
    'country': 'PH',
  },
  {
    'id': '00000000-0000-0000-0000-000000000002',
    'company_id': seedCompanyId,
    'code': 'LX',
    'name': 'Luxium Trading Inc.',
    'trade_name': 'Luxium',
    'tin': '000-000-000-001',
    'rdo_code': '044',
    'sss_employer_id': '00-0000000-1',
    'philhealth_employer_id': '00-000000000-1',
    'pagibig_employer_id': '0000-0000-0001',
    'address_line1': 'Unit 456, Sample Building',
    'address_line2': 'Sample Street, Sample Barangay',
    'city': 'Makati City',
    'province': 'Metro Manila',
    'zip_code': '1234',
    'phone_number': '+63 2 1234 5679',
    'email': 'hr@luxium.ph',
    'country': 'PH',
  },
];

// -----------------------------------------------------------------------------
// Roles
// -----------------------------------------------------------------------------

// Permission strings — mirror payrollos/lib/auth/permissions.ts exactly.
const _allPermissions = <String>[
  'employee:view', 'employee:create', 'employee:edit', 'employee:delete', 'employee:view_sensitive',
  'pay_profile:view', 'pay_profile:edit', 'pay_profile:approve',
  'attendance:view', 'attendance:import', 'attendance:edit', 'attendance:adjust', 'attendance:approve_adjustment',
  'leave:view', 'leave:request', 'leave:approve',
  'payroll:view', 'payroll:run', 'payroll:edit', 'payroll:approve', 'payroll:release',
  'payslip:view_own', 'payslip:view_all', 'payslip:generate',
  'export:bank_file', 'export:statutory', 'export:payroll_register', 'report:view',
  'document:generate', 'document:view',
  'reimbursement:view', 'reimbursement:request', 'reimbursement:approve',
  'cash_advance:view', 'cash_advance:request', 'cash_advance:approve',
  'or_incentive:view', 'or_incentive:submit', 'or_incentive:approve',
  'department:view', 'department:manage',
  'leave_type:view', 'leave_type:manage',
  'role_scorecard:view', 'role_scorecard:manage',
  'hiring:view', 'hiring:create', 'hiring:edit', 'hiring:convert',
  'shift:view', 'shift:manage', 'schedule:view', 'schedule:manage',
  'ruleset:view', 'ruleset:manage',
  'user:view', 'user:manage', 'role:view', 'role:manage',
  'penalty:view', 'penalty:manage', 'penalty_type:manage',
  'workflow:view', 'workflow:create', 'workflow:manage',
  'audit:view',
  'system:settings',
];

final seedRoles = <Map<String, Object>>[
  {
    'id': '22222222-2222-2222-2222-000000000001',
    'code': 'SUPER_ADMIN',
    'name': 'Super Administrator',
    'description': 'Full system access',
    'permissions': _allPermissions,
    'is_system': true,
  },
  {
    'id': '22222222-2222-2222-2222-000000000002',
    'code': 'HR_ADMIN',
    'name': 'HR Administrator',
    'description': 'Manages employees, attendance, leaves, pay profiles',
    'permissions': const [
      'employee:view', 'employee:create', 'employee:edit', 'employee:delete', 'employee:view_sensitive',
      'pay_profile:view', 'pay_profile:edit',
      'attendance:view', 'attendance:import', 'attendance:edit', 'attendance:adjust', 'attendance:approve_adjustment',
      'leave:view', 'leave:approve',
      'payroll:view', 'payroll:run', 'payroll:edit', 'payroll:approve', 'payroll:release',
      'payslip:view_all',
      'document:generate', 'document:view',
      'reimbursement:view', 'reimbursement:approve',
      'cash_advance:view', 'cash_advance:approve',
      'or_incentive:view', 'or_incentive:approve',
      'shift:view', 'shift:manage', 'schedule:view', 'schedule:manage',
      'department:view', 'department:manage',
      'leave_type:view', 'leave_type:manage',
      'role_scorecard:view', 'role_scorecard:manage',
      'hiring:view', 'hiring:create', 'hiring:edit', 'hiring:convert',
      'user:view', 'role:view', 'role:manage',
      'report:view', 'audit:view',
      'penalty:view', 'penalty:manage', 'penalty_type:manage',
      'workflow:view', 'workflow:create', 'workflow:manage',
    ],
    'is_system': true,
  },
  {
    'id': '22222222-2222-2222-2222-000000000003',
    'code': 'PAYROLL_ADMIN',
    'name': 'Payroll Administrator',
    'description': 'Runs and manages payroll',
    'permissions': const [
      'employee:view', 'employee:view_sensitive',
      'pay_profile:view', 'pay_profile:edit', 'pay_profile:approve',
      'attendance:view', 'attendance:import',
      'payroll:view', 'payroll:run', 'payroll:edit',
      'payslip:view_all', 'payslip:generate',
      'export:bank_file', 'export:statutory', 'export:payroll_register',
      'report:view',
      'reimbursement:view', 'cash_advance:view', 'or_incentive:view',
      'shift:view', 'schedule:view', 'ruleset:view',
    ],
    'is_system': true,
  },
  {
    'id': '22222222-2222-2222-2222-000000000004',
    'code': 'FINANCE_MANAGER',
    'name': 'Finance Manager',
    'description': 'Approves payroll, views reports',
    'permissions': const [
      'employee:view', 'pay_profile:view', 'attendance:view',
      'payroll:view', 'payroll:approve', 'payroll:release',
      'payslip:view_all',
      'export:bank_file', 'export:statutory', 'export:payroll_register',
      'report:view',
      'reimbursement:view', 'reimbursement:approve',
      'cash_advance:view', 'cash_advance:approve',
      'audit:view',
    ],
    'is_system': true,
  },
];

// -----------------------------------------------------------------------------
// Departments
// -----------------------------------------------------------------------------

final seedDepartments = <Map<String, Object>>[
  {'id': '99999999-9999-9999-9999-000000000001', 'company_id': seedCompanyId, 'code': 'OPS', 'name': 'Operations'},
  {'id': '99999999-9999-9999-9999-000000000002', 'company_id': seedCompanyId, 'code': 'HR',  'name': 'Human Resources'},
  {'id': '99999999-9999-9999-9999-000000000003', 'company_id': seedCompanyId, 'code': 'SLS', 'name': 'Sales'},
  {'id': '99999999-9999-9999-9999-000000000004', 'company_id': seedCompanyId, 'code': 'MKT', 'name': 'Marketing'},
];

// -----------------------------------------------------------------------------
// Admin users — passwords come from env; app_role goes in JWT app_metadata.
// -----------------------------------------------------------------------------

class SeedUser {
  final String email;
  final String passwordEnvKey;
  final String defaultPassword;
  final String roleCode;
  final String appRole;
  const SeedUser({
    required this.email,
    required this.passwordEnvKey,
    required this.defaultPassword,
    required this.roleCode,
    required this.appRole,
  });
}

const seedUsers = <SeedUser>[
  SeedUser(
    email: 'admin@gamecove.ph',
    passwordEnvKey: 'ADMIN_PASSWORD',
    defaultPassword: 'Admin123!',
    roleCode: 'SUPER_ADMIN',
    appRole: 'SUPER_ADMIN',
  ),
  SeedUser(
    email: 'hr@gamecove.ph',
    passwordEnvKey: 'HR_PASSWORD',
    defaultPassword: 'HrAdmin123!',
    roleCode: 'HR_ADMIN',
    appRole: 'HR',
  ),
  SeedUser(
    email: 'payroll@gamecove.ph',
    passwordEnvKey: 'PAYROLL_PASSWORD',
    defaultPassword: 'Payroll123!',
    roleCode: 'PAYROLL_ADMIN',
    appRole: 'ADMIN',
  ),
  SeedUser(
    email: 'finance@gamecove.ph',
    passwordEnvKey: 'FINANCE_PASSWORD',
    defaultPassword: 'Finance123!',
    roleCode: 'FINANCE_MANAGER',
    appRole: 'ADMIN',
  ),
];
