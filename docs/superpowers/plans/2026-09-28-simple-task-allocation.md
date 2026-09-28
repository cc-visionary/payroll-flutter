# Simple Task Allocation (Role First) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Workforce Planning's three competing "who does this" mechanisms with one rule (every task belongs to exactly one role, hours split across the role's holders by capacity), a 3-input task form, and a Role board front door — 5 tabs become 3.

**Architecture:** One SQL migration converts existing data non-destructively (adds `wp_tasks.allocation_review_note`, resolves each task to one role, redefines `wp_person_load` to read only `wp_tasks.role_scorecard_id` × holders, capacity-weighted). Two new pure Dart units (`frequency.dart`, `role_load.dart`) hold all the math and are unit-tested; the widgets (`RolesBoardTab`, `AllTasksTab`, simplified `TaskFormDialog`) only render them. Old tabs and the % assignment machinery are deleted last, once nothing imports them.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase Postgres views, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-28-simple-task-allocation-design.md`

## Global Constraints

- One role per task: `wp_tasks.role_scorecard_id` is the ONLY "who" the app reads after this change. `owner_employee_id` and `wp_task_assignments` rows are kept in the DB, never deleted, never read for load.
- A holder = employee with that `role_scorecard_id`, `employment_status = 'ACTIVE'`, `deleted_at IS NULL`.
- Split is capacity-weighted: holder share = holder capacity ÷ Σ holders' capacity. Capacity = `wp_capacity_overrides.capacity_hours` → `wp_config.default_capacity_hours` → 160.
- Frequencies: Daily = 26/mo, Weekly = 52/12/mo, Monthly = 1/mo, Quarterly = 1/3/mo, Per order = driver volume. Tokens stored in `cadence`: `DAILY`, `WEEKLY`, `MONTHLY`, `QUARTERLY`, `PER_ORDER`.
- Load bands unchanged: Under < 80%, OK 80–100%, Over > 100% (`capacity_math.dart`).
- "Checked by" is derived from holders' `reports_to_id` managers' roles; 0 hours; never an input.
- Legacy capacity-model reference rows (`external_ref IS NOT NULL AND role_scorecard_id IS NULL`) are NOT genuine work: never shown in "No role yet", never flagged.
- Design system (AGENTS.md): single CTA purple via theme; Geist Mono for numbers (use the existing theme's mono style if present, else `fontFamily: 'Geist Mono'`); 4px spacing grid; status chips via `StatusChip`/`LoadStatusChip` (tinted, no borders); tables wrapped with `ResponsiveTable`.
- Repo is NOT gated on `dart format` — match surrounding style; gate on `flutter analyze` (no new issues) and `flutter test`.
- Multiple sessions share this working dir: do the work in a git worktree (superpowers:using-git-worktrees). The main tree has unrelated uncommitted OT-track changes — never stage them.
- The migration is applied to prod by the OWNER (`supabase db push --linked`); auto-mode blocks it. Do not claim it is applied.

## Review Focus

1. A role with **zero holders** but tasks → must not divide by zero; shows "Nobody holds this role", `needs` still counts its hours, sorts with the over-loaded roles. (Test in Task 2.)
2. A **part-timer** (capacity override 80h) sharing a role with a 160h holder → both show the same load %, part-timer gets 1/3 of hours. (Test in Task 2 and SQL check in Task 1.)
3. A task **dragged onto the role it already belongs to**, or dragged then dragged back → no draft recorded / draft removed; Apply count stays honest. (Test in Task 7.)
4. Reopening a **legacy task** (driver-based with no cadence token, manual times×minutes, or direct hours) in the new form → opens on the right preset, and Save without edits does not change its hours. (Test in Task 4.)
5. An employee who **reports to nobody** or to someone with no role → "Checked by —", no crash. (Test in Task 2.)

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `supabase/migrations/20260929000001_wp_role_first_allocation.sql` | Create | review-note column, data conversion, new `wp_person_load` |
| `supabase/tests/wp_role_first_allocation_check.sql` | Create | psql assertions run against an isolated local DB |
| `lib/features/workforce_planning/frequency.dart` | Create | frequency presets ↔ stored columns, h/mo preview |
| `lib/features/workforce_planning/role_load.dart` | Create | per-role figures, capacity-weighted shares, moves, checked-by, no-role/flagged lists |
| `lib/data/models/workforce_planning.dart` | Modify | `WpTask.allocationReviewNote` |
| `lib/data/repositories/workforce_planning_repository.dart` | Modify | `moveTasksToRoles`, `clearReviewNote`; stop syncing assignments |
| `lib/features/workforce_planning/tabs/task_form_dialog.dart` | Rewrite | 3 inputs + More details |
| `lib/features/workforce_planning/board/role_load_card.dart` | Create | one role card (drop target) |
| `lib/features/workforce_planning/board/board_sections.dart` | Create | people strip, No role yet, Check these |
| `lib/features/workforce_planning/tabs/roles_board_tab.dart` | Create | the front door: drafts, hover, Apply |
| `lib/features/workforce_planning/tabs/all_tasks_tab.dart` | Create | searchable task list |
| `lib/features/workforce_planning/workforce_planning_screen.dart` | Modify | 3 tabs |
| `lib/features/workforce_planning/needs_attention.dart` + `tabs/needs_attention_strip.dart` | Modify | new rules, new tab indexes |
| `lib/data/repositories/role_scorecard_repository.dart` | Modify | drop shared responsibilities |
| `lib/features/documents/templates/employment_contract_template.dart` | Modify | drop owned-task Annex append |
| `wp_providers.dart` | Modify | host `ownerComputedProvider`, drop assignment providers |
| balance_tab, role_view_tab, unassigned_tab, assignment_panel, allocation, rebalance, unassigned_workspace, balance_rows, responsibilities_tab, tasks_paging, task_costing, role_rollup (+ their tests) | Delete | superseded |

---

### Task 0: Worktree

- [ ] **Step 1:** Use superpowers:using-git-worktrees to create branch `feat/simple-task-allocation` from `main`. All later paths are relative to the worktree root.
- [ ] **Step 2:** Baseline: `flutter analyze 2>&1 | tail -3` and `flutter test test/features/workforce_planning 2>&1 | tail -3`. Record the issue count and pass count in your notes — later tasks compare against it.

---

### Task 1: Migration — review note, conversion, role-only capacity-weighted load

**Files:**
- Create: `supabase/migrations/20260929000001_wp_role_first_allocation.sql`
- Create: `supabase/tests/wp_role_first_allocation_check.sql`

**Interfaces:**
- Produces: column `wp_tasks.allocation_review_note text` (nullable); view `wp_person_load` with the SAME columns as today (`employee_id, company_id, tasks_owned, hours_fixed, hours_growing_base, capacity_hours, growth_multiplier`) so `WpPersonLoad.fromRow` is unchanged.

- [ ] **Step 1: Write the migration**

```sql
-- Role-first task allocation (spec 2026-09-28-simple-task-allocation-design.md).
-- Every task belongs to exactly one role; its hours split across the role's
-- ACTIVE holders in proportion to capacity. owner_employee_id and
-- wp_task_assignments are KEPT (rollback = restore 20260724000003's view) but
-- no longer read by wp_person_load.

alter table wp_tasks add column if not exists allocation_review_note text;

-- 1) Tasks with assignment rows: resolve to ONE role.
with ranked as (
  select distinct on (a.task_id)
         a.task_id,
         coalesce(a.role_scorecard_id, e.role_scorecard_id) as role_id,
         count(*) over (partition by a.task_id)            as n_rows
  from wp_task_assignments a
  left join employees e on e.id = a.employee_id
  order by a.task_id,
           (a.assignment_role = 'PRIMARY') desc,
           a.allocation_pct desc
),
was as (
  select a.task_id,
         'was: ' || string_agg(
           coalesce(rs.job_title, e.first_name || ' ' || e.last_name, '?')
             || ' ' || round(a.allocation_pct)::text || '%',
           ', ' order by a.allocation_pct desc) as note
  from wp_task_assignments a
  left join role_scorecards rs on rs.id = a.role_scorecard_id
  left join employees       e  on e.id  = a.employee_id
  group by a.task_id
)
update wp_tasks t
set role_scorecard_id = coalesce(r.role_id, t.role_scorecard_id),
    allocation_review_note = case
      when r.n_rows > 1
        or r.role_id is null
        or r.role_id is distinct from t.role_scorecard_id
      then w.note end
from ranked r
join was w on w.task_id = r.task_id
where t.id = r.task_id
  and t.status = 'ACTIVE';

-- 2) No assignment rows, no role, but an explicit owner: take the owner's role.
update wp_tasks t
set role_scorecard_id = e.role_scorecard_id,
    allocation_review_note = case when e.role_scorecard_id is null
      then 'was: owned by ' || e.first_name || ' ' || e.last_name
           || ' (who has no role)' end
from employees e
where e.id = t.owner_employee_id
  and t.role_scorecard_id is null
  and t.status = 'ACTIVE'
  and not exists (select 1 from wp_task_assignments a where a.task_id = t.id);

-- 3) wp_person_load: role only, capacity-weighted.
create or replace view wp_person_load with (security_invoker = true) as
with holders as (
  select e.id as employee_id, e.company_id, e.role_scorecard_id,
         coalesce(ov.capacity_hours, cfg.default_capacity_hours, 160) as cap
  from employees e
  left join wp_capacity_overrides ov  on ov.employee_id = e.id
  left join wp_config             cfg on cfg.company_id = e.company_id
  where e.employment_status = 'ACTIVE' and e.deleted_at is null
    and e.role_scorecard_id is not null
),
role_cap as (
  select role_scorecard_id, sum(cap) as total_cap
  from holders group by role_scorecard_id
),
attributed as (
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base * h.cap / rc.total_cap as hours,
         tc.is_growing
  from wp_task_computed tc
  join wp_tasks t   on t.id = tc.task_id
  join holders  h   on h.role_scorecard_id = t.role_scorecard_id
  join role_cap rc  on rc.role_scorecard_id = h.role_scorecard_id
  where rc.total_cap > 0
)
select
  e.id         as employee_id,
  e.company_id,
  count(a.task_id) as tasks_owned,
  coalesce(sum(a.hours) filter (where not a.is_growing), 0) as hours_fixed,
  coalesce(sum(a.hours) filter (where a.is_growing), 0)     as hours_growing_base,
  coalesce(ov.capacity_hours, cfg.default_capacity_hours, 160) as capacity_hours,
  coalesce(cfg.growth_multiplier, 1) as growth_multiplier
from employees e
left join attributed            a   on a.employee_id = e.id
left join wp_capacity_overrides ov  on ov.employee_id = e.id
left join wp_config             cfg on cfg.company_id = e.company_id
where e.employment_status = 'ACTIVE' and e.deleted_at is null
group by e.id, e.company_id, ov.capacity_hours, cfg.default_capacity_hours, cfg.growth_multiplier;
```

- [ ] **Step 2: Write the check script** (`supabase/tests/wp_role_first_allocation_check.sql`). It seeds its own rows inside a transaction, runs the migration's statements by `\i`, asserts, and rolls back.

```sql
-- Run: psql "$LOCAL_DB" -v ON_ERROR_STOP=1 -f supabase/tests/wp_role_first_allocation_check.sql
-- Against an isolated local copy with every migration BEFORE 20260929000001
-- applied and supabase/seed/01_company.sql loaded (it creates company
-- 11111111-1111-1111-1111-000000000001, used below).
begin;
insert into role_scorecards (id, company_id, job_title, mission_statement, key_responsibilities, kpis, wage_type, work_hours_per_day, work_days_per_week, is_active, effective_date) values
 ('00000000-0000-0000-0000-0000000000a1','11111111-1111-1111-1111-000000000001','Brand Handler','','[]','[]','MONTHLY',8,'MON_FRI',true,'2026-01-01'),
 ('00000000-0000-0000-0000-0000000000a2','11111111-1111-1111-1111-000000000001','Ops Manager',  '','[]','[]','MONTHLY',8,'MON_FRI',true,'2026-01-01');
-- e1/e2 Brand Handler (e2 part-time 80h), e3 Ops Manager, e4 no role.
insert into employees (id, company_id, employee_number, first_name, last_name, hire_date, role_scorecard_id, employment_status) values
 ('00000000-0000-0000-0000-0000000000e1','11111111-1111-1111-1111-000000000001','T-E1','Ana','Test','2024-01-01','00000000-0000-0000-0000-0000000000a1','ACTIVE'),
 ('00000000-0000-0000-0000-0000000000e2','11111111-1111-1111-1111-000000000001','T-E2','Ben','Test','2024-01-01','00000000-0000-0000-0000-0000000000a1','ACTIVE'),
 ('00000000-0000-0000-0000-0000000000e3','11111111-1111-1111-1111-000000000001','T-E3','Jer','Test','2024-01-01','00000000-0000-0000-0000-0000000000a2','ACTIVE'),
 ('00000000-0000-0000-0000-0000000000e4','11111111-1111-1111-1111-000000000001','T-E4','Nox','Test','2024-01-01',null,'ACTIVE');
