-- Workflows: workflow_instances, workflow_steps

create table workflow_instances (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id),
  employee_id     uuid not null references employees(id),
  workflow_type   workflow_type not null,
  status          workflow_status not null default 'DRAFT',
  title           varchar(255) not null,
  context         jsonb not null default '{}'::jsonb,
  result          jsonb,
  initiated_by_id uuid not null references users(id),
  completed_at    timestamptz,
  cancelled_at    timestamptz,
  cancel_reason   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on workflow_instances (company_id, workflow_type, status);
create index on workflow_instances (employee_id);
create index on workflow_instances (initiated_by_id);
create trigger _workflow_instances_updated before update on workflow_instances for each row execute function set_updated_at();

create table workflow_steps (
  id                    uuid primary key default gen_random_uuid(),
  workflow_instance_id  uuid not null references workflow_instances(id) on delete cascade,
  step_index            integer not null,
  step_type             workflow_step_type not null,
  name                  varchar(255) not null,
  description           text,
  status                workflow_step_status not null default 'PENDING',
  assigned_to_id        uuid references users(id),
  input_data            jsonb,
  output_data           jsonb,
  completed_by_id       uuid references users(id),
  completed_at          timestamptz,
  remarks               text,
  generated_document_id uuid references employee_documents(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (workflow_instance_id, step_index)
);
create index on workflow_steps (workflow_instance_id, status);
create trigger _workflow_steps_updated before update on workflow_steps for each row execute function set_updated_at();
