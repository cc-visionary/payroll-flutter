-- Benefits: penalty_types, penalties, penalty_installments, cash_advances, reimbursements
-- Adds deferred FKs on payslip_lines

create table penalty_types (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id),
  code         varchar(20) not null,
  name         varchar(100) not null,
  description  text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (company_id, code)
);
create index on penalty_types (company_id, is_active);
create trigger _penalty_types_updated before update on penalty_types for each row execute function set_updated_at();

create table penalties (
  id                  uuid primary key default gen_random_uuid(),
  employee_id         uuid not null references employees(id) on delete cascade,
  penalty_type_id     uuid references penalty_types(id),
  custom_description  text,
  total_amount        numeric(12,2) not null,
  installment_count   integer not null,
  installment_amount  numeric(12,2) not null,
  status              penalty_status not null default 'ACTIVE',
  effective_date      date not null,
  remarks             text,
  total_deducted      numeric(12,2) not null default 0,
  completed_at        timestamptz,
  cancelled_at        timestamptz,
  cancel_reason       text,
  created_by_id       uuid references users(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index on penalties (employee_id, status);
create index on penalties (status);
create trigger _penalties_updated before update on penalties for each row execute function set_updated_at();

create table penalty_installments (
  id                  uuid primary key default gen_random_uuid(),
  penalty_id          uuid not null references penalties(id) on delete cascade,
  installment_number  integer not null,
  amount              numeric(12,2) not null,
  is_deducted         boolean not null default false,
  deducted_at         timestamptz,
  payroll_run_id      uuid references payroll_runs(id),
  payslip_line_id     uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (penalty_id, installment_number)
);
create index on penalty_installments (penalty_id, is_deducted);
create index on penalty_installments (payroll_run_id);
create trigger _penalty_installments_updated before update on penalty_installments for each row execute function set_updated_at();

create table cash_advances (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references companies(id),
  employee_id           uuid not null references employees(id) on delete cascade,
  lark_instance_code    varchar(100) not null unique,
  lark_approval_status  varchar(20) not null,
  lark_approved_at      timestamptz,
  amount                numeric(12,2) not null,
  reason                text,
  status                cash_advance_status not null default 'PENDING',
  is_deducted           boolean not null default false,
  deducted_at           timestamptz,
  payroll_run_id        uuid references payroll_runs(id),
  payslip_line_id       uuid,
  synced_at             timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index on cash_advances (employee_id, status);
create index on cash_advances (company_id, status);
create trigger _cash_advances_updated before update on cash_advances for each row execute function set_updated_at();

create table reimbursements (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references companies(id),
  employee_id           uuid not null references employees(id) on delete cascade,
  lark_instance_code    varchar(100) not null unique,
  lark_approval_status  varchar(20) not null,
  lark_approved_at      timestamptz,
  amount                numeric(12,2) not null,
  reimbursement_type    varchar(100),
  reason                text,
  transaction_date      date,
  status                reimbursement_status not null default 'PENDING',
  is_paid               boolean not null default false,
  paid_at               timestamptz,
  payroll_run_id        uuid references payroll_runs(id),
  payslip_line_id       uuid,
  synced_at             timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index on reimbursements (employee_id, status);
create index on reimbursements (company_id, status);
create trigger _reimbursements_updated before update on reimbursements for each row execute function set_updated_at();

-- Backfill payslip_lines FKs
alter table payslip_lines
  add constraint payslip_lines_penalty_installment_fkey
  foreign key (penalty_installment_id) references penalty_installments(id);
alter table payslip_lines
  add constraint payslip_lines_cash_advance_fkey
  foreign key (cash_advance_id) references cash_advances(id);
alter table payslip_lines
  add constraint payslip_lines_reimbursement_fkey
  foreign key (reimbursement_id) references reimbursements(id);