insert into wp_capacity_overrides (employee_id, capacity_hours) values ('00000000-0000-0000-0000-0000000000e2', 80);
insert into wp_tasks (id, company_id, name, role_scorecard_id, owner_employee_id, hours_per_month, external_ref) values
 ('00000000-0000-0000-0000-0000000000f1','11111111-1111-1111-1111-000000000001','card only',        '00000000-0000-0000-0000-0000000000a1', null, 30, null),
 ('00000000-0000-0000-0000-0000000000f2','11111111-1111-1111-1111-000000000001','split 60/40',      '00000000-0000-0000-0000-0000000000a1', null, 10, null),
 ('00000000-0000-0000-0000-0000000000f3','11111111-1111-1111-1111-000000000001','owner no card',    null, '00000000-0000-0000-0000-0000000000e3', 5, null),
 ('00000000-0000-0000-0000-0000000000f4','11111111-1111-1111-1111-000000000001','owner has no role',null, '00000000-0000-0000-0000-0000000000e4', 5, null),
 ('00000000-0000-0000-0000-0000000000f5','11111111-1111-1111-1111-000000000001','legacy ref',       null, null, 99, 'XLSX-1');
insert into wp_task_assignments (company_id, task_id, role_scorecard_id, employee_id, assignment_role, allocation_pct) values
 ('11111111-1111-1111-1111-000000000001','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000a1',null,'PRIMARY',100),
 ('11111111-1111-1111-1111-000000000001','00000000-0000-0000-0000-0000000000f2',null,'00000000-0000-0000-0000-0000000000e3','PRIMARY',60),
 ('11111111-1111-1111-1111-000000000001','00000000-0000-0000-0000-0000000000f2','00000000-0000-0000-0000-0000000000a1',null,'CONTRIBUTOR',40);

\i supabase/migrations/20260929000001_wp_role_first_allocation.sql

do $$
declare r record;
begin
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f1';
  assert r.role_scorecard_id = '00000000-0000-0000-0000-0000000000a1' and r.allocation_review_note is null, 'f1 unchanged, unflagged';
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f2';
  assert r.role_scorecard_id = '00000000-0000-0000-0000-0000000000a2', 'f2 -> PRIMARY person''s role (Ops Manager)';
  assert r.allocation_review_note like 'was: %60%%40%', 'f2 flagged with both rows';
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f3';
  assert r.role_scorecard_id = '00000000-0000-0000-0000-0000000000a2' and r.allocation_review_note is null, 'f3 -> owner role';
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f4';
  assert r.role_scorecard_id is null and r.allocation_review_note like '%has no role%', 'f4 flagged';
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f5';
  assert r.role_scorecard_id is null and r.allocation_review_note is null, 'legacy untouched';
  assert (select count(*) from wp_task_assignments where task_id = '00000000-0000-0000-0000-0000000000f2') = 2, 'assignments kept';
  -- capacity-weighted: Brand Handler has 30h (f1); e1 160h gets 20h, e2 80h gets 10h -> both 12.5%
  assert (select round(hours_fixed::numeric,2) from wp_person_load where employee_id = '00000000-0000-0000-0000-0000000000e1') = 20.00, 'e1 20h';
  assert (select round(hours_fixed::numeric,2) from wp_person_load where employee_id = '00000000-0000-0000-0000-0000000000e2') = 10.00, 'e2 10h';
  -- Ops Manager: f2 10h + f3 5h
  assert (select round(hours_fixed::numeric,2) from wp_person_load where employee_id = '00000000-0000-0000-0000-0000000000e3') = 15.00, 'e3 15h';
  assert (select hours_fixed from wp_person_load where employee_id = '00000000-0000-0000-0000-0000000000e4') = 0, 'no-role person 0h';
end $$;
rollback;
```

If an insert fails on a NOT NULL column added by a later migration, add that column with a valid literal to the insert — do not drop the row.

- [ ] **Step 3: Run it against an isolated local DB** — follow `reference_local_supabase_rls_testing` memory: copy `supabase/` to the scratchpad, set `project_id = "payroll-rlstest"`, ports 543xx→643xx, change `inspector_port`, `[db.migrations] enabled = false`, `supabase start -x realtime,storage-api,imgproxy,studio,edge-runtime,logflare,vector,supavisor,mailpit,inbucket`, apply every migration before `20260929000001` in order with psql (run `supabase/seed/01_company.sql` before `20260418000002`). Then:

Run: `psql "postgresql://postgres:postgres@127.0.0.1:64322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/wp_role_first_allocation_check.sql`
Expected: ends with `ROLLBACK`, no `ASSERT` failure.

If the local stack cannot be started, STOP and report BLOCKED with the error — do not skip to Step 4.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260929000001_wp_role_first_allocation.sql supabase/tests/wp_role_first_allocation_check.sql
git commit -m "feat(wp): role-first allocation migration (one role per task, capacity-weighted load)"
```

---

### Task 2: `role_load.dart` — role figures, shares, moves, checked-by

**Files:**
- Create: `lib/features/workforce_planning/role_load.dart`
- Test: `test/features/workforce_planning/role_load_test.dart`

**Interfaces:**
- Consumes: `WpTask`, `WpTaskComputed`, `WpPersonLoad` (models), `Employee`, `RoleScorecard`, `loadStatus`/`LoadStatus` (`capacity_math.dart`).
- Produces:
  - `typedef RoleMoves = Map<String, String>;` (taskId → roleId)
  - `double taskHours(WpTaskComputed? c, double multiplier)`
  - `class RoleHolder { Employee employee; double capacityHours; }`
  - `class RoleLoad { RoleScorecard role; List<RoleHolder> holders; List<WpTask> tasks; double workHours; double defaultCapacity; double get capacityHours; double get load; double get peopleNeeded; double get shortBy; LoadStatus get status; bool get unstaffedWithWork; double hoursFor(String employeeId); }`
  - `List<RoleLoad> buildRoleLoads({required List<RoleScorecard> roles, required List<Employee> employees, required List<WpTask> tasks, required Map<String, double> hoursByTaskId, required Map<String, double> capacityByEmployee, required double defaultCapacity, RoleMoves moves = const {}})` — sorted: unstaffed-with-work first, then load descending, then title.
  - `List<String> checkedByTitles({required RoleScorecard role, required List<Employee> employees, required Map<String, RoleScorecard> rolesById})`
  - `bool isLegacyReference(WpTask t)`
  - `List<WpTask> noRoleTasks(List<WpTask> tasks, {RoleMoves moves = const {}})`
  - `List<WpTask> flaggedTasks(List<WpTask> tasks)`
  - `String? roleOf(WpTask t, RoleMoves moves)`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/capacity_math.dart';
import 'package:payroll_flutter/features/workforce_planning/role_load.dart';

Employee emp(String id, {String? role, String? reportsTo, String status = 'ACTIVE'}) => Employee(
  id: id, companyId: 'c', employeeNumber: id, firstName: id, lastName: 'X',
  roleScorecardId: role, reportsToId: reportsTo,
  employmentType: 'FULL_TIME', employmentStatus: status,
  hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
  isNdEligible: false, isHolidayPayEligible: false,
  sssEligibilityOverride: false, philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false, taxOnFullEarnings: false,
);

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

WpTask task(String id, {String? role, String? note, String? ext, String status = 'ACTIVE'}) =>
    WpTask(id: id, companyId: 'c', name: id, roleScorecardId: role,
        allocationReviewNote: note, externalRef: ext, status: status);

void main() {
  final bh = role('bh', 'Brand Handler');
  final om = role('om', 'Ops Manager');
  final kiosk = role('k', 'Kiosk Rep');

  List<RoleLoad> build({RoleMoves moves = const {}, Map<String, double>? caps}) => buildRoleLoads(
    roles: [bh, om, kiosk],
    employees: [
      emp('ana', role: 'bh', reportsTo: 'jer'),
      emp('ben', role: 'bh', reportsTo: 'jer'),
      emp('jer', role: 'om'),
      emp('gone', role: 'bh', status: 'SEPARATED'),
    ],
    tasks: [task('t1', role: 'bh'), task('t2', role: 'bh'), task('t3', role: 'om'), task('t4', role: 'k')],
    hoursByTaskId: {'t1': 200, 't2': 40, 't3': 100, 't4': 50},
    capacityByEmployee: caps ?? {'ana': 160, 'ben': 160, 'jer': 160},
    defaultCapacity: 160,
    moves: moves,
  );

  test('work, capacity, load, needs and short for a two-holder role', () {
    final r = build().firstWhere((x) => x.role.id == 'bh');
    expect(r.holders.map((h) => h.employee.id), ['ana', 'ben'], reason: 'SEPARATED excluded');
    expect(r.workHours, 240);
    expect(r.capacityHours, 320);
    expect(r.load, closeTo(0.75, 1e-9));
    expect(r.peopleNeeded, closeTo(1.5, 1e-9));
    expect(r.shortBy, 0);
    expect(r.status, LoadStatus.under);
  });

  test('capacity-weighted: a part-timer gets a smaller share, same load %', () {
    final r = build(caps: {'ana': 160, 'ben': 80, 'jer': 160}).firstWhere((x) => x.role.id == 'bh');
    expect(r.hoursFor('ana'), closeTo(160, 1e-9));
    expect(r.hoursFor('ben'), closeTo(80, 1e-9));
    expect(r.hoursFor('ana') / 160, closeTo(r.hoursFor('ben') / 80, 1e-9));
  });

  test('zero-holder role: no division by zero, needs counts, sorts first', () {
    final loads = build();
    expect(loads.first.role.id, 'k');
    final k = loads.first;
    expect(k.holders, isEmpty);
    expect(k.load, 0);
    expect(k.unstaffedWithWork, isTrue);
    expect(k.peopleNeeded, closeTo(50 / 160, 1e-9));
    expect(k.shortBy, closeTo(50 / 160, 1e-9));
    expect(k.hoursFor('ana'), 0);
  });

  test('a draft move shifts hours between roles', () {
    final before = build();
    final after = build(moves: {'t1': 'om'});
    double work(List<RoleLoad> l, String id) => l.firstWhere((x) => x.role.id == id).workHours;
    expect(work(before, 'om'), 100);
    expect(work(after, 'om'), 300);
    expect(work(after, 'bh'), 40);
    expect(after.firstWhere((x) => x.role.id == 'om').status, LoadStatus.over);
  });

  test('over-loaded roles sort before under-loaded ones', () {
    final ids = build(moves: {'t1': 'om'}).map((r) => r.role.id).toList();
    expect(ids, ['k', 'om', 'bh']);
  });

  test('checked by = distinct roles of the holders\' managers', () {
    final byId = {for (final r in [bh, om, kiosk]) r.id: r};
    final emps = [emp('ana', role: 'bh', reportsTo: 'jer'), emp('ben', role: 'bh', reportsTo: 'jer'), emp('jer', role: 'om')];
    expect(checkedByTitles(role: bh, employees: emps, rolesById: byId), ['Ops Manager']);
    expect(checkedByTitles(role: om, employees: emps, rolesById: byId), isEmpty, reason: 'reports to nobody');
  });

  test('checked by skips a manager with no role', () {
    final emps = [emp('ana', role: 'bh', reportsTo: 'boss'), emp('boss')];
    expect(checkedByTitles(role: bh, employees: emps, rolesById: {'bh': bh}), isEmpty);
  });

  test('no-role list excludes legacy reference rows and archived tasks', () {
    final tasks = [task('a'), task('b', ext: 'XLSX-1'), task('c', status: 'ARCHIVED'), task('d', role: 'bh')];
    expect(noRoleTasks(tasks).map((t) => t.id), ['a']);
    expect(noRoleTasks(tasks, moves: {'a': 'bh'}), isEmpty);
  });

  test('flagged list = active tasks carrying a review note', () {
    final tasks = [task('a', note: 'was: x'), task('b'), task('c', note: 'was: y', status: 'ARCHIVED')];
    expect(flaggedTasks(tasks).map((t) => t.id), ['a']);
  });

  test('taskHours projects growing work by the multiplier', () {
    const fixed = WpTaskComputed(taskId: 'a', companyId: 'c', hoursPerMonthBase: 10);
    const growing = WpTaskComputed(taskId: 'b', companyId: 'c', hoursPerMonthBase: 10, isGrowing: true);
    expect(taskHours(fixed, 2), 10);
    expect(taskHours(growing, 2), 20);
    expect(taskHours(null, 2), 0);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/role_load_test.dart`
Expected: FAIL — `role_load.dart` not found and `allocationReviewNote` is not a `WpTask` parameter.

- [ ] **Step 3: Add `allocationReviewNote` to `WpTask`** (`lib/data/models/workforce_planning.dart`)

Add the field after `hoursPerMonth`:

```dart
  /// Set by the role-first migration when converting this task to one role
  /// lost information ("was: Jeremy 60%, Brand Handler 40%"). Shown in the
  /// board's "Check these" list until HR clicks "Looks right". Never written
  /// by [toUpsert] — only [WorkforcePlanningRepository.clearReviewNote].
  final String? allocationReviewNote;
```

Add `this.allocationReviewNote,` to the constructor, `allocationReviewNote: r['allocation_review_note'] as String?,` to `fromRow`, and `allocationReviewNote: allocationReviewNote,` to `copyWithSort`. Do NOT add it to `toUpsert`.

