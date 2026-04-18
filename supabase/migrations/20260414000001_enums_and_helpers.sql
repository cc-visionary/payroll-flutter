-- Payroll Flutter — Enums + common helpers
-- Ported from payrollos/prisma/schema.prisma

-- =============================================================================
-- EXTENSIONS
-- =============================================================================
create extension if not exists "pgcrypto";  -- gen_random_uuid()

-- =============================================================================
-- ENUMS
-- =============================================================================
create type user_status as enum ('ACTIVE', 'INACTIVE', 'LOCKED', 'PENDING_VERIFICATION');

create type employment_type as enum (
  'REGULAR', 'PROBATIONARY', 'CONTRACTUAL', 'CONSULTANT', 'INTERN', 'SEASONAL', 'CASUAL'
);

create type employment_status as enum (
  'ACTIVE', 'RESIGNED', 'TERMINATED', 'AWOL', 'DECEASED', 'END_OF_CONTRACT', 'RETIRED'
);

create type wage_type as enum ('MONTHLY', 'DAILY', 'HOURLY');

create type pay_frequency as enum ('MONTHLY', 'SEMI_MONTHLY', 'BI_WEEKLY', 'WEEKLY');

create type employment_event_type as enum (
  'HIRE', 'REGULARIZATION', 'SALARY_CHANGE', 'ROLE_CHANGE', 'DEPARTMENT_TRANSFER',
  'PROMOTION', 'DEMOTION', 'PENALTY_ISSUED', 'INCIDENT_REPORTED', 'COMMENDATION',
  'SEPARATION_INITIATED', 'SEPARATION_CONFIRMED', 'REHIRE', 'STATUS_CHANGE', 'DECLARED_WAGE_OVERRIDE'
);

create type employment_event_status as enum ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED');

create type applicant_status as enum (
  'NEW', 'SCREENING', 'INTERVIEW', 'ASSESSMENT', 'OFFER',
  'OFFER_ACCEPTED', 'HIRED', 'REJECTED', 'WITHDRAWN'
);

create type interview_type as enum ('PHONE_SCREEN', 'TECHNICAL', 'BEHAVIORAL', 'PANEL', 'FINAL');
create type interview_result as enum ('PENDING', 'PASSED', 'FAILED', 'NO_SHOW', 'RESCHEDULED');

create type shift_break_type as enum ('FIXED', 'AUTO_DEDUCT', 'NO_BREAK');
create type attendance_source as enum ('LARK_IMPORT', 'MANUAL', 'BIOMETRIC', 'SYSTEM');
create type attendance_status as enum ('PRESENT', 'ABSENT', 'HALF_DAY', 'ON_LEAVE', 'REST_DAY', 'HOLIDAY');
create type day_type as enum ('WORKDAY', 'REST_DAY', 'REGULAR_HOLIDAY', 'SPECIAL_HOLIDAY', 'SPECIAL_WORKING');

create type approval_status as enum ('PENDING', 'APPROVED', 'REJECTED');
create type import_status as enum ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'PARTIALLY_COMPLETED');

create type leave_accrual_type as enum ('NONE', 'MONTHLY', 'ANNUAL', 'TENURE_BASED');
create type leave_request_status as enum ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED');

create type payroll_run_status as enum ('DRAFT', 'COMPUTING', 'REVIEW', 'RELEASED', 'CANCELLED');

create type payslip_line_category as enum (
  'BASIC_PAY', 'OVERTIME_REGULAR', 'OVERTIME_REST_DAY', 'OVERTIME_HOLIDAY',
  'NIGHT_DIFFERENTIAL', 'HOLIDAY_PAY', 'REST_DAY_PAY', 'ALLOWANCE', 'REIMBURSEMENT',
  'INCENTIVE', 'BONUS', 'ADJUSTMENT_ADD', 'THIRTEENTH_MONTH_PAY',
  'LATE_DEDUCTION', 'UNDERTIME_DEDUCTION', 'LATE_UT_DEDUCTION', 'ABSENT_DEDUCTION',
  'SSS_EE', 'SSS_ER', 'PHILHEALTH_EE', 'PHILHEALTH_ER', 'PAGIBIG_EE', 'PAGIBIG_ER',
  'TAX_WITHHOLDING', 'CASH_ADVANCE_DEDUCTION', 'LOAN_DEDUCTION',
  'ADJUSTMENT_DEDUCT', 'OTHER_DEDUCTION', 'PENALTY_DEDUCTION'
);

-- Per-payslip approval state within a REVIEW run.
-- Supports the iterative workflow: send → edit → unsend → recompute → resubmit.
create type payslip_approval_status as enum (
  'DRAFT_IN_REVIEW',   -- computed, under internal review, not yet sent to Lark
  'PENDING_APPROVAL',  -- sent to Lark, awaiting approver action
  'APPROVED',          -- approved in Lark
  'REJECTED',          -- rejected in Lark (needs edit + resubmit)
  'RECALLED'           -- unsent before decision so it can be edited
);

create type penalty_status as enum ('ACTIVE', 'COMPLETED', 'CANCELLED');
create type cash_advance_status as enum ('PENDING', 'DEDUCTED', 'CANCELLED');
create type reimbursement_status as enum ('PENDING', 'PAID', 'CANCELLED');

create type audit_action as enum (
  'CREATE', 'UPDATE', 'DELETE', 'APPROVE', 'REJECT', 'LOGIN', 'LOGOUT', 'EXPORT', 'IMPORT'
);

create type document_status as enum (
  'DRAFT', 'PENDING_APPROVAL', 'ISSUED', 'SIGNED', 'VOIDED', 'SUPERSEDED', 'EXPIRED'
);

create type export_type as enum (
  'PAYROLL_REGISTER', 'BANK_DISBURSEMENT', 'SSS_CONTRIBUTIONS', 'PHILHEALTH_CONTRIBUTIONS',
  'PAGIBIG_CONTRIBUTIONS', 'TAX_ALPHALIST', 'PAYSLIP_PDF', 'PAYSLIP_PDF_ZIP'
);

create type check_in_type as enum ('MONTHLY', 'QUARTERLY', 'ANNUAL');
create type check_in_status as enum ('DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'COMPLETED', 'SKIPPED');
create type goal_type as enum ('PERFORMANCE', 'LEARNING', 'PROJECT', 'BEHAVIORAL');
create type goal_status as enum ('NOT_STARTED', 'IN_PROGRESS', 'COMPLETED', 'PARTIALLY_MET', 'NOT_MET', 'DEFERRED');

create type workflow_type as enum (
  'HIRING', 'REGULARIZATION', 'SALARY_CHANGE', 'ROLE_CHANGE',
  'DISCIPLINARY', 'SEPARATION', 'REPAYMENT_AGREEMENT'
);
create type workflow_status as enum ('DRAFT', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED');
create type workflow_step_type as enum ('DATA_ENTRY', 'APPROVAL', 'DOCUMENT_GENERATION', 'STATUS_UPDATE', 'REVIEW');
create type workflow_step_status as enum ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'SKIPPED', 'REJECTED');

-- App-level role (maps to payrollos lib/auth/permissions.ts)
create type app_role as enum ('SUPER_ADMIN', 'ADMIN', 'HR', 'MANAGER', 'EMPLOYEE');

-- =============================================================================
-- COMMON TRIGGERS
-- =============================================================================
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- JWT claim helpers for RLS
create or replace function auth_app_role()
returns app_role language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_role', ''),
    'EMPLOYEE'
  )::app_role
$$;

create or replace function auth_company_id()
returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid
$$;

create or replace function auth_employee_id()
returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'employee_id', '')::uuid
$$;
