-- Port of payrollos/prisma/seed/seeders/02-roles.ts + data/roles.ts
-- System roles with their permission arrays (permission strings are the same
-- as payrollos/lib/auth/permissions.ts Permission enum values).

insert into roles (id, code, name, description, permissions, is_system) values
(
  '22222222-2222-2222-2222-000000000001',
  'SUPER_ADMIN',
  'Super Administrator',
  'Full system access',
  '["*"]'::jsonb,
  true
),
(
  '22222222-2222-2222-2222-000000000002',
  'HR_ADMIN',
  'HR Administrator',
  'Manage employees, attendance, leaves, pay profiles',
  '[
    "employee:view","employee:create","employee:edit","employee:view_sensitive",
    "pay_profile:view","pay_profile:edit",
    "attendance:view","attendance:import","attendance:edit","attendance:adjust","attendance:approve_adjustment",
    "leave:view","leave:approve",
    "department:view","department:manage",
    "leave_type:view","leave_type:manage",
    "document:generate","document:view",
    "reimbursement:view","reimbursement:approve",
    "cash_advance:view","cash_advance:approve"
  ]'::jsonb,
  true
),
(
  '22222222-2222-2222-2222-000000000003',
  'PAYROLL_ADMIN',
  'Payroll Administrator',
  'Run payroll, export statutory files, generate payslips',
  '[
    "employee:view","employee:view_sensitive",
    "pay_profile:view",
    "attendance:view",
    "payroll:view","payroll:run","payroll:edit",
    "payslip:view_all","payslip:generate",
    "export:bank_file","export:statutory","export:payroll_register","report:view",
    "document:view"
  ]'::jsonb,
  true
),
(
  '22222222-2222-2222-2222-000000000004',
  'FINANCE_MANAGER',
  'Finance Manager',
  'Approve payroll, view financial reports',
  '[
    "employee:view",
    "payroll:view","payroll:approve","payroll:release",
    "payslip:view_all",
    "export:payroll_register","report:view"
  ]'::jsonb,
  true
)
on conflict (code) do update set
  name        = excluded.name,
  description = excluded.description,
  permissions = excluded.permissions;