- [ ] **Step 4: Write `role_load.dart`**

```dart
import 'dart:math' as math;

import '../../data/models/employee.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import 'capacity_math.dart';

/// Draft role changes dragged on the board but not applied: taskId -> roleId.
typedef RoleMoves = Map<String, String>;

/// A task's monthly hours at [multiplier]: growing work scales, fixed doesn't.
double taskHours(WpTaskComputed? c, double multiplier) {
  if (c == null) return 0;
  return c.isGrowing ? c.hoursPerMonthBase * multiplier : c.hoursPerMonthBase;
}

/// The role a task belongs to under the draft [moves].
String? roleOf(WpTask t, RoleMoves moves) => moves[t.id] ?? t.roleScorecardId;

/// The original capacity-model rows: a reference copy, not genuine work.
bool isLegacyReference(WpTask t) =>
    t.externalRef != null && t.roleScorecardId == null;

class RoleHolder {
  final Employee employee;
  final double capacityHours;
  const RoleHolder(this.employee, this.capacityHours);
}

/// One role's workload against the people holding it. Hours split across
/// holders in proportion to capacity (mirrors wp_person_load), so every
/// holder of a role shares the role's load %.
class RoleLoad {
  final RoleScorecard role;
  final List<RoleHolder> holders;
  final List<WpTask> tasks;
  final double workHours;
  final double defaultCapacity;

  const RoleLoad({
    required this.role,
    required this.holders,
    required this.tasks,
    required this.workHours,
    required this.defaultCapacity,
  });

  double get capacityHours =>
      holders.fold<double>(0, (s, h) => s + h.capacityHours);

  double get load => loadFraction(workHours, capacityHours);

  /// How many standard-capacity people this much work needs.
  double get peopleNeeded =>
      defaultCapacity <= 0 ? 0 : workHours / defaultCapacity;

  double get shortBy => math.max(0, peopleNeeded - holders.length);

  bool get unstaffedWithWork => holders.isEmpty && workHours > 0;

  LoadStatus get status =>
      unstaffedWithWork ? LoadStatus.over : loadStatus(load);

  /// [employeeId]'s share of this role's hours; 0 when not a holder.
  double hoursFor(String employeeId) {
    final cap = capacityHours;
    if (cap <= 0) return 0;
    for (final h in holders) {
      if (h.employee.id == employeeId) return workHours * h.capacityHours / cap;
    }
    return 0;
  }
}

bool _isHolder(Employee e, String roleId) =>
    e.employmentStatus == 'ACTIVE' &&
    e.deletedAt == null &&
    e.roleScorecardId == roleId;

List<RoleLoad> buildRoleLoads({
  required List<RoleScorecard> roles,
  required List<Employee> employees,
  required List<WpTask> tasks,
  required Map<String, double> hoursByTaskId,
  required Map<String, double> capacityByEmployee,
  required double defaultCapacity,
  RoleMoves moves = const {},
}) {
  final tasksByRole = <String, List<WpTask>>{};
  for (final t in tasks) {
    if (t.status != 'ACTIVE') continue;
    final r = roleOf(t, moves);
    if (r != null) (tasksByRole[r] ??= []).add(t);
  }
  final out = [
    for (final role in roles)
      RoleLoad(
        role: role,
        holders: [
          for (final e in employees)
            if (_isHolder(e, role.id))
              RoleHolder(e, capacityByEmployee[e.id] ?? defaultCapacity),
        ],
        tasks: tasksByRole[role.id] ?? const [],
        workHours: (tasksByRole[role.id] ?? const <WpTask>[]).fold<double>(
          0,
          (s, t) => s + (hoursByTaskId[t.id] ?? 0),
        ),
        defaultCapacity: defaultCapacity,
      ),
  ];
  out.sort((a, b) {
    if (a.unstaffedWithWork != b.unstaffedWithWork) {
      return a.unstaffedWithWork ? -1 : 1;
    }
    final byLoad = b.load.compareTo(a.load);
    if (byLoad != 0) return byLoad;
    return a.role.jobTitle.compareTo(b.role.jobTitle);
  });
  return out;
}

/// Who checks this role's work: the distinct roles of the holders' managers
/// (RACI "Accountable"). A label only — it carries no hours.
List<String> checkedByTitles({
  required RoleScorecard role,
  required List<Employee> employees,
  required Map<String, RoleScorecard> rolesById,
}) {
  final byId = {for (final e in employees) e.id: e};
  final titles = <String>{};
  for (final e in employees) {
    if (!_isHolder(e, role.id)) continue;
    final manager = e.reportsToId == null ? null : byId[e.reportsToId];
    final managerRole = manager?.roleScorecardId == null
        ? null
        : rolesById[manager!.roleScorecardId];
    if (managerRole != null) titles.add(managerRole.jobTitle);
  }
  return titles.toList()..sort();
}

/// Genuine ACTIVE work with no role under [moves].
List<WpTask> noRoleTasks(List<WpTask> tasks, {RoleMoves moves = const {}}) => [
  for (final t in tasks)
    if (t.status == 'ACTIVE' && !isLegacyReference(t) && roleOf(t, moves) == null)
      t,
];

/// ACTIVE tasks the migration flagged for a human look.
List<WpTask> flaggedTasks(List<WpTask> tasks) => [
  for (final t in tasks)
    if (t.status == 'ACTIVE' && t.allocationReviewNote != null) t,
];
```

Note `noRoleTasks` must check legacy on the ORIGINAL row (a legacy row moved to a role by a draft is no longer roleless anyway), which `isLegacyReference(t)` does.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/workforce_planning/role_load_test.dart`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/workforce_planning/role_load.dart lib/data/models/workforce_planning.dart test/features/workforce_planning/role_load_test.dart
git commit -m "feat(wp): role load math — capacity-weighted shares, needs/short, checked-by"
```

---

### Task 3: `frequency.dart` — how often × how long

**Files:**
- Create: `lib/features/workforce_planning/frequency.dart`
- Test: `test/features/workforce_planning/frequency_test.dart`

**Interfaces:**
- Consumes: `WpTask`.
- Produces:
  - `enum TaskFrequency { daily, weekly, monthly, quarterly, perOrder, custom }` with `String get token`, `String get label`, `double? get timesPerMonth`
  - `const double kWorkingDaysPerMonth = 26;`
  - `TaskFrequency frequencyOf(WpTask t)`
  - `double? minutesOf(WpTask t)` — per-occurrence minutes to prefill
  - `double? customHoursOf(WpTask t)` — h/mo to prefill for `custom`
  - `double previewHoursPerMonth({required TaskFrequency frequency, double? minutes, double? customHours, double driverVolume = 0, double driverFactor = 1})`
  - `String effortLabel(WpTask t, double hours)` — "Daily · 60 min", "Per order · 3 min", "7.5 h/mo" (custom), "Weekly" (no minutes yet)

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/frequency.dart';

WpTask t({String? cadence, String timesSource = 'manual', double? times, double? minutes, double? hours, String? driverId}) =>
    WpTask(id: 'x', companyId: 'c', name: 'x', cadence: cadence, timesSource: timesSource,
        timesManual: times, minutesManual: minutes, hoursPerMonth: hours, driverId: driverId);

