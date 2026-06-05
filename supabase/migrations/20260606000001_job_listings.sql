-- 20260606000001_job_listings.sql
--
-- Adds a job_listings table that owns applicants. Headcount is slot-based:
-- the filled count is derived at read time from COUNT(active employees in
-- this role + brand), never stored. Applicants get a nullable listing_id —
-- existing applicants stay NULL and appear in the "Talent Pool" tab.

create table job_listings (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id),
  hiring_entity_id    uuid not null references hiring_entities(id),
  role_scorecard_id   uuid not null references role_scorecards(id),
  title               varchar(255) not null,
  target_headcount    integer not null default 1 check (target_headcount >= 1),
  status              text not null default 'OPEN'
    check (status in ('OPEN', 'PAUSED', 'CLOSED')),
  notes               text,
  created_at          timestamptz not null default now(),
  created_by_id       uuid references auth.users(id),
  closed_at           timestamptz,
  deleted_at          timestamptz,
  updated_at          timestamptz not null default now()
);

create index idx_job_listings_status_active
  on job_listings (status)
  where deleted_at is null;

create index idx_job_listings_role_brand
  on job_listings (role_scorecard_id, hiring_entity_id);

create index idx_job_listings_company
  on job_listings (company_id)
  where deleted_at is null;

create trigger _job_listings_updated before update on job_listings
  for each row execute function set_updated_at();

-- RLS — mirrors applicants pattern (company-scoped + role-gated).
alter table job_listings enable row level security;

create policy job_listings_company_select on job_listings for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');

create policy job_listings_company_write on job_listings for all
  using (
    (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
    or auth_app_role() = 'SUPER_ADMIN'
  )
  with check (
    (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
    or auth_app_role() = 'SUPER_ADMIN'
  );

-- Add listing_id to applicants. Nullable: NULL = Talent Pool.
alter table applicants
  add column listing_id uuid references job_listings(id);

create index idx_applicants_listing_id
  on applicants (listing_id)
  where deleted_at is null and listing_id is not null;
