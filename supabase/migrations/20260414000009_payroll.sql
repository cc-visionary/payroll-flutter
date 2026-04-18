-- Payroll: calendars, periods, runs, payslips, lines, manual adjustments
-- Adds deferred FK on attendance_day_records.locked_by_payroll_run_id

create table payroll_calendars (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id),
  year          integer not null,
  pay_frequency pay_frequency not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (company_id, year, pay_frequency)
);
create trigger _payroll_calendars_updated before update on payroll_calendars for each row execute function set_updated_at();

create table pay_periods (
  id             uuid primary key default gen_random_uuid(),
  calendar_id    uuid not null references payroll_calendars(id) on delete cascade,
  code           varchar(100) not null,
  start_date     date not null,
  end_date       date not null,
  cutoff_date    date not null,
  pay_date       date not null,
  period_number  integer not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (calendar_id, code)
);
create index on pay_periods (start_date, end_date);
create trigger _pay_periods_updated before update on pay_periods for each row execute function set_updated_at();

create table payroll_runs (
  id                uuid primary key default gen_random_uuid(),
  pay_period_id     uuid not null references pay_periods(id) on delete cascade,
  status            payroll_run_status not null default 'DRAFT',
  total_gross_pay   numeric(14,2) not null default 0,
  total_deductions  numeric(14,2) not null default 0,
  total_net_pay     numeric(14,2) not null default 0,
  employee_count    integer not null default 0,
  payslip_count     integer not null default 0,
  created_by_id     uuid references users(id),
  approved_by_id    uuid references users(id),
  approved_at       timestamptz,
  released_at       timestamptz,
  remarks           text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index on payroll_runs (pay_period_id);
create index on payroll_runs (status);
create trigger _payroll_runs_updated before update on payroll_runs for each row execute function set_updated_at();

-- Backfill attendance_day_records -> payroll_runs FK
alter table attendance_day_records
  add constraint attendance_day_records_locked_by_payroll_run_id_fkey
  foreign key (locked_by_payroll_run_id) references payroll_runs(id);

create table payslips (
  id                          uuid primary key default gen_random_uuid(),
  payroll_run_id              uuid not null references payroll_runs(id) on delete cascade,
  employee_id                 uuid not null references employees(id),
  payslip_number              varchar(50),
  gross_pay                   numeric(12,2) not null,
  total_earnings              numeric(12,2) not null,
  total_deductions            numeric(12,2) not null,
  net_pay                     numeric(12,2) not null,
  sss_ee                      numeric(10,2) not null default 0,
  sss_er                      numeric(10,2) not null default 0,
  philhealth_ee               numeric(10,2) not null default 0,
  philhealth_er               numeric(10,2) not null default 0,
  pagibig_ee                  numeric(10,2) not null default 0,
  pagibig_er                  numeric(10,2) not null default 0,
  withholding_tax             numeric(10,2) not null default 0,
  ytd_gross_pay               numeric(14,2) not null default 0,
  ytd_taxable_income          numeric(14,2) not null default 0,
  ytd_tax_withheld            numeric(14,2) not null default 0,
  pay_profile_snapshot        jsonb not null,
  pdf_path                    varchar(500),
  pdf_generated_at            timestamptz,
  payment_source_account      varchar(50),
  payment_method              varchar(20),
  lark_approval_instance_code varchar(100),
  lark_approval_sent_at       timestamptz,
  lark_approval_status        varchar(20),
  approval_status             payslip_approval_status not null default 'DRAFT_IN_REVIEW',
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  unique (payroll_run_id, employee_id)
);
create index on payslips (employee_id);
create index on payslips (lark_approval_instance_code);
create trigger _payslips_updated before update on payslips for each row execute function set_updated_at();

create table manual_adjustment_lines (
  id              uuid primary key default gen_random_uuid(),
  payroll_run_id  uuid not null references payroll_runs(id),
  employee_id     uuid not null references employees(id),
  category        payslip_line_category not null,
  description     varchar(255) not null,
  amount          numeric(12,2) not null,
  remarks         text,
  created_by_id   uuid references users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on manual_adjustment_lines (payroll_run_id, employee_id);
create trigger _manual_adjustment_lines_updated before update on manual_adjustment_lines for each row execute function set_updated_at();

create table payslip_lines (
  id                        uuid primary key default gen_random_uuid(),
  payslip_id                uuid not null references payslips(id) on delete cascade,
  category                  payslip_line_category not null,
  description               varchar(255) not null,
  quantity                  numeric(10,4),
  rate                      numeric(12,4),
  multiplier                numeric(4,2),
  amount                    numeric(12,2) not null,
  attendance_day_record_id  uuid references attendance_day_records(id),
  manual_adjustment_id      uuid references manual_adjustment_lines(id),
  penalty_installment_id    uuid,  -- FK added in benefits migration
  cash_advance_id           uuid,  -- FK added in benefits migration
  reimbursement_id          uuid,  -- FK added in benefits migration
  rule_code                 varchar(50),
  rule_description          varchar(255),
  sort_order                integer not null default 0,
  created_at                timestamptz not null default now()
);
create index on payslip_lines (payslip_id, category);