void main() {
  test('preset times per month', () {
    expect(TaskFrequency.daily.timesPerMonth, 26);
    expect(TaskFrequency.weekly.timesPerMonth, closeTo(52 / 12, 1e-9));
    expect(TaskFrequency.monthly.timesPerMonth, 1);
    expect(TaskFrequency.quarterly.timesPerMonth, closeTo(1 / 3, 1e-9));
    expect(TaskFrequency.perOrder.timesPerMonth, isNull);
    expect(TaskFrequency.custom.timesPerMonth, isNull);
  });

  test('tokens round-trip', () {
    for (final f in TaskFrequency.values.where((f) => f != TaskFrequency.custom)) {
      expect(frequencyOf(t(cadence: f.token, times: 1, minutes: 1)), f);
    }
  });

  test('legacy rows open on the right preset', () {
    expect(frequencyOf(t(hours: 12)), TaskFrequency.custom, reason: 'direct hours');
    expect(frequencyOf(t(timesSource: 'driver', driverId: 'd', minutes: 3)), TaskFrequency.perOrder);
    expect(frequencyOf(t(cadence: 'every other day', times: 13, minutes: 30)), TaskFrequency.custom,
        reason: 'free-text cadence with manual times -> custom h/mo');
    expect(frequencyOf(t()), TaskFrequency.weekly, reason: 'blank task defaults to weekly');
  });

  test('custom prefill preserves a legacy manual task\'s hours exactly', () {
    final legacy = t(cadence: 'every other day', times: 13, minutes: 30);
    expect(customHoursOf(legacy), closeTo(6.5, 1e-9));
    expect(customHoursOf(t(hours: 12)), 12);
  });

  test('preview hours per month', () {
    expect(previewHoursPerMonth(frequency: TaskFrequency.daily, minutes: 60), 26);
    expect(previewHoursPerMonth(frequency: TaskFrequency.weekly, minutes: 180), closeTo(13, 1e-9));
    expect(previewHoursPerMonth(frequency: TaskFrequency.perOrder, minutes: 3, driverVolume: 1200, driverFactor: 1), 60);
    expect(previewHoursPerMonth(frequency: TaskFrequency.custom, customHours: 7.5), 7.5);
    expect(previewHoursPerMonth(frequency: TaskFrequency.daily), 0, reason: 'no minutes yet');
  });

  test('effort label reads like a human would say it', () {
    expect(effortLabel(t(cadence: 'DAILY', times: 26, minutes: 60), 26), 'Daily · 60 min');
    expect(effortLabel(t(hours: 7.5), 7.5), '7.5 h/mo');
    expect(effortLabel(t(), 0), 'Weekly');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/frequency_test.dart`
Expected: FAIL — `frequency.dart` not found.

- [ ] **Step 3: Write `frequency.dart`**

```dart
import '../../data/models/workforce_planning.dart';

/// Working days in a month — the same 26 the payroll engine uses.
const double kWorkingDaysPerMonth = 26;

/// How often a task happens. Stored as a token in `wp_tasks.cadence` so the
/// form reopens on the same preset; the times/month it implies is written to
/// `times_manual` (or, for [perOrder], read from a driver).
enum TaskFrequency { daily, weekly, monthly, quarterly, perOrder, custom }

extension TaskFrequencyX on TaskFrequency {
  String get token => switch (this) {
    TaskFrequency.daily => 'DAILY',
    TaskFrequency.weekly => 'WEEKLY',
    TaskFrequency.monthly => 'MONTHLY',
    TaskFrequency.quarterly => 'QUARTERLY',
    TaskFrequency.perOrder => 'PER_ORDER',
    TaskFrequency.custom => 'CUSTOM',
  };

  String get label => switch (this) {
    TaskFrequency.daily => 'Daily',
    TaskFrequency.weekly => 'Weekly',
    TaskFrequency.monthly => 'Monthly',
    TaskFrequency.quarterly => 'Quarterly',
    TaskFrequency.perOrder => 'Per order',
    TaskFrequency.custom => 'Custom (hours / month)',
  };

  double? get timesPerMonth => switch (this) {
    TaskFrequency.daily => kWorkingDaysPerMonth,
    TaskFrequency.weekly => 52 / 12,
    TaskFrequency.monthly => 1,
    TaskFrequency.quarterly => 1 / 3,
    TaskFrequency.perOrder => null,
    TaskFrequency.custom => null,
  };
}

TaskFrequency frequencyOf(WpTask t) {
  if (t.hoursPerMonth != null) return TaskFrequency.custom;
  for (final f in TaskFrequency.values) {
    if (f != TaskFrequency.custom && f.token == t.cadence) return f;
  }
  if (t.timesSource == 'driver') return TaskFrequency.perOrder;
  if (t.timesManual != null || t.minutesManual != null) {
    return TaskFrequency.custom;
  }
  return TaskFrequency.weekly;
}

double? minutesOf(WpTask t) => t.minutesManual;

/// The h/mo to show when a task opens as [TaskFrequency.custom]: its direct
/// hours, or its legacy manual times x minutes, so Save-without-edits keeps
/// the same workload.
double? customHoursOf(WpTask t) {
  if (t.hoursPerMonth != null) return t.hoursPerMonth;
  final times = t.timesManual, minutes = t.minutesManual;
  if (times == null || minutes == null) return null;
  return times * minutes / 60;
}

double previewHoursPerMonth({
  required TaskFrequency frequency,
  double? minutes,
  double? customHours,
  double driverVolume = 0,
  double driverFactor = 1,
}) {
  if (frequency == TaskFrequency.custom) return customHours ?? 0;
  final m = minutes ?? 0;
  final times = frequency == TaskFrequency.perOrder
      ? driverVolume * driverFactor
      : frequency.timesPerMonth!;
  return times * m / 60;
}

/// How a task's effort reads on the board and in lists.
String effortLabel(WpTask t, double hours) {
  final f = frequencyOf(t);
  if (f == TaskFrequency.custom) return '${hours.toStringAsFixed(1)} h/mo';
  final m = t.minutesManual;
  return m == null ? f.label : '${f.label} · ${m.toStringAsFixed(0)} min';
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/workforce_planning/frequency_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/frequency.dart test/features/workforce_planning/frequency_test.dart
git commit -m "feat(wp): frequency presets for task effort"
```

---

### Task 4: Repository — role moves, review note, stop syncing assignments

**Files:**
- Modify: `lib/data/repositories/workforce_planning_repository.dart`

**Interfaces:**
- Produces:
  - `Future<List<String>> moveTasksToRoles(RoleMoves moves)` — returns failed task ids.
  - `Future<void> clearReviewNote(String taskId)`
  - `saveTask` and `setTaskCard` no longer call `_syncPrimaryFromTask`.

- [ ] **Step 1: Edit the repository**

The data layer must not import feature files, so `moveTasksToRoles` takes a plain `Map<String, String>` (`RoleMoves` is a typedef of that type; callers pass it unchanged).

In `saveTask`, drop the `_syncPrimaryFromTask` call; the method becomes:

```dart
  Future<void> saveTask(WpTask task) async {
    final payload = task.toUpsert(task.companyId);
    if (task.id.isEmpty) {
      await _client.from('wp_tasks').insert(payload);
    } else {
      await _client.from('wp_tasks').update(payload).eq('id', task.id);
    }
  }
```

In `setTaskCard`, delete `await _syncPrimaryFromTask(taskId);`. Update its doc comment to: `/// Sets (or clears) a task's role. The role is the only "who" — load follows it via wp_person_load.`

Delete `_syncPrimaryFromTask`. In `reassignTaskOwner` (still called by `balance_tab.dart` until Task 9 deletes it) remove its `_syncPrimaryFromTask` call. Keep `primaryAssignmentPayload` (it has its own tests) until Task 9.

Add:

```dart
  /// Applies the board's draft role moves (taskId -> roleId), one row at a
  /// time so a partial failure keeps the rows that succeeded. Returns the ids
  /// that failed so the board can keep them as drafts.
  Future<List<String>> moveTasksToRoles(Map<String, String> moves) async {
    final failed = <String>[];
    for (final m in moves.entries) {
      try {
        await _client
            .from('wp_tasks')
            .update({'role_scorecard_id': m.value})
            .eq('id', m.key);
      } catch (_) {
        failed.add(m.key);
      }
    }
    return failed;
  }

  /// HR confirmed a migration-flagged task ("Looks right").
  Future<void> clearReviewNote(String taskId) async => _client
      .from('wp_tasks')
      .update({'allocation_review_note': null})
      .eq('id', taskId);
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/data/repositories/workforce_planning_repository.dart`
Expected: No issues (other than pre-existing ones in the baseline).

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/workforce_planning_repository.dart
git commit -m "feat(wp): repo role moves + review note; stop mirroring assignments"
```

---

### Task 5: Simplified task form

**Files:**
- Rewrite: `lib/features/workforce_planning/tabs/task_form_dialog.dart`
- Rewrite: `test/features/workforce_planning/task_form_dialog_test.dart`
- Modify: callers `lib/features/workforce_planning/role/responsibilities_pane.dart` (two `TaskFormDialog(` sites) — drop the `employees:` and `nodes:`→ keep; pass `initialRoleId: widget.cardId` on create.

**Interfaces:**
- Consumes: `frequency.dart` (Task 3), `WpTask`, `WpDriver`, `WpNode`, `RoleScorecard`, `findSimilarAccountabilities`/`SimilarNameWarning` (existing `duplicate_check.dart`/`duplicate_warning.dart`).
- Produces:
  - `String? validateTaskForm({required String name, required String? roleId, required TaskFrequency frequency, String? minutesText, String? customHoursText, String? driverId})`
  - `WpTask buildTaskFromForm({WpTask? existing, required String companyId, required String name, required String roleId, String? responsibilityArea, required TaskFrequency frequency, String? minutesText, String? customHoursText, String? driverId, More more = const More()})`
  - `class More { String? nodeId, brandScope, skillTier, risk, capability, criticality, notes; bool isEssential; bool isExpectation; }` — the collapsed fields; `More.of(WpTask?)` copies them from an existing task.
  - `TaskFormDialog({WpTask? existing, required String companyId, required List<RoleScorecard> cards, List<WpNode> nodes = const [], List<WpDriver> drivers = const [], String? initialRoleId, List<WpTask> duplicateCheckPool = const [], Map<String, int> holderCountByRole = const {}})` — pops a `WpTask` on Save.

- [ ] **Step 1: Write the failing tests** (replace the file's contents)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/frequency.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/task_form_dialog.dart';

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

void main() {
  group('validateTaskForm', () {
    test('requires name, role and a duration', () {
      expect(validateTaskForm(name: '', roleId: 'r', frequency: TaskFrequency.daily, minutesText: '5'), 'Name is required.');
      expect(validateTaskForm(name: 'x', roleId: null, frequency: TaskFrequency.daily, minutesText: '5'), 'Pick the role that does this.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.daily, minutesText: ''), 'How long does it take each time?');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.custom, customHoursText: ''), 'Enter hours per month.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.perOrder, minutesText: '3'), 'Pick what the orders are counted from.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.weekly, minutesText: '30'), isNull);
    });
  });

  group('buildTaskFromForm', () {
    test('a preset writes cadence token + times + minutes, no direct hours', () {
      final t = buildTaskFromForm(companyId: 'c', name: ' Pack ', roleId: 'bh', frequency: TaskFrequency.daily, minutesText: '60');
      expect(t.name, 'Pack');
      expect(t.cadence, 'DAILY');
      expect(t.timesSource, 'manual');
      expect(t.timesManual, 26);
      expect(t.minutesManual, 60);
      expect(t.hoursPerMonth, isNull);
      expect(t.roleScorecardId, 'bh');
    });

    test('per order writes a driver, not manual times', () {
      final t = buildTaskFromForm(companyId: 'c', name: 'Pick', roleId: 'bh', frequency: TaskFrequency.perOrder, minutesText: '3', driverId: 'orders');
      expect(t.cadence, 'PER_ORDER');
      expect(t.timesSource, 'driver');
      expect(t.driverId, 'orders');
      expect(t.timesManual, isNull);
    });

    test('custom writes direct hours', () {
      final t = buildTaskFromForm(companyId: 'c', name: 'X', roleId: 'bh', frequency: TaskFrequency.custom, customHoursText: '7.5');
      expect(t.hoursPerMonth, 7.5);
      expect(t.cadence, isNull);
    });

    test('editing preserves id, owner, externalRef, sort, More fields', () {
      const existing = WpTask(id: 't1', companyId: 'c', name: 'Old', roleScorecardId: 'bh',
          ownerEmployeeId: 'e1', externalRef: 'X-1', areaSort: 2, taskSort: 5,
          skillTier: 'Managerial', risk: 'High', criticality: 'CRITICAL', notes: 'n');
      final t = buildTaskFromForm(existing: existing, companyId: 'c', name: 'New', roleId: 'om',
          frequency: TaskFrequency.monthly, minutesText: '120', more: More.of(existing));
      expect(t.id, 't1');
      expect(t.ownerEmployeeId, 'e1');
      expect(t.externalRef, 'X-1');
      expect((t.areaSort, t.taskSort), (2, 5));
      expect((t.skillTier, t.risk, t.criticality, t.notes), ('Managerial', 'High', 'CRITICAL', 'n'));
      expect(t.roleScorecardId, 'om');
    });

    test('Review Focus 4: a legacy manual task saved without edits keeps its hours', () {
      const legacy = WpTask(id: 't', companyId: 'c', name: 'L', roleScorecardId: 'bh',
          cadence: 'every other day', timesManual: 13, minutesManual: 30);
      final f = frequencyOf(legacy);
      final t = buildTaskFromForm(existing: legacy, companyId: 'c', name: 'L', roleId: 'bh',
          frequency: f, customHoursText: customHoursOf(legacy)!.toString(), more: More.of(legacy));
      expect(f, TaskFrequency.custom);
      expect(t.hoursPerMonth, closeTo(6.5, 1e-9));
    });
  });

  testWidgets('shows only the essentials until More details is opened', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<WpTask>(context: context, builder: (_) => TaskFormDialog(
        companyId: 'c', cards: [role('bh', 'Brand Handler')], initialRoleId: 'bh',
        holderCountByRole: const {'bh': 2})),
      child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('How often'), findsOneWidget);
    expect(find.text('Minutes each time'), findsOneWidget);
    expect(find.text('Role that does it'), findsOneWidget);
    expect(find.text('Skill tier'), findsNothing);
    expect(find.text('Owner'), findsNothing);

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Minutes each time'), '60');
    await tester.pump();
    expect(find.textContaining('≈ 26.0 h/mo'), findsOneWidget);
    expect(find.textContaining('split across 2 people'), findsOneWidget);

    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(find.text('Skill tier'), findsOneWidget);
  });
}
```


- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart`
Expected: FAIL — new signatures don't exist.

- [ ] **Step 3: Rewrite `task_form_dialog.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../duplicate_check.dart';
import '../duplicate_warning.dart';
import '../frequency.dart';

const _tiers = ['Transactional', 'Operational', 'Managerial', 'Strategic'];
const _risks = ['Low', 'Medium', 'High'];
const _criticalities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];

String? _present(String? id, Iterable<String> ids) =>
    (id != null && ids.contains(id)) ? id : null;

double? _num(String? s) => double.tryParse((s ?? '').trim());

/// The collapsed "More details" fields. None of them affects load.
class More {
  final String? nodeId, brandScope, skillTier, risk, capability, criticality, notes;
  final bool isEssential, isExpectation;
  const More({
    this.nodeId, this.brandScope, this.skillTier, this.risk, this.capability,
    this.criticality, this.notes, this.isEssential = true, this.isExpectation = false,
  });
  factory More.of(WpTask? t) => t == null
      ? const More()
      : More(
          nodeId: t.nodeId, brandScope: t.brandScope, skillTier: t.skillTier,
          risk: t.risk, capability: t.capability, criticality: t.criticality,
          notes: t.notes, isEssential: t.isEssential, isExpectation: t.isExpectation,
        );
}

String? validateTaskForm({
  required String name,
  required String? roleId,
  required TaskFrequency frequency,
  String? minutesText,
  String? customHoursText,
  String? driverId,
}) {
  if (name.trim().isEmpty) return 'Name is required.';
  if (roleId == null) return 'Pick the role that does this.';
  if (frequency == TaskFrequency.custom) {
    return _num(customHoursText) == null ? 'Enter hours per month.' : null;
  }
  if (_num(minutesText) == null) return 'How long does it take each time?';
  if (frequency == TaskFrequency.perOrder && (driverId == null || driverId.isEmpty)) {
    return 'Pick what the orders are counted from.';
  }
  return null;
}

WpTask buildTaskFromForm({
  WpTask? existing,
  required String companyId,
  required String name,
  required String roleId,
  String? responsibilityArea,
  required TaskFrequency frequency,
  String? minutesText,
  String? customHoursText,
  String? driverId,
  More more = const More(),
}) {
  final custom = frequency == TaskFrequency.custom;
  final perOrder = frequency == TaskFrequency.perOrder;
  String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
  return WpTask(
    id: existing?.id ?? '',
    companyId: existing?.companyId ?? companyId,
    name: name.trim(),
    roleScorecardId: roleId,
    responsibilityArea: clean(responsibilityArea ?? existing?.responsibilityArea),
    cadence: custom ? null : frequency.token,
    timesSource: perOrder ? 'driver' : 'manual',
    timesManual: (custom || perOrder) ? null : frequency.timesPerMonth,
    driverId: perOrder ? driverId : null,
    driverFactor: existing?.driverFactor ?? 1,
    minutesSource: 'manual',
    minutesManual: custom ? null : _num(minutesText),
    hoursPerMonth: custom ? _num(customHoursText) : null,
    nodeId: more.nodeId,
    brandScope: clean(more.brandScope),
    skillTier: more.skillTier,
    risk: more.risk,
    capability: clean(more.capability),
    criticality: more.criticality,
    notes: clean(more.notes),
    isEssential: more.isEssential,
    isExpectation: more.isExpectation,
    // Kept, not edited here: the DB still carries them for rollback.
    ownerEmployeeId: existing?.ownerEmployeeId,
    externalRef: existing?.externalRef,
    areaSort: existing?.areaSort ?? 0,
    taskSort: existing?.taskSort ?? 0,
    status: existing?.status ?? 'ACTIVE',
  );
}

/// Add/edit a task: name, how often x how long, and the one role that does
/// it. Everything else sits under "More details" because none of it changes
/// anyone's load.
class TaskFormDialog extends StatefulWidget {
  final WpTask? existing;
  final String companyId;
  final List<RoleScorecard> cards;
  final List<WpNode> nodes;
  final List<WpDriver> drivers;
  final String? initialRoleId;
  final List<WpTask> duplicateCheckPool;

  /// Role id -> active holders, for the "split across N people" line.
  final Map<String, int> holderCountByRole;

  const TaskFormDialog({
    super.key,
    this.existing,
    required this.companyId,
    required this.cards,
    this.nodes = const [],
    this.drivers = const [],
    this.initialRoleId,
    this.duplicateCheckPool = const [],
    this.holderCountByRole = const {},
  });

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late TaskFrequency _frequency = widget.existing == null
      ? TaskFrequency.weekly
      : frequencyOf(widget.existing!);
  late final _minutes = TextEditingController(
    text: widget.existing == null ? '' : (minutesOf(widget.existing!)?.toString() ?? ''),
  );
  late final _customHours = TextEditingController(
    text: widget.existing == null ? '' : (customHoursOf(widget.existing!)?.toString() ?? ''),
  );
  late String? _roleId = widget.existing?.roleScorecardId ?? widget.initialRoleId;
  late String? _driverId = widget.existing?.driverId ??
      widget.drivers.where((d) => d.name.toLowerCase().contains('order')).firstOrNull?.id;

  // "More details" — one field per state variable so "— None —" can clear it.
  late final More _initial = More.of(widget.existing);
  late String? _nodeId = _initial.nodeId;
  late String? _tier = _initial.skillTier;
  late String? _risk = _initial.risk;
  late String? _criticality = _initial.criticality;
  late bool _essential = _initial.isEssential;
  late final _brand = TextEditingController(text: _initial.brandScope ?? '');
  late final _capability = TextEditingController(text: _initial.capability ?? '');
  late final _notes = TextEditingController(text: _initial.notes ?? '');

  bool _showMore = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _minutes, _customHours, _brand, _capability, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) =>
      InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder());

  double get _driverVolume {
    for (final d in widget.drivers) {
      if (d.id == _driverId) return d.value;
    }
    return 0;
  }

  String _previewLine() {
    final h = previewHoursPerMonth(
      frequency: _frequency,
      minutes: _num(_minutes.text),
      customHours: _num(_customHours.text),
      driverVolume: _driverVolume,
      driverFactor: widget.existing?.driverFactor ?? 1,
    );
    final n = _roleId == null ? 0 : (widget.holderCountByRole[_roleId] ?? 0);
    final who = _roleId == null
        ? ''
        : n == 0
            ? ' · nobody holds this role yet'
            : ' · split across $n ${n == 1 ? 'person' : 'people'}';
    return '≈ ${h.toStringAsFixed(1)} h/mo$who';
  }

  void _save() {
    final err = validateTaskForm(
      name: _name.text, roleId: _roleId, frequency: _frequency,
      minutesText: _minutes.text, customHoursText: _customHours.text, driverId: _driverId,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final more = More(
      nodeId: _nodeId, brandScope: _brand.text, skillTier: _tier, risk: _risk,
      capability: _capability.text, criticality: _criticality, notes: _notes.text,
      isEssential: _initial.isExpectation ? false : _essential,
      isExpectation: _initial.isExpectation,
    );
    Navigator.pop(context, buildTaskFromForm(
      existing: widget.existing, companyId: widget.companyId, name: _name.text,
      roleId: _roleId!, frequency: _frequency, minutesText: _minutes.text,
      customHoursText: _customHours.text, driverId: _driverId, more: more,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final roleIds = widget.cards.map((c) => c.id);
    final custom = _frequency == TaskFrequency.custom;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New task' : 'Edit task'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _name, decoration: _dec('Name'), onChanged: (_) => setState(() {})),
              if (widget.duplicateCheckPool.isNotEmpty)
                SimilarNameWarning(
                  matches: findSimilarAccountabilities(
                    typed: _name.text,
                    all: widget.duplicateCheckPool,
                    excludeId: widget.existing?.id,
                  ),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<TaskFrequency>(
                    initialValue: _frequency,
                    decoration: _dec('How often'),
                    items: [for (final f in TaskFrequency.values) DropdownMenuItem(value: f, child: Text(f.label))],
                    onChanged: (f) => setState(() => _frequency = f ?? _frequency),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: custom
                      ? TextFormField(controller: _customHours, decoration: _dec('Hours / month', hint: 'e.g. 10'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))
                      : TextFormField(controller: _minutes, decoration: _dec('Minutes each time', hint: 'e.g. 15'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
                ),
              ]),
              if (_frequency == TaskFrequency.perOrder) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _present(_driverId, widget.drivers.map((d) => d.id)),
                  decoration: _dec('Orders counted from'),
                  items: [for (final d in widget.drivers) DropdownMenuItem(value: d.id, child: Text('${d.name} (${d.value.toStringAsFixed(0)}/mo)'))],
                  onChanged: (v) => setState(() => _driverId = v),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _present(_roleId, roleIds),
                decoration: _dec('Role that does it'),
                items: [for (final c in widget.cards) DropdownMenuItem(value: c.id, child: Text(c.jobTitle))],
                onChanged: (v) => setState(() => _roleId = v),
              ),
              const SizedBox(height: 8),
              Text(_previewLine(), style: AppTheme.mono(context)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showMore = !_showMore),
                  icon: Icon(_showMore ? Icons.expand_less : Icons.expand_more),
                  label: const Text('More details'),
                ),
              ),
              if (_showMore) ..._moreFields(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _pick(String label, String? value, List<String> options, void Function(String?) set) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<String?>(
          initialValue: _present(value, options),
          decoration: _dec(label),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => setState(() => set(v)),
        ),
      );

  Widget _text(TextEditingController c, String label, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(controller: c, decoration: _dec(label), maxLines: maxLines),
  );

  List<Widget> _moreFields() => [
    _text(_notes, 'Notes', maxLines: 2),
    _pick('Criticality', _criticality, _criticalities, (v) => _criticality = v),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Essential function'),
      value: _initial.isExpectation ? false : _essential,
      onChanged: _initial.isExpectation ? null : (v) => setState(() => _essential = v),
    ),
    _pick('Skill tier', _tier, _tiers, (v) => _tier = v),
    _pick('Risk', _risk, _risks, (v) => _risk = v),
    _text(_capability, 'Capability requirement'),
    _text(_brand, 'Brand / scope'),
    if (widget.nodes.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<String?>(
          initialValue: _present(_nodeId, widget.nodes.map((n) => n.id)),
          decoration: _dec('Value-chain node'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
            for (final n in widget.nodes) DropdownMenuItem(value: n.id, child: Text(n.name)),
          ],
          onChanged: (v) => setState(() => _nodeId = v),
        ),
      ),
  ];
}
```

- [ ] **Step 4: Update callers.** In `responsibilities_pane.dart` both `TaskFormDialog(` calls: remove `employees:` and `rates:`; add `initialRoleId: widget.cardId` on the create call; keep `cards:`, `nodes:`, `drivers:`, `duplicateCheckPool:`. `responsibilities_tab.dart` is deleted in Task 9 — if it breaks analyze now, fix its call the same way (drop `employees:`/`rates:`) so the tree builds.

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart && flutter analyze lib/features/workforce_planning`
Expected: PASS; analyze no new issues. Remaining `responsibilities_tab_test.dart` failures that construct the old dialog are expected and are deleted in Task 9 — note them, don't fix them.

- [ ] **Step 6: Commit**

```bash
git add lib/features/workforce_planning/tabs/task_form_dialog.dart lib/features/workforce_planning/role/responsibilities_pane.dart lib/features/workforce_planning/tabs/responsibilities_tab.dart test/features/workforce_planning/task_form_dialog_test.dart
git commit -m "feat(wp): 3-input task form (how often x how long, one role)"
```

---

### Task 6: Board sections — people strip, No role yet, Check these

**Files:**
- Create: `lib/features/workforce_planning/board/board_sections.dart`
- Test: `test/features/workforce_planning/board_sections_test.dart`

**Interfaces:**
- Consumes: `RoleLoad`, `Employee`, `WpTask`, `RoleScorecard` (Task 2), `effortLabel` (Task 3 `frequency.dart`).
- Produces:
  - `PeopleLoadStrip({required List<RoleLoad> loads, required List<Employee> employees})` — chip per ACTIVE employee `"<First> NN%"`, sorted by load desc; employees with no role show `"<First> no role"` last.
  - `NoRoleSection({required List<WpTask> tasks, required Map<String,double> hoursById, required void Function(WpTask) onOpenTask})` — hidden when empty; header `"No role yet (N)"`; each task is a `Draggable<String>` with key `ValueKey('task-<id>')`.
  - `FlaggedSection({required List<WpTask> tasks, required Map<String, RoleScorecard> rolesById, required Future<void> Function(WpTask) onLooksRight, required void Function(WpTask) onOpenTask})` — hidden when empty; header `"Check these (N)"`; row = name, `now: <role title or 'no role'>`, the note, a `Looks right` button.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/board/board_sections.dart';

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  testWidgets('No role section: hidden when empty, counts and lists tasks', (tester) async {
    await tester.pumpWidget(wrap(NoRoleSection(tasks: const [], hoursById: const {}, onOpenTask: (_) {})));
    expect(find.textContaining('No role yet'), findsNothing);

    await tester.pumpWidget(wrap(NoRoleSection(
      tasks: const [WpTask(id: 'a', companyId: 'c', name: 'Orphan work')],
      hoursById: const {'a': 12}, onOpenTask: (_) {})));
    expect(find.text('No role yet (1)'), findsOneWidget);
    expect(find.text('Orphan work'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-a')), findsOneWidget);
  });

  testWidgets('Check these: shows was-note and current role; Looks right calls back', (tester) async {
    WpTask? confirmed;
    await tester.pumpWidget(wrap(FlaggedSection(
      tasks: const [WpTask(id: 'a', companyId: 'c', name: 'Split task', roleScorecardId: 'om',
          allocationReviewNote: 'was: Jeremy 60%, Brand Handler 40%')],
      rolesById: {'om': role('om', 'Ops Manager')},
      onLooksRight: (t) async => confirmed = t,
      onOpenTask: (_) {})));
    expect(find.text('Check these (1)'), findsOneWidget);
    expect(find.textContaining('now: Ops Manager'), findsOneWidget);
    expect(find.textContaining('was: Jeremy 60%'), findsOneWidget);
    await tester.tap(find.text('Looks right'));
    await tester.pump();
    expect(confirmed?.id, 'a');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/board_sections_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Write `board_sections.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../role_load.dart';
import '../tabs/load_chip.dart';
import '../frequency.dart' show effortLabel;

/// Everyone's load at a glance, busiest first. A person's load is their
/// role's load (capacity-weighted split), so this is read off [loads].
class PeopleLoadStrip extends StatelessWidget {
  final List<RoleLoad> loads;
  final List<Employee> employees;
  const PeopleLoadStrip({super.key, required this.loads, required this.employees});

  @override
  Widget build(BuildContext context) {
    final byRole = {for (final l in loads) l.role.id: l};
    final rows = [
      for (final e in employees)
        if (e.employmentStatus == 'ACTIVE' && e.deletedAt == null)
          (e: e, load: e.roleScorecardId == null ? null : byRole[e.roleScorecardId]),
    ]..sort((a, b) => (b.load?.load ?? -1).compareTo(a.load?.load ?? -1));
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final r in rows)
        Chip(
          avatar: r.load == null ? null : LoadStatusChip(status: r.load!.status),
          label: Text(r.load == null
              ? '${r.e.firstName} no role'
              : '${r.e.firstName} ${(r.load!.load * 100).round()}%'),
        ),
    ]);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    margin: const EdgeInsets.only(bottom: 12),
    child: ExpansionTile(
      initiallyExpanded: true,
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: children,
    ),
  );
}

/// Genuine work that reaches nobody. Drag a row onto a role card.
class NoRoleSection extends StatelessWidget {
  final List<WpTask> tasks;
  final Map<String, double> hoursById;
  final void Function(WpTask) onOpenTask;
  const NoRoleSection({super.key, required this.tasks, required this.hoursById, required this.onOpenTask});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return _Section(title: 'No role yet (${tasks.length})', children: [
      for (final t in tasks)
        Draggable<String>(
          key: ValueKey('task-${t.id}'),
          data: t.id,
          feedback: Material(elevation: 4, child: Padding(padding: const EdgeInsets.all(8), child: Text(t.name))),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.drag_indicator, size: 16),
            title: Text(t.name),
            trailing: Text(effortLabel(t, hoursById[t.id] ?? 0)),
            onTap: () => onOpenTask(t),
          ),
        ),
    ]);
  }
}

/// Tasks the role-first migration could not convert without losing detail.
class FlaggedSection extends StatelessWidget {
  final List<WpTask> tasks;
  final Map<String, RoleScorecard> rolesById;
  final Future<void> Function(WpTask) onLooksRight;
  final void Function(WpTask) onOpenTask;
  const FlaggedSection({super.key, required this.tasks, required this.rolesById, required this.onLooksRight, required this.onOpenTask});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return _Section(title: 'Check these (${tasks.length})', children: [
      for (final t in tasks)
        ListTile(
          dense: true,
          title: Text(t.name),
          subtitle: Text(
            'now: ${rolesById[t.roleScorecardId]?.jobTitle ?? 'no role'} · ${t.allocationReviewNote}',
          ),
          onTap: () => onOpenTask(t),
          trailing: TextButton(onPressed: () => onLooksRight(t), child: const Text('Looks right')),
        ),
    ]);
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/workforce_planning/board_sections_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/board/board_sections.dart test/features/workforce_planning/board_sections_test.dart
git commit -m "feat(wp): board sections — people strip, no-role pool, check-these list"
```

---

### Task 7: Role board — cards, drag drafts, Apply

**Files:**
- Create: `lib/features/workforce_planning/board/role_load_card.dart`
- Create: `lib/features/workforce_planning/tabs/roles_board_tab.dart`
- Test: `test/features/workforce_planning/roles_board_tab_test.dart`

**Interfaces:**
- Consumes: `buildRoleLoads`, `RoleLoad`, `RoleMoves`, `taskHours`, `checkedByTitles`, `noRoleTasks`, `flaggedTasks` (Task 2); `effortLabel` (Task 3); `PeopleLoadStrip`, `NoRoleSection`, `FlaggedSection` (Task 6); `WorkforcePlanningRepository.moveTasksToRoles`, `.saveTask` (Task 4); `TaskFormDialog` (Task 5); providers `wpActiveEmployeesProvider`, `wpTasksProvider`, `wpAllTaskComputedProvider`, `wpPersonLoadsProvider`, `wpConfigProvider`, `wpGrowthMultiplierProvider`, `wpDriversProvider`, `wpNodesProvider`, `roleScorecardListProvider`.
- Produces:
  - `class RoleLoadCard extends StatelessWidget { RoleLoad current; RoleLoad planned; List<WpTask> tasks; List<String> checkedBy; bool highlighted; Map<String,double> taskHoursById; void Function(String taskId) onDropTask; void Function(String? taskId) onHoverTask; VoidCallback onAddTask; VoidCallback onAddHolder; VoidCallback onOpenRole; void Function(WpTask) onOpenTask; }`
  - `class RolesBoardTab extends ConsumerStatefulWidget` — test hook: `const RolesBoardTab({super.key})`.
  - Draggable payload type: `String` (task id). Widget keys: `ValueKey('role-card-<roleId>')`, `ValueKey('task-<taskId>')`.

- [ ] **Step 1: Write the failing widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/roles_board_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final applied = <Map<String, String>>[];
  final cleared = <String>[];
  @override
  Future<List<String>> moveTasksToRoles(Map<String, String> moves) async {
    applied.add({...moves});
    return const [];
  }
  @override
  Future<void> clearReviewNote(String taskId) async => cleared.add(taskId);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Employee emp(String id, String first, {String? role, String? reportsTo}) => Employee(
  id: id, companyId: 'c', employeeNumber: id, firstName: first, lastName: 'X',
  roleScorecardId: role, reportsToId: reportsTo,
  employmentType: 'FULL_TIME', employmentStatus: 'ACTIVE',
  hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
  isNdEligible: false, isHolidayPayEligible: false,
  sssEligibilityOverride: false, philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false, taxOnFullEarnings: false,
);

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

Widget host(_FakeRepo repo, {List<WpTask>? tasks}) => ProviderScope(
  overrides: [
    wpActiveEmployeesProvider.overrideWith((ref) async => [
      emp('ana', 'Ana', role: 'bh', reportsTo: 'jer'),
      emp('ben', 'Ben', role: 'bh', reportsTo: 'jer'),
      emp('jer', 'Jeremy', role: 'om'),
    ]),
    roleScorecardListProvider.overrideWith((ref) async => [role('bh', 'Brand Handler'), role('om', 'Ops Manager')]),
    wpTasksProvider.overrideWith((ref) async => tasks ?? const [
      WpTask(id: 't1', companyId: 'c', name: 'Pack orders', roleScorecardId: 'bh'),
      WpTask(id: 't2', companyId: 'c', name: 'Weekly report', roleScorecardId: 'om'),
    ]),
    wpAllTaskComputedProvider.overrideWith((ref) async => const [
      WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 160),
      WpTaskComputed(taskId: 't2', companyId: 'c', hoursPerMonthBase: 176),
    ]),
    wpPersonLoadsProvider.overrideWith((ref) async => [
      for (final id in ['ana', 'ben', 'jer']) WpPersonLoad(employeeId: id, companyId: 'c', capacityHours: 160),
    ]),
    wpConfigProvider.overrideWith((ref) async => null),
    wpDriversProvider.overrideWith((ref) async => const []),
    wpNodesProvider.overrideWith((ref) async => const []),
    workforcePlanningRepositoryProvider.overrideWithValue(repo),
  ],
  child: const MaterialApp(home: Scaffold(body: RolesBoardTab())),
);

Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
  final g = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 100));
  await g.moveTo(tester.getCenter(to));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('over-loaded role first, with needs/short and checked-by', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(host(_FakeRepo()));
    await tester.pumpAndSettle();

    final om = tester.getTopLeft(find.byKey(const ValueKey('role-card-om')));
    final bh = tester.getTopLeft(find.byKey(const ValueKey('role-card-bh')));
    expect(om.dy < bh.dy, isTrue, reason: 'Ops Manager 110% sorts above Brand Handler 50%');
    expect(find.textContaining('Needs 1.1 people'), findsOneWidget);
    expect(find.textContaining('short 0.1'), findsOneWidget);
    expect(find.textContaining('checked by Ops Manager'), findsOneWidget);
  });

  testWidgets('drag a task to another role -> draft with before/after, Apply writes it', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    final repo = _FakeRepo();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    await drag(tester, find.byKey(const ValueKey('task-t2')), find.byKey(const ValueKey('role-card-bh')));
    expect(find.text('1 unsaved move'), findsOneWidget);
    expect(find.textContaining('50% → 105%'), findsOneWidget, reason: 'Brand Handler 160h → 336h of 320h');

    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();
    expect(repo.applied, [{'t2': 'bh'}]);
  });

  testWidgets('Review Focus 3: dropping on its own role records nothing; dragging back removes the draft', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(host(_FakeRepo()));
    await tester.pumpAndSettle();

    await drag(tester, find.byKey(const ValueKey('task-t1')), find.byKey(const ValueKey('role-card-bh')));
    expect(find.textContaining('unsaved'), findsNothing);

    await drag(tester, find.byKey(const ValueKey('task-t1')), find.byKey(const ValueKey('role-card-om')));
    expect(find.text('1 unsaved move'), findsOneWidget);
    await drag(tester, find.byKey(const ValueKey('task-t1')), find.byKey(const ValueKey('role-card-bh')));
    expect(find.textContaining('unsaved'), findsNothing);
  });

  testWidgets('Reset discards drafts without writing', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    final repo = _FakeRepo();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await drag(tester, find.byKey(const ValueKey('task-t2')), find.byKey(const ValueKey('role-card-bh')));
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unsaved'), findsNothing);
    expect(repo.applied, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/roles_board_tab_test.dart`
Expected: FAIL — `roles_board_tab.dart` not found.

- [ ] **Step 3: Write `board/role_load_card.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/workforce_planning.dart';
import '../capacity_math.dart';
import '../../../app/theme.dart';
import '../frequency.dart' show effortLabel;
import '../role_load.dart';
import '../tabs/load_chip.dart';

String _pct(double f) => '${(f * 100).round()}%';
String _h(double v) => '${v.toStringAsFixed(v >= 10 ? 0 : 1)}h';

/// One role on the board: headcount headline, holders, tasks. Also the drop
/// target for moving a task into this role.
class RoleLoadCard extends StatelessWidget {
  final RoleLoad current;

  /// Figures under drafts + the in-flight hover (numbers only).
  final RoleLoad planned;

  /// The rows to render: drafts only, never the hover — re-parenting the
  /// Draggable under the pointer mid-drag would cancel the drag.
  final List<WpTask> tasks;
  final List<String> checkedBy;
  final bool highlighted;
  final Map<String, double> taskHoursById;
  final void Function(String taskId) onDropTask;
  final void Function(String? taskId) onHoverTask;
  final VoidCallback onAddTask;
  final VoidCallback onAddHolder;
  final VoidCallback onOpenRole;
  final void Function(WpTask task) onOpenTask;

  const RoleLoadCard({
    super.key,
    required this.current,
    required this.planned,
    required this.tasks,
    required this.checkedBy,
    required this.highlighted,
    required this.taskHoursById,
    required this.onDropTask,
    required this.onHoverTask,
    required this.onAddTask,
    required this.onAddHolder,
    required this.onOpenRole,
    required this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final changed = (planned.workHours - current.workHours).abs() > 0.001;
    final danger = planned.status == LoadStatus.over;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        onHoverTask(d.data);
        return true;
      },
      onLeave: (_) => onHoverTask(null),
      onAcceptWithDetails: (d) => onDropTask(d.data),
      builder: (context, candidates, _) => Card(
        key: ValueKey('role-card-${current.role.id}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: candidates.isNotEmpty || highlighted
                ? cs.primary
                : danger
                    ? StatusPalette.of(context, StatusTone.danger).foreground
                    : cs.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpenRole,
                    child: Text(current.role.jobTitle, style: text.titleMedium),
                  ),
                ),
                Text(
                  checkedBy.isEmpty ? 'checked by —' : 'checked by ${checkedBy.join(', ')}',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Work ${_h(planned.workHours)}/mo'),
                Text('Has ${planned.holders.length}'),
                Text('Needs ${planned.peopleNeeded.toStringAsFixed(1)} people'),
                if (planned.shortBy > 0.05)
                  StatusChip(label: 'short ${planned.shortBy.toStringAsFixed(1)}', tone: StatusTone.danger),
                if (changed)
                  Text('${_pct(current.load)} → ${_pct(planned.load)}',
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              if (planned.holders.isEmpty)
                Text('Nobody holds this role', style: TextStyle(color: cs.onSurfaceVariant))
              else
                Wrap(spacing: 12, runSpacing: 4, children: [
                  for (final h in planned.holders)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(h.employee.firstName),
                      const SizedBox(width: 4),
                      Text(_pct(planned.load)),
                      const SizedBox(width: 4),
                      LoadStatusChip(status: planned.status),
                    ]),
                ]),
              const Divider(height: 24),
              for (final t in tasks)
                Draggable<String>(
                  key: ValueKey('task-${t.id}'),
                  data: t.id,
                  feedback: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(padding: const EdgeInsets.all(8), child: Text(t.name)),
                  ),
                  childWhenDragging: Opacity(opacity: 0.4, child: _taskRow(context, t)),
                  child: _taskRow(context, t),
                ),
              Row(children: [
                TextButton.icon(onPressed: onAddTask, icon: const Icon(Icons.add), label: const Text('Add task')),
                TextButton.icon(onPressed: onAddHolder, icon: const Icon(Icons.person_add_alt), label: const Text('Add holder')),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskRow(BuildContext context, WpTask t) {
    final hours = taskHoursById[t.id] ?? 0;
    final moved = t.roleScorecardId != current.role.id;
    return InkWell(
      onTap: () => onOpenTask(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          const Icon(Icons.drag_indicator, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(t.name,
                style: moved ? TextStyle(color: Theme.of(context).colorScheme.primary) : null),
          ),
          Text(effortLabel(t, hours)),
          const SizedBox(width: 12),
          SizedBox(width: 56, child: Text('≈ ${_h(hours)}', textAlign: TextAlign.right)),
        ]),
      ),
    );
  }
}
```

Give the `%`, hours and `Needs` texts `style: AppTheme.mono(context)` (merge with the colour styles where both apply).

- [ ] **Step 4: Write `tabs/roles_board_tab.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../board/board_sections.dart';
import '../board/role_load_card.dart';
import '../role_load.dart';
import '../wp_providers.dart';
import 'needs_attention_strip.dart';
import 'task_form_dialog.dart';

/// The Workforce Planning front door: every role with its people and its
/// work. Drag a task onto another role to plan a move; nothing is written
/// until Apply.
class RolesBoardTab extends ConsumerStatefulWidget {
  const RolesBoardTab({super.key});

  @override
  ConsumerState<RolesBoardTab> createState() => _RolesBoardTabState();
}

class _RolesBoardTabState extends ConsumerState<RolesBoardTab> {
  final RoleMoves _moves = {};
  ({String taskId, String roleId})? _hover;
  bool _applying = false;

  void _invalidate() {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(roleScorecardListProvider);
  }

  /// Records a move, or removes it when the task lands back on its own role.
  void _drop(WpTask task, String roleId) => setState(() {
    _hover = null;
    if (task.roleScorecardId == roleId) {
      _moves.remove(task.id);
    } else {
      _moves[task.id] = roleId;
    }
  });

  Future<void> _apply() async {
    setState(() => _applying = true);
    final failed = await ref.read(workforcePlanningRepositoryProvider).moveTasksToRoles({..._moves});
    if (!mounted) return;
    setState(() {
      _moves.removeWhere((id, _) => !failed.contains(id));
      _applying = false;
    });
    _invalidate();
    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${failed.length} move(s) could not be saved and are still drafts.')),
      );
    }
  }

  Future<void> _openTask({WpTask? existing, String? roleId, required _BoardData d}) async {
    final saved = await showDialog<WpTask>(
      context: context,
      builder: (_) => TaskFormDialog(
        existing: existing,
        companyId: d.companyId,
        cards: d.roles,
        nodes: d.nodes,
        drivers: d.drivers,
        initialRoleId: roleId,
        duplicateCheckPool: d.tasks,
        holderCountByRole: {for (final r in d.current) r.role.id: r.holders.length},
      ),
    );
    if (saved == null) return;
    await ref.read(workforcePlanningRepositoryProvider).saveTask(saved);
    _invalidate();
  }

  Future<void> _addHolder(RoleScorecard role, List<Employee> employees) async {
    final picked = await showDialog<Employee>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Who should hold ${role.jobTitle}?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Changing someone\'s role can change their pay, so it is done from '
              'their profile with Compensation & role change.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
          for (final e in employees.where((e) => e.roleScorecardId != role.id))
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e), child: Text(e.fullName)),
        ],
      ),
    );
    if (picked != null && mounted) context.push('/employees/${picked.id}');
  }

  @override
  Widget build(BuildContext context) {
    final async = _BoardData.watch(ref);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (d) => _board(context, d),
    );
  }

  Widget _board(BuildContext context, _BoardData d) {
    // Order and task rows follow the committed drafts only; the hover changes
    // numbers, never layout, so nothing moves under the pointer mid-drag.
    final withDrafts = d.loads(_moves);
    final preview = {..._moves, if (_hover != null) _hover!.taskId: _hover!.roleId};
    final plannedById = {for (final r in d.loads(preview)) r.role.id: r};
    final currentById = {for (final r in d.current) r.role.id: r};
    final rolesById = {for (final r in d.roles) r.id: r};
    final tasksById = {for (final t in d.tasks) t.id: t};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NeedsAttentionStrip(),
        if (_moves.isNotEmpty) _planBar(context),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PeopleLoadStrip(loads: plannedById.values.toList(), employees: d.employees),
              const SizedBox(height: 16),
              NoRoleSection(
                tasks: noRoleTasks(d.tasks, moves: _moves),
                hoursById: d.hoursById,
                onOpenTask: (t) => _openTask(existing: t, d: d),
              ),
              FlaggedSection(
                tasks: flaggedTasks(d.tasks),
                rolesById: rolesById,
                onLooksRight: (t) async {
                  await ref.read(workforcePlanningRepositoryProvider).clearReviewNote(t.id);
                  _invalidate();
                },
                onOpenTask: (t) => _openTask(existing: t, d: d),
              ),
              for (final p in withDrafts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RoleLoadCard(
                    current: currentById[p.role.id]!,
                    planned: plannedById[p.role.id]!,
                    tasks: p.tasks,
                    checkedBy: checkedByTitles(role: p.role, employees: d.employees, rolesById: rolesById),
                    highlighted: _hover?.roleId == p.role.id,
                    taskHoursById: d.hoursById,
                    onHoverTask: (taskId) => setState(() {
                      _hover = taskId == null ? null : (taskId: taskId, roleId: p.role.id);
                    }),
                    onDropTask: (taskId) {
                      final t = tasksById[taskId];
                      if (t != null) _drop(t, p.role.id);
                    },
                    onAddTask: () => _openTask(roleId: p.role.id, d: d),
                    onAddHolder: () => _addHolder(p.role, d.employees),
                    onOpenRole: () => context.push('/workforce-planning/roles/${p.role.id}'),
                    onOpenTask: (t) => _openTask(existing: t, d: d),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planBar(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(child: Text('${_moves.length} unsaved ${_moves.length == 1 ? 'move' : 'moves'}')),
        TextButton(
          onPressed: _applying ? null : () => setState(() { _moves.clear(); _hover = null; }),
          child: const Text('Reset'),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _applying ? null : _apply, child: Text('Apply ${_moves.length}')),
      ]),
    ),
  );
}

