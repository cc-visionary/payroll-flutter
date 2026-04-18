-- Hiring-entity bank accounts: the company's own bank accounts that payroll
-- disburses FROM. Mirrors employee_bank_accounts in shape, keyed by
-- hiring_entity_id so GameCove and Luxium banking stay separate.
--
-- Idempotent: safe to re-run on a database where the table was already
-- created manually (e.g., via Supabase Studio) before the migration history
-- caught up.
create table if not exists hiring_entity_bank_accounts (
  id                uuid primary key default gen_random_uuid(),
  hiring_entity_id  uuid not null references hiring_entities(id) on delete cascade,
  bank_code         varchar(20) not null,
  bank_name         varchar(100) not null,
  account_number    varchar(50) not null,
  account_name      varchar(255) not null,
  account_type      varchar(20),
  is_primary        boolean not null default false,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index if not exists hiring_entity_bank_accounts_entity_live_idx
  on hiring_entity_bank_accounts (hiring_entity_id)
  where deleted_at is null;
drop trigger if exists _hiring_entity_bank_accounts_updated
  on hiring_entity_bank_accounts;
create trigger _hiring_entity_bank_accounts_updated
  before update on hiring_entity_bank_accounts
  for each row execute function set_updated_at();

-- RLS: SELECT for anyone in the same company; write for HR/ADMIN/SUPER_ADMIN.
alter table hiring_entity_bank_accounts enable row level security;

drop policy if exists hiring_entity_bank_accounts_select on hiring_entity_bank_accounts;
drop policy if exists hiring_entity_bank_accounts_write  on hiring_entity_bank_accounts;

create policy hiring_entity_bank_accounts_select on hiring_entity_bank_accounts
  for select using (
    exists (
      select 1 from hiring_entities he
       where he.id = hiring_entity_id
         and (he.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
    )
  );

create policy hiring_entity_bank_accounts_write on hiring_entity_bank_accounts
  for all using (
    auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and exists (
      select 1 from hiring_entities he
       where he.id = hiring_entity_id
         and (he.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
    )
  ) with check (
    auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and exists (
      select 1 from hiring_entities he
       where he.id = hiring_entity_id
         and (he.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
    )
  );