/// Everything the board reads, loaded together.
class _BoardData {
  final String companyId;
  final List<RoleScorecard> roles;
  final List<Employee> employees;
  final List<WpTask> tasks;
  final List<WpNode> nodes;
  final List<WpDriver> drivers;
  final Map<String, double> hoursById;
  final Map<String, double> capacityById;
  final double defaultCapacity;
  late final List<RoleLoad> current = loads(const {});

  _BoardData({
    required this.companyId, required this.roles, required this.employees,
    required this.tasks, required this.nodes, required this.drivers,
    required this.hoursById, required this.capacityById, required this.defaultCapacity,
  });

  List<RoleLoad> loads(RoleMoves moves) => buildRoleLoads(
    roles: roles, employees: employees, tasks: tasks, hoursByTaskId: hoursById,
    capacityByEmployee: capacityById, defaultCapacity: defaultCapacity, moves: moves,
  );

  static AsyncValue<_BoardData> watch(WidgetRef ref) {
    final roles = ref.watch(roleScorecardListProvider);
    final emps = ref.watch(wpActiveEmployeesProvider);
    final tasks = ref.watch(wpTasksProvider);
    final computed = ref.watch(wpAllTaskComputedProvider);
    final loads = ref.watch(wpPersonLoadsProvider);
    final config = ref.watch(wpConfigProvider);
    final nodes = ref.watch(wpNodesProvider);
    final drivers = ref.watch(wpDriversProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);
    for (final a in [roles, emps, tasks, computed, loads, config]) {
      if (a.hasError) return AsyncValue.error(a.error!, a.stackTrace ?? StackTrace.empty);
      if (!a.hasValue) return const AsyncValue.loading();
    }
    final active = roles.requireValue.where((r) => r.isActive).toList();
    final e = emps.requireValue;
    return AsyncValue.data(_BoardData(
      companyId: e.isNotEmpty ? e.first.companyId : (active.isNotEmpty ? active.first.companyId : ''),
      roles: active,
      employees: e,
      tasks: tasks.requireValue,
      nodes: nodes.asData?.value ?? const [],
      drivers: drivers.asData?.value ?? const [],
      hoursById: {for (final c in computed.requireValue) c.taskId: taskHours(c, multiplier)},
      capacityById: {for (final l in loads.requireValue) l.employeeId: l.capacityHours},
      defaultCapacity: config.requireValue?.defaultCapacityHours ?? 160,
    ));
  }
}
```

The test host does not override the NeedsAttentionStrip's providers; the strip is self-contained and renders `SizedBox.shrink()` while loading/erroring (see its doc comment). If the test errors on it, override the missing providers in the test host rather than removing the strip.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/workforce_planning/roles_board_tab_test.dart`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/workforce_planning/board lib/features/workforce_planning/tabs/roles_board_tab.dart test/features/workforce_planning/roles_board_tab_test.dart
git commit -m "feat(wp): Role board — role cards, drag-to-role drafts, Apply"
```

---

### Task 8: All tasks tab

**Files:**
- Create: `lib/features/workforce_planning/tabs/all_tasks_tab.dart`
- Test: `test/features/workforce_planning/all_tasks_tab_test.dart`

**Interfaces:**
- Consumes: providers as in Task 7; `effortLabel` (Task 3); `checkedByTitles`, `taskHours`, `isLegacyReference` (Task 2); `TaskFormDialog` (Task 5); repo `saveTask`, `setTaskArchived`, `setTaskCard`.
- Produces: `const AllTasksTab({super.key})`; pure filter `List<WpTask> filterTasks(List<WpTask> tasks, {String query = '', AllTasksFilter filter = AllTasksFilter.all, String? roleId})` with `enum AllTasksFilter { all, noRole, flagged, role }`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/all_tasks_tab.dart';

void main() {
  const tasks = [
    WpTask(id: 'a', companyId: 'c', name: 'Pack Shopee orders', roleScorecardId: 'bh'),
    WpTask(id: 'b', companyId: 'c', name: 'Reply to chats'),
    WpTask(id: 'c', companyId: 'c', name: 'Legacy row', externalRef: 'X'),
    WpTask(id: 'd', companyId: 'c', name: 'Split thing', roleScorecardId: 'om', allocationReviewNote: 'was: x'),
    WpTask(id: 'e', companyId: 'c', name: 'Old', roleScorecardId: 'bh', status: 'ARCHIVED'),
  ];

  test('default hides archived and legacy reference rows', () {
    expect(filterTasks(tasks).map((t) => t.id), ['a', 'b', 'd']);
  });
  test('search is case-insensitive on name', () {
    expect(filterTasks(tasks, query: 'shopee').map((t) => t.id), ['a']);
  });
  test('no role / flagged / by role', () {
    expect(filterTasks(tasks, filter: AllTasksFilter.noRole).map((t) => t.id), ['b']);
    expect(filterTasks(tasks, filter: AllTasksFilter.flagged).map((t) => t.id), ['d']);
    expect(filterTasks(tasks, filter: AllTasksFilter.role, roleId: 'bh').map((t) => t.id), ['a']);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/all_tasks_tab_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Write `all_tasks_tab.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../frequency.dart' show effortLabel;
import '../role_load.dart';
import '../wp_providers.dart';
import 'task_form_dialog.dart';

enum AllTasksFilter { all, noRole, flagged, role }

List<WpTask> filterTasks(
  List<WpTask> tasks, {
  String query = '',
  AllTasksFilter filter = AllTasksFilter.all,
  String? roleId,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final t in tasks)
      if (t.status == 'ACTIVE' &&
          !isLegacyReference(t) &&
          (q.isEmpty || t.name.toLowerCase().contains(q)) &&
          switch (filter) {
            AllTasksFilter.all => true,
            AllTasksFilter.noRole => t.roleScorecardId == null,
            AllTasksFilter.flagged => t.allocationReviewNote != null,
            AllTasksFilter.role => t.roleScorecardId == roleId,
          })
        t,
  ];
}

/// Every task as one searchable list — for finding a task and bulk tidying.
class AllTasksTab extends ConsumerStatefulWidget {
  const AllTasksTab({super.key});

  @override
  ConsumerState<AllTasksTab> createState() => _AllTasksTabState();
}

class _AllTasksTabState extends ConsumerState<AllTasksTab> {
  String _query = '';
  AllTasksFilter _filter = AllTasksFilter.all;
  String? _roleId;

  void _invalidate() {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(roleScorecardListProvider);
  }

  Future<void> _edit(WpTask t, List<RoleScorecard> roles, List<WpTask> all) async {
    final saved = await showDialog<WpTask>(
      context: context,
      builder: (_) => TaskFormDialog(
        existing: t,
        companyId: t.companyId,
        cards: roles,
        nodes: ref.read(wpNodesProvider).asData?.value ?? const [],
        drivers: ref.read(wpDriversProvider).asData?.value ?? const [],
        duplicateCheckPool: all,
      ),
    );
    if (saved == null) return;
    await ref.read(workforcePlanningRepositoryProvider).saveTask(saved);
    _invalidate();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(wpTasksProvider);
    final roles = ref.watch(roleScorecardListProvider);
    final emps = ref.watch(wpActiveEmployeesProvider);
    final computed = ref.watch(wpAllTaskComputedProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);
    if ([tasks, roles, emps, computed].any((a) => a.isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = [tasks, roles, emps, computed].where((a) => a.hasError).firstOrNull;
    if (err != null) return Center(child: Text('Error: ${err.error}'));

    final allRoles = roles.requireValue;
    final rolesById = {for (final r in allRoles) r.id: r};
    final hours = {for (final c in computed.requireValue) c.taskId: taskHours(c, multiplier)};
    final rows = filterTasks(tasks.requireValue, query: _query, filter: _filter, roleId: _roleId);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 280,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tasks', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          DropdownButton<String>(
            value: _filter == AllTasksFilter.role ? 'role:$_roleId' : _filter.name,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All tasks')),
              const DropdownMenuItem(value: 'noRole', child: Text('No role')),
              const DropdownMenuItem(value: 'flagged', child: Text('Check these')),
              for (final r in allRoles.where((r) => r.isActive))
                DropdownMenuItem(value: 'role:${r.id}', child: Text(r.jobTitle)),
            ],
            onChanged: (v) => setState(() {
              if (v == null) return;
              if (v.startsWith('role:')) {
                _filter = AllTasksFilter.role;
                _roleId = v.substring(5);
              } else {
                _filter = AllTasksFilter.values.byName(v);
                _roleId = null;
              }
            }),
          ),
          Text('${rows.length} tasks'),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          child: ResponsiveTable(
            child: DataTable(
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('Task')),
                DataColumn(label: Text('How often')),
                DataColumn(label: Text('≈ h/mo'), numeric: true),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Checked by')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final t in rows)
                  DataRow(
                    onSelectChanged: (_) => _edit(t, allRoles, tasks.requireValue),
                    cells: [
                      DataCell(Text(t.name)),
                      DataCell(Text(effortLabel(t, hours[t.id] ?? 0))),
                      DataCell(Text((hours[t.id] ?? 0).toStringAsFixed(1))),
                      DataCell(Text(rolesById[t.roleScorecardId]?.jobTitle ?? '—')),
                      DataCell(Text(() {
                        final r = rolesById[t.roleScorecardId];
                        if (r == null) return '—';
                        final by = checkedByTitles(role: r, employees: emps.requireValue, rolesById: rolesById);
                        return by.isEmpty ? '—' : by.join(', ');
                      }())),
                      DataCell(IconButton(
                        tooltip: 'Archive',
                        icon: const Icon(Icons.archive_outlined),
                        onPressed: () async {
                          await ref.read(workforcePlanningRepositoryProvider).setTaskArchived(t.id, true);
                          _invalidate();
                        },
                      )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}
```

Confirm `ResponsiveTable`'s constructor (`lib/widgets/responsive_table.dart:18`) takes `child:` as used; adjust if it requires other named args.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/features/workforce_planning/all_tasks_tab_test.dart && flutter analyze lib/features/workforce_planning/tabs/all_tasks_tab.dart`
Expected: PASS; no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/tabs/all_tasks_tab.dart test/features/workforce_planning/all_tasks_tab_test.dart
git commit -m "feat(wp): All tasks tab — searchable one-line-per-task list"
```

---

### Task 9: Wire 3 tabs, new attention rules, delete the old machinery

**Files:**
- Modify: `lib/features/workforce_planning/workforce_planning_screen.dart`
- Modify: `lib/features/workforce_planning/needs_attention.dart`, `tabs/needs_attention_strip.dart`, `test/features/workforce_planning/needs_attention_test.dart`, `needs_attention_strip_test.dart`
- Modify: `lib/features/workforce_planning/wp_providers.dart` (host `ownerComputedProvider`; delete `wpTaskAssignmentsProvider`, `wpAssignmentsByTaskProvider`, and the `balance_rows.dart` import if `wpKpiCountByEmployeeProvider` moves or is deleted — keep it only if something outside the deleted files uses it)
- Modify importers of `ownerComputedProvider`: `role/responsibilities_pane.dart`, `role/kpis_pane.dart`, `tabs/drivers_scenario_tab.dart` → import from `../wp_providers.dart`
- Delete: `tabs/balance_tab.dart`, `tabs/role_view_tab.dart`, `tabs/unassigned_tab.dart`, `tabs/assignment_panel.dart`, `tabs/responsibilities_tab.dart`, `allocation.dart`, `rebalance.dart`, `unassigned_workspace.dart`, `balance_rows.dart`, `tasks_paging.dart`, `task_costing.dart`, `role_rollup.dart`, and their tests (`balance_tab_test`, `balance_rows_test`, `allocation_test`, `assignment_panel_test`, `attribute_task_test`, `rebalance_test`, `unassigned_tab_test`, `unassigned_workspace_test`, `responsibilities_tab_test`, `responsibilities_tab_archive_test`, `responsibilities_tab_costing_test`, `tasks_paging_test`, `task_costing_test`, `role_rollup_test`, `role_lens_test` if it imports a deleted file)
- Modify: `workforce_planning_repository.dart` — delete `reassignTaskOwner`, `primaryAssignmentPayload`, `setAllocations`, `upsertAssignment`, `deleteAssignment`, `taskAssignments`, `taskComputedForOwner` ONLY if no remaining caller (check with grep after the deletions).

**Interfaces:**
- Produces: `enum AttentionTarget { roles, tasks, kpiLibrary }`; tab indexes Roles 0, Organization 1, All tasks 2; `buildNeedsAttention` signature loses `loads` and `assignmentsByTask`, gains `required List<RoleLoad> roleLoads`.

- [ ] **Step 1: Update the needs-attention tests first.** In `needs_attention_test.dart`, replace the people/process rules' tests with:

```dart
  test('role-first signals', () {
    final bh = role('bh', 'Brand Handler');
    final k = role('k', 'Kiosk');
    final loads = buildRoleLoads(
      roles: [bh, k],
      employees: [emp('ana', role: 'bh')],
      tasks: const [
        WpTask(id: 't1', companyId: 'c', name: 'a', roleScorecardId: 'bh'),
        WpTask(id: 't2', companyId: 'c', name: 'b', roleScorecardId: 'k'),
        WpTask(id: 't3', companyId: 'c', name: 'orphan'),
        WpTask(id: 't4', companyId: 'c', name: 'legacy', externalRef: 'X'),
        WpTask(id: 't5', companyId: 'c', name: 'flag', roleScorecardId: 'bh', allocationReviewNote: 'was: x'),
      ],
      hoursByTaskId: const {'t1': 200, 't2': 10},
      capacityByEmployee: const {'ana': 160},
      defaultCapacity: 160,
    );
    final items = buildNeedsAttention(
      roleLoads: loads,
      tasks: loads.expand((l) => l.tasks).toList() + const [
        WpTask(id: 't3', companyId: 'c', name: 'orphan'),
        WpTask(id: 't4', companyId: 'c', name: 'legacy', externalRef: 'X'),
      ],
      employees: [emp('ana', role: 'bh')],
      cards: [bh, k],
      kpis: const [],
      kpiAssignedByKpi: const {},
    );
    String? label(String contains) => items.map((i) => i.label).where((l) => l.contains(contains)).firstOrNull;
    expect(label('over capacity'), '1 role over capacity');
    expect(label('no role'), '1 task with no role', reason: 'legacy excluded');
    expect(label('nobody holds'), '1 role nobody holds');
    expect(label('check'), '1 task to check');
  });
```

(Reuse the file's existing `emp`/`role` helpers; if their names differ, adapt the calls — the assertions are the contract.) Delete the tests for the removed signals: "people over capacity", "responsibilities unassigned", "critical responsibilities nobody owns", "shares don't total 100%". Keep every KPI/structure test unchanged except the `roles nobody holds` test, which now reads holders from `roleLoads` (drop the `holderCountByRole` argument).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/needs_attention_test.dart`
Expected: FAIL — `roleLoads` is not a parameter.

- [ ] **Step 3: Rewrite the rule set in `needs_attention.dart`**

- Change imports: drop `allocation.dart`, `unassigned_workspace.dart`, `capacity_math.dart`; add `role_load.dart`.
- `enum AttentionTarget { roles, tasks, kpiLibrary }`.
- Signature: replace `required List<WpPersonLoad> loads,` with `required List<RoleLoad> roleLoads,`; delete the `assignmentsByTask` and `holderCountByRole` parameters.
- Replace the People block (over / orphans / criticalOrphans) and the `misallocated` block with:

```dart
  // People — roles, not persons: every holder of a role shares its load.
  final overRoles = roleLoads
      .where((r) => r.holders.isNotEmpty && r.status == LoadStatus.over)
      .length;
  add(
    AttentionCategory.people,
    AttentionSeverity.high,
    overRoles,
    '${_plural(overRoles, 'role', 'roles')} over capacity',
    AttentionTarget.roles,
  );

  final noRole = noRoleTasks(tasks).length;
  add(
    AttentionCategory.people,
    AttentionSeverity.medium,
    noRole,
    '${_plural(noRole, 'task', 'tasks')} with no role',
    AttentionTarget.roles,
  );

  final flagged = flaggedTasks(tasks).length;
  add(
    AttentionCategory.process,
    AttentionSeverity.medium,
    flagged,
    '${_plural(flagged, 'task', 'tasks')} to check',
    AttentionTarget.roles,
  );
```

- Replace the `unfilledRoles` block's source with `roleLoads.where((r) => r.holders.isEmpty).length` and label unchanged (`'… nobody holds'`), target `AttentionTarget.roles`.
- `unstaffedCritical`: replace `_cardHasActiveHolder(employees, c.id)` with a lookup in `{for (final r in roleLoads) r.role.id: r.holders.isNotEmpty}`; delete `_cardHasActiveHolder`.
- `uncostedEssential` target → `AttentionTarget.tasks`. Every `AttentionTarget.balance`/`.unassigned` reference → `.roles`.

`LoadStatus` needs `capacity_math.dart` after all — keep that import.

- [ ] **Step 4: Update `needs_attention_strip.dart`**: tab map `{AttentionTarget.roles: 0, AttentionTarget.tasks: 2}`; update the doc comment to "Roles 0, Organization 1, All tasks 2"; delete the `if (item.target == AttentionTarget.balance)` branch at line ~128 (read it first; keep whatever non-balance behaviour it guards). Build `roleLoads` in the strip the same way `_BoardData` does (roles, employees, tasks, computed via `taskHours`, capacities from `wpPersonLoadsProvider`, default capacity from `wpConfigProvider`) and pass it to `buildNeedsAttention`. Update `needs_attention_strip_test.dart` overrides: remove `wpTaskAssignmentsProvider`, add `wpAllTaskComputedProvider` and `wpConfigProvider` overrides; change expected labels to the new wording.

- [ ] **Step 5: Move `ownerComputedProvider` into `wp_providers.dart`** (verbatim, including its doc comment) and point its three importers at `../wp_providers.dart` (or `wp_providers.dart` relative path as appropriate). Also remove `ref.invalidate(wpTaskAssignmentsProvider);` in `responsibilities_pane.dart`.

- [ ] **Step 6: Rewrite `workforce_planning_screen.dart`'s tabs**

```dart
    return DefaultTabController(
      length: 3,
      ...
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Roles'),
              Tab(text: 'Organization'),
              Tab(text: 'All tasks'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            RolesBoardTab(),
            OrganizationTab(),
            AllTasksTab(),
          ],
        ),
```

Update the class doc comment to the three tabs and the questions they answer; update imports.

- [ ] **Step 7: Delete the superseded files** listed above with `git rm`, then:

Run: `flutter analyze 2>&1 | tail -30`
Fix every error by removing dead imports/usages (never by resurrecting a deleted file). For each repository method in the Files list: `grep -rn "<method>(" lib test` — delete it only if the grep is empty.

- [ ] **Step 8: Run the whole WP + documents suites**

Run: `flutter test test/features/workforce_planning test/data 2>&1 | tail -5`
Expected: All tests passed.

- [ ] **Step 9: Commit**

```bash
git add -A lib/features/workforce_planning lib/data/repositories/workforce_planning_repository.dart test/features/workforce_planning
git commit -m "feat(wp): 3-tab Workforce Planning; role-first attention rules; remove %-assignment machinery"
```

(`git add -A` is scoped to these paths so the unrelated main-tree changes can't be staged; you are in a worktree anyway.)

---

### Task 10: Role card PDF + contract Annex A stop reading person/shared allocation

**Files:**
- Modify: `lib/data/repositories/role_scorecard_repository.dart` (`list`, `byId`, `_withSharedResponsibilities`, `assignedTasksByCard`, `activeTasksOwnedBy`, `createDraftRoleFromTasks`)
- Modify: `lib/features/documents/templates/employment_contract_template.dart:~675-690`
- Modify: `test/data/models/role_scorecard_responsibilities_test.dart` only if it calls a deleted repository method (the `withExtraResponsibilities` model tests stay — the model method is kept).

**Interfaces:**
- Produces: `RoleScorecardRepository.list()` / `byId()` return the authored responsibilities only.

- [ ] **Step 1: Repository.** In `list()` replace `return _withSharedResponsibilities(cards);` with `return cards;`. In `byId()` replace the `merged` block with `return RoleScorecard.fromRow(row);`. Delete `_withSharedResponsibilities`, `assignedTasksByCard`, `activeTasksOwnedBy`. In `createDraftRoleFromTasks` delete the two `wp_task_assignments` statements and their comment (the `wp_tasks` update is now the whole move).

- [ ] **Step 2: Contract.** In `employment_contract_template.dart` delete the "Personally-owned, off-card ACTIVE tasks" block (the `ownedExtra` declaration and its `try/catch`), then follow `ownedExtra` to where it is appended to Annex A and remove that use. Leave a one-line comment at the removal point: `// Annex A lists the role's tasks only — tasks belong to roles (spec 2026-09-28-simple-task-allocation-design.md).`

- [ ] **Step 3: Analyze + tests**

Run: `flutter analyze 2>&1 | tail -5 && flutter test test/data test/features/documents 2>&1 | tail -5`
Expected: no new analyze issues; All tests passed. If a documents test asserted the owned-task annex rows, delete that test case (the behaviour is intentionally gone) and say so in the commit body.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/role_scorecard_repository.dart lib/features/documents/templates/employment_contract_template.dart test
git commit -m "feat(wp): role card + Annex A list the role's own tasks only"
```

---

### Task 11: Full verification, handoff

- [ ] **Step 1:** `flutter analyze 2>&1 | tail -3` — issue count ≤ Task 0 baseline. Paste the output.
- [ ] **Step 2:** `flutter test 2>&1 | tail -3` — All tests passed. Paste the output.
- [ ] **Step 3:** Update `.agent/state.md` in the worktree: add a section "Simple task allocation (role first)" — branch, commits, migration `20260929000001` NOT applied (owner runs `supabase db push --linked`; until then the app reads the old `wp_person_load` and `allocation_review_note` is missing, so the board's "Check these" query will error — DO NOT merge to main before the push), GUI smoke checklist:
  1. Roles tab opens; over-loaded role first; "Needs X people" matches hand math for one role.
  2. Drag a task to another role → before/after %, Apply → reload shows it moved.
  3. "Check these" rows show the old split; "Looks right" removes a row.
  4. New task: Daily · 60 min on a 2-holder role shows "≈ 26.0 h/mo · split across 2 people".
  5. Generate a contract for someone whose role has tasks — Annex A lists them, no "Additional Responsibilities" block.
- [ ] **Step 4:** Commit the state file, then use superpowers:finishing-a-development-branch.
