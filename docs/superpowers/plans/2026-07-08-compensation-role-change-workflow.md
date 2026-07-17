# Compensation & Role Change Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let HR perform a salary or role change against an employee that writes an effective-dated compensation record and auto-drafts the matching notice via a workflow — the way separation already works.

**Architecture:** A new `compensation_changes` table becomes the effective-dated source of truth for an individual's pay/role; `role_scorecards.base_salary` becomes the role's reference/band. Payroll resolves each employee's effective compensation row (falling back to the scorecard), so future-dated changes auto-apply with no cron. Confirming a change writes the row → appends an `employment_events` timeline entry → drafts an `employee_documents` notice → seeds a `SALARY_CHANGE`/`ROLE_CHANGE` workflow whose one step renders the PDF via the existing "Generate now" flow. The notice reuses the existing `SalaryAdjustmentTemplate`, extended with `lateral` and `demotion` modes.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase Postgres, Dart `decimal`, `flutter_test`.

## Global Constraints

- Package import prefix is `package:payroll_flutter/…`. Run Dart tests with `flutter test <path>`.
- Repo gates on `flutter analyze` (must be clean), **not** on `dart format`. Match each file's surrounding formatting style; do not reformat existing code. (memory: repo-not-gated-on-dart-format)
- Salary math uses `package:decimal/decimal.dart` (`Decimal`), never `double`. Money is rendered via `lib/core/money.dart` `Money.fmtPhp`.
- `wage_type` values are exactly `'MONTHLY' | 'DAILY' | 'HOURLY'`. Change types are exactly `'SALARY_INCREASE' | 'SALARY_DECREASE' | 'PROMOTION' | 'LATERAL_TRANSFER' | 'DEMOTION'`. Change statuses are exactly `'SCHEDULED' | 'APPLIED' | 'CANCELLED'`.
- `employment_event_type` already contains `SALARY_CHANGE, ROLE_CHANGE, DEPARTMENT_TRANSFER, PROMOTION, DEMOTION` — do **not** add event-type enum values.
- `employee_documents.document_type` is `varchar(50)` (not an enum) — new codes `PROMOTION`, `LATERAL_TRANSFER`, `DEMOTION` need no migration.
- New migration timestamp must sort after `20260630000002` and every other pending migration. Use `20260708000001_compensation_changes.sql`. Migrations applied to prod are a separate deploy gate (memory: migration prod-deploy gates) — do not assume prod is migrated.
- Multiple Claude sessions share this working dir — implement on an isolated git worktree/branch (memory: concurrent-sessions-worktree). The executing skill sets this up.
- Payroll invariant preserved: the statutory `declared_wage_override` path is unchanged; it still layers on top as `StatutoryOverride`. Only the *actual-earnings* base rate resolution changes.

---

### Task 1: Migration — `compensation_changes` table

**Files:**
- Create: `supabase/migrations/20260708000001_compensation_changes.sql`

**Interfaces:**
- Produces: table `compensation_changes` with columns used by every later task (see model in Task 2). Columns: `id, company_id, employee_id, change_type, status, effective_date, prev_base_salary, new_base_salary, prev_wage_type, new_wage_type, prev_scorecard_id, new_scorecard_id, reason, workflow_id, document_id, initiated_by_id, applied_at, created_at, updated_at, deleted_at`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260708000001_compensation_changes.sql`:

```sql
-- 20260708000001_compensation_changes.sql
--
-- Per-employee, effective-dated source of truth for an individual's pay/role.
-- role_scorecards.base_salary stays as the role's reference/band; payroll
-- resolves the current effective compensation_changes row and falls back to
-- the scorecard when none exists (see compute_service.dart). Text+check
-- columns (not new enum types) — mirrors the job_listings.status idiom.

create table compensation_changes (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id),
  employee_id         uuid not null references employees(id),
  change_type         text not null
    check (change_type in ('SALARY_INCREASE','SALARY_DECREASE','PROMOTION','LATERAL_TRANSFER','DEMOTION')),
  status              text not null default 'SCHEDULED'
    check (status in ('SCHEDULED','APPLIED','CANCELLED')),
  effective_date      date not null,
  prev_base_salary    numeric(14,2),
  new_base_salary     numeric(14,2),
  prev_wage_type      text check (prev_wage_type in ('MONTHLY','DAILY','HOURLY')),
  new_wage_type       text check (new_wage_type in ('MONTHLY','DAILY','HOURLY')),
  prev_scorecard_id   uuid references role_scorecards(id),
  new_scorecard_id    uuid references role_scorecards(id),
  reason              text not null default '',
  workflow_id         uuid references workflow_instances(id),
  document_id         uuid references employee_documents(id),
  initiated_by_id     uuid not null references users(id),
  applied_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);

-- Payroll resolver lookup: newest effective row per employee.
create index idx_comp_changes_employee_effective
  on compensation_changes (employee_id, effective_date)
  where deleted_at is null;

-- "apply due" sweep: scheduled rows past their effective date.
create index idx_comp_changes_status
  on compensation_changes (status)
  where deleted_at is null;

create index idx_comp_changes_workflow
  on compensation_changes (workflow_id)
  where workflow_id is not null;

create trigger _compensation_changes_updated before update on compensation_changes
  for each row execute function set_updated_at();

-- RLS — mirrors job_listings (company-scoped + role-gated).
alter table compensation_changes enable row level security;

create policy compensation_changes_company_select on compensation_changes for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');

create policy compensation_changes_company_write on compensation_changes for all
  using (
    (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
    or auth_app_role() = 'SUPER_ADMIN'
  )
  with check (
    (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
    or auth_app_role() = 'SUPER_ADMIN'
  );
```

- [ ] **Step 2: Apply to the local Supabase stack to verify it parses/applies**

Run: `supabase db reset` (local Docker stack — applies every migration from scratch)
Expected: completes without error; the run lists `20260708000001_compensation_changes.sql` among applied migrations. If the local stack isn't running, start it with `supabase start` first. (Prod apply is a separate deploy gate — do not run against prod here.)

- [ ] **Step 3: Sanity-check the table exists**

Run: `supabase db reset` output already confirms; optionally `psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" -c '\d compensation_changes'`
Expected: table with the columns above, RLS enabled.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260708000001_compensation_changes.sql
git commit -m "feat(comp): add compensation_changes table + RLS"
```

---

### Task 2: `CompensationChange` model

**Files:**
- Create: `lib/data/models/compensation_change.dart`
- Test: `test/data/models/compensation_change_test.dart`

**Interfaces:**
- Produces:
  - `class CompensationChange` with fields `String id, companyId, employeeId, changeType, status; DateTime effectiveDate; Decimal? prevBaseSalary, newBaseSalary; String? prevWageType, newWageType, prevScorecardId, newScorecardId; String reason; String? workflowId, documentId; String initiatedById; DateTime? appliedAt; DateTime createdAt; DateTime? deletedAt`.
  - `factory CompensationChange.fromRow(Map<String, dynamic> r)`.
  - `bool get isRoleChange` → true when `newScorecardId != null && newScorecardId != prevScorecardId`.

- [ ] **Step 1: Write the failing test**

Create `test/data/models/compensation_change_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';

void main() {
  group('CompensationChange.fromRow', () {
    test('parses a full row', () {
      final c = CompensationChange.fromRow({
        'id': 'C1',
        'company_id': 'CO1',
        'employee_id': 'E1',
        'change_type': 'PROMOTION',
        'status': 'SCHEDULED',
        'effective_date': '2026-08-01',
        'prev_base_salary': '30000.00',
        'new_base_salary': '38000.00',
        'prev_wage_type': 'MONTHLY',
        'new_wage_type': 'MONTHLY',
        'prev_scorecard_id': 'S1',
        'new_scorecard_id': 'S2',
        'reason': 'Merit + role move',
        'workflow_id': 'W1',
        'document_id': 'D1',
        'initiated_by_id': 'U1',
        'applied_at': null,
        'created_at': '2026-07-08T00:00:00Z',
        'deleted_at': null,
      });
      expect(c.changeType, 'PROMOTION');
      expect(c.newBaseSalary, Decimal.parse('38000.00'));
      expect(c.effectiveDate, DateTime.parse('2026-08-01'));
      expect(c.isRoleChange, isTrue);
    });

    test('isRoleChange is false when scorecard unchanged', () {
      final c = CompensationChange.fromRow({
        'id': 'C2', 'company_id': 'CO1', 'employee_id': 'E1',
        'change_type': 'SALARY_INCREASE', 'status': 'SCHEDULED',
        'effective_date': '2026-08-01',
        'prev_scorecard_id': 'S1', 'new_scorecard_id': 'S1',
        'initiated_by_id': 'U1', 'created_at': '2026-07-08T00:00:00Z',
      });
      expect(c.isRoleChange, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/compensation_change_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../compensation_change.dart'`.

- [ ] **Step 3: Write the model**

Create `lib/data/models/compensation_change.dart`:

```dart
import 'package:decimal/decimal.dart';

/// Plain-Dart model mirroring the `compensation_changes` table
/// (supabase/migrations/20260708000001_compensation_changes.sql).
///
/// Effective-dated source of truth for an individual's pay/role. Payroll reads
/// the current effective row and falls back to `role_scorecards.base_salary`.
class CompensationChange {
  final String id;
  final String companyId;
  final String employeeId;
  final String changeType; // SALARY_INCREASE|SALARY_DECREASE|PROMOTION|LATERAL_TRANSFER|DEMOTION
  final String status;     // SCHEDULED|APPLIED|CANCELLED
  final DateTime effectiveDate;
  final Decimal? prevBaseSalary;
  final Decimal? newBaseSalary;
  final String? prevWageType;
  final String? newWageType;
  final String? prevScorecardId;
  final String? newScorecardId;
  final String reason;
  final String? workflowId;
  final String? documentId;
  final String initiatedById;
  final DateTime? appliedAt;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const CompensationChange({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.changeType,
    required this.status,
    required this.effectiveDate,
    this.prevBaseSalary,
    this.newBaseSalary,
    this.prevWageType,
    this.newWageType,
    this.prevScorecardId,
    this.newScorecardId,
    this.reason = '',
    this.workflowId,
    this.documentId,
    required this.initiatedById,
    this.appliedAt,
    required this.createdAt,
    this.deletedAt,
  });

  /// True when this change moves the employee to a different role scorecard.
  bool get isRoleChange =>
      newScorecardId != null && newScorecardId != prevScorecardId;

  factory CompensationChange.fromRow(Map<String, dynamic> r) {
    Decimal? dec(Object? v) => v == null ? null : Decimal.parse(v.toString());
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return CompensationChange(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      employeeId: r['employee_id'] as String,
      changeType: r['change_type'] as String,
      status: r['status'] as String,
      effectiveDate: DateTime.parse(r['effective_date'] as String),
      prevBaseSalary: dec(r['prev_base_salary']),
      newBaseSalary: dec(r['new_base_salary']),
      prevWageType: r['prev_wage_type'] as String?,
      newWageType: r['new_wage_type'] as String?,
      prevScorecardId: r['prev_scorecard_id'] as String?,
      newScorecardId: r['new_scorecard_id'] as String?,
      reason: r['reason'] as String? ?? '',
      workflowId: r['workflow_id'] as String?,
      documentId: r['document_id'] as String?,
      initiatedById: r['initiated_by_id'] as String,
      appliedAt: dt(r['applied_at']),
      createdAt: dt(r['created_at'])!,
      deletedAt: dt(r['deleted_at']),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/compensation_change_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/compensation_change.dart test/data/models/compensation_change_test.dart
git commit -m "feat(comp): CompensationChange model"
```

---

### Task 3: `effectiveCompensation` resolver (the effective-date core)

**Files:**
- Create: `lib/features/payroll/engine/effective_compensation.dart`
- Test: `test/engine/effective_compensation_test.dart`

**Interfaces:**
- Consumes: `CompensationChange` (Task 2).
- Produces: `CompensationChange? effectiveCompensation(List<CompensationChange> changes, DateTime asOf)` — the row with the greatest `effectiveDate <= asOf` among rows whose `status` is `SCHEDULED` or `APPLIED` and `deletedAt == null`; ties broken by `createdAt` (newest), then `id`. Returns `null` when none qualify (caller falls back to the scorecard).

- [ ] **Step 1: Write the failing test**

Create `test/engine/effective_compensation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/features/payroll/engine/effective_compensation.dart';

CompensationChange _c({
  required String id,
  required String effective,
  String status = 'SCHEDULED',
  String created = '2026-07-08T00:00:00Z',
  bool deleted = false,
}) =>
    CompensationChange(
      id: id,
      companyId: 'CO1',
      employeeId: 'E1',
      changeType: 'SALARY_INCREASE',
      status: status,
      effectiveDate: DateTime.parse(effective),
      initiatedById: 'U1',
      createdAt: DateTime.parse(created),
      deletedAt: deleted ? DateTime.parse('2026-07-09T00:00:00Z') : null,
    );

void main() {
  group('effectiveCompensation', () {
    test('empty list returns null (scorecard fallback)', () {
      expect(effectiveCompensation(const [], DateTime.parse('2026-08-01')), isNull);
    });

    test('future-dated row is not yet effective', () {
      final rows = [_c(id: 'A', effective: '2026-09-01')];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15')), isNull);
    });

    test('picks the latest effective_date at or before asOf', () {
      final rows = [
        _c(id: 'A', effective: '2026-06-01'),
        _c(id: 'B', effective: '2026-08-01'),
        _c(id: 'C', effective: '2026-10-01'),
      ];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15'))!.id, 'B');
    });

    test('effective_date exactly equal to asOf qualifies', () {
      final rows = [_c(id: 'A', effective: '2026-08-01')];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-01'))!.id, 'A');
    });

    test('CANCELLED and soft-deleted rows are ignored', () {
      final rows = [
        _c(id: 'A', effective: '2026-08-01', status: 'CANCELLED'),
        _c(id: 'B', effective: '2026-07-01', deleted: true),
        _c(id: 'C', effective: '2026-06-01'),
      ];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15'))!.id, 'C');
    });

    test('APPLIED rows count', () {
      final rows = [_c(id: 'A', effective: '2026-08-01', status: 'APPLIED')];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15'))!.id, 'A');
    });

    test('same effective_date tie-breaks on newest created_at', () {
      final rows = [
        _c(id: 'OLD', effective: '2026-08-01', created: '2026-07-01T00:00:00Z'),
        _c(id: 'NEW', effective: '2026-08-01', created: '2026-07-05T00:00:00Z'),
      ];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15'))!.id, 'NEW');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/engine/effective_compensation_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the resolver**

Create `lib/features/payroll/engine/effective_compensation.dart`:

```dart
import '../../../data/models/compensation_change.dart';

/// Selects the compensation change in effect as of [asOf].
///
/// Qualifying rows: status SCHEDULED or APPLIED, not soft-deleted, and
/// `effectiveDate <= asOf`. Among those, the one with the greatest
/// `effectiveDate` wins; ties break on newest `createdAt`, then `id`.
/// Returns null when nothing qualifies — the caller then falls back to the
/// role scorecard's `base_salary` / `wage_type`.
CompensationChange? effectiveCompensation(
  List<CompensationChange> changes,
  DateTime asOf,
) {
  CompensationChange? best;
  for (final c in changes) {
    if (c.deletedAt != null) continue;
    if (c.status != 'SCHEDULED' && c.status != 'APPLIED') continue;
    if (c.effectiveDate.isAfter(asOf)) continue;
    if (best == null || _beats(c, best)) best = c;
  }
  return best;
}

bool _beats(CompensationChange a, CompensationChange b) {
  final byDate = a.effectiveDate.compareTo(b.effectiveDate);
  if (byDate != 0) return byDate > 0;
  final byCreated = a.createdAt.compareTo(b.createdAt);
  if (byCreated != 0) return byCreated > 0;
  return a.id.compareTo(b.id) > 0;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/engine/effective_compensation_test.dart`
Expected: PASS (all 7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/payroll/engine/effective_compensation.dart test/engine/effective_compensation_test.dart
git commit -m "feat(comp): effective-date resolver for compensation changes"
```

---

### Task 4: `CompensationChangeRepository` + pure insert-payload builder

**Files:**
- Create: `lib/data/repositories/compensation_change_repository.dart`
- Test: `test/data/repositories/compensation_change_payload_test.dart`

**Interfaces:**
- Consumes: `CompensationChange` (Task 2).
- Produces:
  - `Map<String, dynamic> buildCompensationChangeInsert({required String id, companyId, employeeId, changeType, status, required DateTime effectiveDate, Decimal? prevBaseSalary, newBaseSalary, String? prevWageType, newWageType, prevScorecardId, newScorecardId, required String reason, required String initiatedById})` — top-level pure function.
  - `class CompensationChangeRepository` with:
    - `Future<CompensationChange> insert({... same fields ..., bool applyImmediately})` — inserts the row (status `APPLIED` + `applied_at` when `applyImmediately`, else `SCHEDULED`) and returns the created model. Does **not** repoint the employee (the confirm handler does that, Task 10).
    - `Future<List<CompensationChange>> listByEmployee(String employeeId)`
    - `Future<List<CompensationChange>> pendingByEmployee(String employeeId)` — status `SCHEDULED`, not deleted.
    - `Future<void> linkWorkflow({required String id, required String workflowId, required String documentId})`
    - `Future<void> cancel(String id)` — status → `CANCELLED`.
    - `Future<int> applyDue({required String companyId, required DateTime asOf})` — for every `SCHEDULED` row with `effective_date <= asOf`, when `new_scorecard_id` differs from the employee's current `role_scorecard_id` repoint it, then mark the row `APPLIED` + stamp `applied_at`. Returns count applied.
  - Providers: `compensationChangeRepositoryProvider`, `compensationChangesByEmployeeProvider(employeeId)`, `pendingCompensationChangesProvider(employeeId)`.

- [ ] **Step 1: Write the failing test (pure payload builder)**

Create `test/data/repositories/compensation_change_payload_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/compensation_change_repository.dart';

void main() {
  group('buildCompensationChangeInsert', () {
    test('maps every field to its column', () {
      final p = buildCompensationChangeInsert(
        id: 'C1',
        companyId: 'CO1',
        employeeId: 'E1',
        changeType: 'PROMOTION',
        status: 'SCHEDULED',
        effectiveDate: DateTime.parse('2026-08-01'),
        prevBaseSalary: Decimal.parse('30000'),
        newBaseSalary: Decimal.parse('38000'),
        prevWageType: 'MONTHLY',
        newWageType: 'MONTHLY',
        prevScorecardId: 'S1',
        newScorecardId: 'S2',
        reason: 'Merit',
        initiatedById: 'U1',
      );
      expect(p['id'], 'C1');
      expect(p['change_type'], 'PROMOTION');
      expect(p['status'], 'SCHEDULED');
      expect(p['effective_date'], '2026-08-01'); // date only, no time
      expect(p['prev_base_salary'], '30000');
      expect(p['new_base_salary'], '38000');
      expect(p['new_scorecard_id'], 'S2');
      expect(p['reason'], 'Merit');
      expect(p['initiated_by_id'], 'U1');
    });

    test('null salaries/scorecards serialize as null, not "null"', () {
      final p = buildCompensationChangeInsert(
        id: 'C2', companyId: 'CO1', employeeId: 'E1',
        changeType: 'LATERAL_TRANSFER', status: 'SCHEDULED',
        effectiveDate: DateTime.parse('2026-08-01'),
        prevBaseSalary: null, newBaseSalary: null,
        prevWageType: null, newWageType: null,
        prevScorecardId: 'S1', newScorecardId: 'S2',
        reason: '', initiatedById: 'U1',
      );
      expect(p['prev_base_salary'], isNull);
      expect(p['new_base_salary'], isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/compensation_change_payload_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the repository + payload builder**

Create `lib/data/repositories/compensation_change_repository.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/compensation_change.dart';

/// Pure builder for the INSERT payload. Kept top-level (no Supabase dependency)
/// so it is unit-testable in isolation, mirroring `buildInsertPayload` in
/// employee_document_repository.dart. `effective_date` is written date-only.
Map<String, dynamic> buildCompensationChangeInsert({
  required String id,
  required String companyId,
  required String employeeId,
  required String changeType,
  required String status,
  required DateTime effectiveDate,
  Decimal? prevBaseSalary,
  Decimal? newBaseSalary,
  String? prevWageType,
  String? newWageType,
  String? prevScorecardId,
  String? newScorecardId,
  required String reason,
  required String initiatedById,
}) {
  return {
    'id': id,
    'company_id': companyId,
    'employee_id': employeeId,
    'change_type': changeType,
    'status': status,
    'effective_date': effectiveDate.toIso8601String().substring(0, 10),
    'prev_base_salary': prevBaseSalary?.toString(),
    'new_base_salary': newBaseSalary?.toString(),
    'prev_wage_type': prevWageType,
    'new_wage_type': newWageType,
    'prev_scorecard_id': prevScorecardId,
    'new_scorecard_id': newScorecardId,
    'reason': reason,
    'initiated_by_id': initiatedById,
    if (status == 'APPLIED') 'applied_at': DateTime.now().toUtc().toIso8601String(),
  };
}

class CompensationChangeRepository {
  final SupabaseClient _client;
  CompensationChangeRepository(this._client);

  Future<CompensationChange> insert({
    required String companyId,
    required String employeeId,
    required String changeType,
    required DateTime effectiveDate,
    Decimal? prevBaseSalary,
    Decimal? newBaseSalary,
    String? prevWageType,
    String? newWageType,
    String? prevScorecardId,
    String? newScorecardId,
    required String reason,
    required String initiatedById,
    required bool applyImmediately,
  }) async {
    final id = const Uuid().v4();
    final payload = buildCompensationChangeInsert(
      id: id,
      companyId: companyId,
      employeeId: employeeId,
      changeType: changeType,
      status: applyImmediately ? 'APPLIED' : 'SCHEDULED',
      effectiveDate: effectiveDate,
      prevBaseSalary: prevBaseSalary,
      newBaseSalary: newBaseSalary,
      prevWageType: prevWageType,
      newWageType: newWageType,
      prevScorecardId: prevScorecardId,
      newScorecardId: newScorecardId,
      reason: reason,
      initiatedById: initiatedById,
    );
    final row = await _client
        .from('compensation_changes')
        .insert(payload)
        .select('*')
        .single();
    return CompensationChange.fromRow(row);
  }

  Future<List<CompensationChange>> listByEmployee(String employeeId) async {
    final rows = await _client
        .from('compensation_changes')
        .select('*')
        .eq('employee_id', employeeId)
        .isFilter('deleted_at', null)
        .order('effective_date', ascending: false);
    return (rows as List)
        .map((r) => CompensationChange.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<CompensationChange>> pendingByEmployee(String employeeId) async {
    final rows = await _client
        .from('compensation_changes')
        .select('*')
        .eq('employee_id', employeeId)
        .eq('status', 'SCHEDULED')
        .isFilter('deleted_at', null)
        .order('effective_date', ascending: true);
    return (rows as List)
        .map((r) => CompensationChange.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> linkWorkflow({
    required String id,
    required String workflowId,
    required String documentId,
  }) async {
    await _client
        .from('compensation_changes')
        .update({'workflow_id': workflowId, 'document_id': documentId})
        .eq('id', id);
  }

  Future<void> cancel(String id) async {
    await _client
        .from('compensation_changes')
        .update({'status': 'CANCELLED'})
        .eq('id', id);
  }

  /// Materializes every SCHEDULED change due on or before [asOf]: repoints the
  /// employee's role_scorecard_id when the change moves the role, then marks
  /// the change APPLIED. Called at the start of a payroll compute (no cron).
  Future<int> applyDue({
    required String companyId,
    required DateTime asOf,
  }) async {
    final due = await _client
        .from('compensation_changes')
        .select('id, employee_id, new_scorecard_id, prev_scorecard_id')
        .eq('company_id', companyId)
        .eq('status', 'SCHEDULED')
        .isFilter('deleted_at', null)
        .lte('effective_date', asOf.toIso8601String().substring(0, 10));
    var count = 0;
    for (final r in (due as List).cast<Map<String, dynamic>>()) {
      final newScorecardId = r['new_scorecard_id'] as String?;
      final prevScorecardId = r['prev_scorecard_id'] as String?;
      if (newScorecardId != null && newScorecardId != prevScorecardId) {
        await _client
            .from('employees')
            .update({'role_scorecard_id': newScorecardId})
            .eq('id', r['employee_id'] as String);
      }
      await _client.from('compensation_changes').update({
        'status': 'APPLIED',
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', r['id'] as String);
      count++;
    }
    return count;
  }
}

final compensationChangeRepositoryProvider =
    Provider<CompensationChangeRepository>(
        (ref) => CompensationChangeRepository(Supabase.instance.client));

final compensationChangesByEmployeeProvider =
    FutureProvider.family<List<CompensationChange>, String>((ref, employeeId) =>
        ref.read(compensationChangeRepositoryProvider).listByEmployee(employeeId));

final pendingCompensationChangesProvider =
    FutureProvider.family<List<CompensationChange>, String>((ref, employeeId) =>
        ref.read(compensationChangeRepositoryProvider).pendingByEmployee(employeeId));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/compensation_change_payload_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Verify analyze is clean**

Run: `flutter analyze lib/data/repositories/compensation_change_repository.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/compensation_change_repository.dart test/data/repositories/compensation_change_payload_test.dart
git commit -m "feat(comp): CompensationChangeRepository + insert payload builder"
```

---

### Task 5: Extend notice modes — enum, label, and validation

**Files:**
- Modify: `lib/features/documents/templates/salary_adjustment_inputs.dart` (enum `SalaryAdjustmentType`, `SalaryAdjustmentTypeX.label`)
- Modify: `lib/features/documents/templates/salary_adjustment_validate.dart`
- Test: `test/features/documents/salary_adjustment_validate_test.dart`

**Interfaces:**
- Produces: `enum SalaryAdjustmentType { salaryAdjustment, promotion, lateral, demotion }` with `.label`. Validation rules:
  - `lateral`: requires `newRoleScorecardId` set and different from old; salary must be **equal** (skip the "must differ" and "must be positive difference" checks; require `oldSalary == newSalary`).
  - `promotion` / `demotion`: require `newRoleScorecardId` set and different from old (existing promotion rule generalized to any role-changing mode).
  - Non-lateral modes keep the existing "new salary must differ from current" rule.

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/salary_adjustment_validate_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_validate.dart';

SalaryAdjustmentInputs _base({
  required SalaryAdjustmentType type,
  required Decimal oldS,
  required Decimal newS,
  String? oldRole,
  String? newRole,
}) =>
    SalaryAdjustmentInputs(
      type: type,
      employeeId: 'E1',
      employeeFullName: 'Jane Cruz',
      companyId: 'CO1',
      companyName: 'Luxium',
      hrManagerName: 'Brixter',
      oldRoleScorecardId: oldRole,
      newRoleScorecardId: newRole,
      oldSalary: oldS,
      newSalary: newS,
      reason: 'because',
      effectiveDate: DateTime.parse('2026-08-01'),
      issueDate: DateTime.parse('2026-07-08'),
    );

void main() {
  String? codes(List<ValidationError> e) => e.map((x) => x.field).join(',');

  test('lateral requires equal salary and a differing role', () {
    final ok = validateSalaryAdjustment(_base(
      type: SalaryAdjustmentType.lateral,
      oldS: Decimal.parse('30000'), newS: Decimal.parse('30000'),
      oldRole: 'S1', newRole: 'S2',
    ));
    expect(ok, isEmpty, reason: codes(ok));
  });

  test('lateral rejects a salary change', () {
    final bad = validateSalaryAdjustment(_base(
      type: SalaryAdjustmentType.lateral,
      oldS: Decimal.parse('30000'), newS: Decimal.parse('31000'),
      oldRole: 'S1', newRole: 'S2',
    ));
    expect(bad.any((e) => e.field == 'newSalary'), isTrue);
  });

  test('lateral rejects same role', () {
    final bad = validateSalaryAdjustment(_base(
      type: SalaryAdjustmentType.lateral,
      oldS: Decimal.parse('30000'), newS: Decimal.parse('30000'),
      oldRole: 'S1', newRole: 'S1',
    ));
    expect(bad.any((e) => e.field == 'newRoleScorecardId'), isTrue);
  });

  test('demotion requires a differing role', () {
    final bad = validateSalaryAdjustment(_base(
      type: SalaryAdjustmentType.demotion,
      oldS: Decimal.parse('30000'), newS: Decimal.parse('25000'),
      oldRole: 'S1', newRole: null,
    ));
    expect(bad.any((e) => e.field == 'newRoleScorecardId'), isTrue);
  });

  test('plain salary adjustment still requires a difference', () {
    final bad = validateSalaryAdjustment(_base(
      type: SalaryAdjustmentType.salaryAdjustment,
      oldS: Decimal.parse('30000'), newS: Decimal.parse('30000'),
    ));
    expect(bad.any((e) => e.field == 'newSalary'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/salary_adjustment_validate_test.dart`
Expected: FAIL — `SalaryAdjustmentType` has no member `lateral`.

- [ ] **Step 3: Extend the enum + label**

In `lib/features/documents/templates/salary_adjustment_inputs.dart` replace the enum and its extension (lines 7–14):

```dart
enum SalaryAdjustmentType { salaryAdjustment, promotion, lateral, demotion }

extension SalaryAdjustmentTypeX on SalaryAdjustmentType {
  String get label => switch (this) {
    SalaryAdjustmentType.salaryAdjustment => 'Salary Adjustment',
    SalaryAdjustmentType.promotion => 'Promotion',
    SalaryAdjustmentType.lateral => 'Lateral Transfer',
    SalaryAdjustmentType.demotion => 'Demotion',
  };

  /// True for modes that move the employee to a different role scorecard.
  bool get isRoleChange =>
      this == SalaryAdjustmentType.promotion ||
      this == SalaryAdjustmentType.lateral ||
      this == SalaryAdjustmentType.demotion;
}
```

- [ ] **Step 4: Update validation**

In `lib/features/documents/templates/salary_adjustment_validate.dart`, replace the salary-difference block (lines 29–38) and the promotion block (lines 42–59) with:

```dart
  if (i.newSalary <= Decimal.zero) {
    errors.add(
      const ValidationError('newSalary', 'New salary must be positive'),
    );
  }
  if (i.type == SalaryAdjustmentType.lateral) {
    if (i.oldSalary != i.newSalary) {
      errors.add(const ValidationError(
        'newSalary', 'A lateral transfer keeps salary unchanged'));
    }
  } else if (i.oldSalary == i.newSalary) {
    errors.add(const ValidationError(
      'newSalary', 'New salary must differ from current'));
  }
  if (i.type.isRoleChange) {
    final newId = i.newRoleScorecardId ?? '';
    if (newId.isEmpty) {
      errors.add(const ValidationError(
        'newRoleScorecardId', 'Select the target role scorecard'));
    } else if (newId == (i.oldRoleScorecardId ?? '')) {
      errors.add(const ValidationError(
        'newRoleScorecardId', 'Target role must differ from current'));
    }
  }
```

Leave the earlier `oldSalary <= 0` and `reason` checks in place.

- [ ] **Step 5: Run test to verify it passes + full documents suite green**

Run: `flutter test test/features/documents/salary_adjustment_validate_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/salary_adjustment_inputs.dart lib/features/documents/templates/salary_adjustment_validate.dart test/features/documents/salary_adjustment_validate_test.dart
git commit -m "feat(comp): lateral + demotion notice modes with validation"
```

---

### Task 6: Notice body per mode + autofill from the compensation change

**Files:**
- Modify: `lib/features/documents/templates/salary_adjustment_template.dart` (`build`, `autofill`)
- Test: `test/features/documents/salary_adjustment_body_test.dart`

**Interfaces:**
- Consumes: `SalaryAdjustmentType` (Task 5), `CompensationChangeRepository.listByEmployee` (Task 4), `effectiveCompensation` NOT used here — instead the newest non-cancelled change for this employee drives the notice.
- Produces: `build(i)` emits a subject + body matching `i.type`. `autofill(ctx)` populates old/new salary, positions, period, effective date, reason, and mode from the employee's newest actionable `compensation_changes` row when one exists; otherwise falls back to today's scorecard-only behavior.

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/salary_adjustment_body_test.dart`. It reaches into `build()` output and asserts the subject text per mode. `LetterMetaBlock` carries the `subject`; `ParagraphBlock` carries body text.

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/letter_meta_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_template.dart';

SalaryAdjustmentInputs _i(SalaryAdjustmentType type) => SalaryAdjustmentInputs(
      type: type,
      employeeId: 'E1',
      employeeFullName: 'Jane Cruz',
      employeeGender: 'FEMALE',
      employeePosition: 'Brand Handler',
      companyId: 'CO1',
      companyName: 'Luxium',
      hrManagerName: 'Brixter',
      oldPosition: 'Brand Handler',
      newPosition: 'Senior Brand Handler',
      oldSalary: Decimal.parse('30000'),
      newSalary: type == SalaryAdjustmentType.lateral
          ? Decimal.parse('30000')
          : Decimal.parse('35000'),
      salaryPeriod: 'MONTHLY',
      reason: 'Merit review.',
      effectiveDate: DateTime.parse('2026-08-01'),
      issueDate: DateTime.parse('2026-07-08'),
    );

String _subject(List blocks) =>
    blocks.whereType<LetterMetaBlock>().first.subject ?? '';
String _body(List blocks) =>
    blocks.whereType<ParagraphBlock>().map((b) => b.text).join('\n');

void main() {
  const t = SalaryAdjustmentTemplate();

  test('lateral subject + unchanged-salary wording', () {
    final blocks = t.build(_i(SalaryAdjustmentType.lateral));
    expect(_subject(blocks), 'Notice of Lateral Transfer');
    expect(_body(blocks).toLowerCase(), contains('transferred'));
    expect(_body(blocks).toLowerCase(), contains('remains unchanged'));
  });

  test('demotion subject', () {
    final blocks = t.build(_i(SalaryAdjustmentType.demotion));
    expect(_subject(blocks), 'Notice of Change in Role');
  });

  test('promotion subject still works', () {
    final blocks = t.build(_i(SalaryAdjustmentType.promotion));
    expect(_subject(blocks), 'Notice of Promotion');
  });

  test('salary adjustment subject still works', () {
    final blocks = t.build(_i(SalaryAdjustmentType.salaryAdjustment));
    expect(_subject(blocks), 'Notice of Salary Adjustment');
  });
}
```

> Before writing implementation, open `lib/features/documents/blocks/paragraph_block.dart` and `letter_meta_block.dart` to confirm the field names used above (`ParagraphBlock.text`, `LetterMetaBlock.subject`). If a name differs, update the test to match the real field — do not invent fields.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/salary_adjustment_body_test.dart`
Expected: FAIL — subjects for lateral/demotion don't match (build only knows promotion vs salaryAdjustment).

- [ ] **Step 3: Update `build()` subject + body**

In `lib/features/documents/templates/salary_adjustment_template.dart`, replace the `subject` and `bodyText` computation (lines 126–140) with a `switch` over `i.type`:

```dart
    final subject = switch (i.type) {
      SalaryAdjustmentType.promotion => 'Notice of Promotion',
      SalaryAdjustmentType.lateral => 'Notice of Lateral Transfer',
      SalaryAdjustmentType.demotion => 'Notice of Change in Role',
      SalaryAdjustmentType.salaryAdjustment => 'Notice of Salary Adjustment',
    };

    final effective = df.format(i.effectiveDate);
    final oldPay = cf.format(i.oldSalary.toDouble());
    final newPay = cf.format(i.newSalary.toDouble());
    final bodyText = switch (i.type) {
      SalaryAdjustmentType.promotion =>
        'We are pleased to inform you that, effective $effective, you are being '
            'promoted from ${i.oldPosition} to ${i.newPosition}. In line with '
            'this promotion, your $periodLabel will be adjusted from $oldPay to '
            '$newPay. ${i.reason}',
      SalaryAdjustmentType.lateral =>
        'We wish to inform you that, effective $effective, you are being '
            'transferred from ${i.oldPosition} to ${i.newPosition}. Your '
            '$periodLabel remains unchanged at $oldPay. ${i.reason}',
      SalaryAdjustmentType.demotion =>
        'We wish to inform you that, effective $effective, your role will change '
            'from ${i.oldPosition} to ${i.newPosition}, and your $periodLabel '
            'will be adjusted from $oldPay to $newPay. ${i.reason}',
      SalaryAdjustmentType.salaryAdjustment =>
        'We are pleased to inform you that, effective $effective, your '
            '$periodLabel will be adjusted from $oldPay to $newPay. ${i.reason}',
    };
```

Keep the existing `LetterMetaBlock(subject: subject, …)` and `ParagraphBlock(bodyText)` usage.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/salary_adjustment_body_test.dart`
Expected: PASS.

- [ ] **Step 5: Autofill from the newest actionable comp change**

In the same file's `autofill(ctx)` (after the scorecard is fetched, before the `return`), insert a lookup so the notice reflects the change that was just created. Add near the top of the file: `import '../../../data/repositories/compensation_change_repository.dart';` and `import '../../../data/models/compensation_change.dart';`. Then before the `return SalaryAdjustmentInputs(...)`:

```dart
    // If a compensation change exists for this employee, render the notice from
    // it (exact prev/new snapshots) rather than inferring from the scorecard.
    CompensationChange? change;
    try {
      final all = await ctx.ref.read(
        compensationChangesByEmployeeProvider(e?.id ?? '').future,
      );
      change = all
          .where((c) => c.status != 'CANCELLED')
          .fold<CompensationChange?>(null, (best, c) =>
              best == null || c.createdAt.isAfter(best.createdAt) ? c : best);
    } catch (_) {
      change = null;
    }

    final mode = change == null
        ? SalaryAdjustmentType.salaryAdjustment
        : _modeForChangeType(change.changeType);
```

Then in the returned `SalaryAdjustmentInputs`, source values from `change` when present (fall back to the existing scorecard-derived values otherwise):

```dart
      type: mode,
      oldSalary: change?.prevBaseSalary ??
          e?.declaredWageOverride ?? scorecard?.baseSalary ?? Decimal.zero,
      newSalary: change?.newBaseSalary ?? Decimal.zero,
      salaryPeriod: change?.newWageType ?? scorecard?.wageType ?? 'MONTHLY',
      oldRoleScorecardId: change?.prevScorecardId ?? e?.roleScorecardId,
      newRoleScorecardId: change?.newScorecardId,
      effectiveDate: change?.effectiveDate ?? firstOfNextMonth,
      reason: change?.reason ?? '',
```

Add the private helper at the bottom of the file:

```dart
SalaryAdjustmentType _modeForChangeType(String changeType) => switch (changeType) {
      'PROMOTION' => SalaryAdjustmentType.promotion,
      'LATERAL_TRANSFER' => SalaryAdjustmentType.lateral,
      'DEMOTION' => SalaryAdjustmentType.demotion,
      _ => SalaryAdjustmentType.salaryAdjustment, // SALARY_INCREASE|SALARY_DECREASE
    };
```

For `newPosition`/`oldPosition`, resolve titles from the scorecards when a role change: keep the existing `oldPosition` line, and set `newPosition` by reading `change?.newScorecardId`'s scorecard title (reuse the already-imported `roleScorecardByIdProvider`; when null leave `''`).

- [ ] **Step 6: Verify analyze + documents suite**

Run: `flutter analyze lib/features/documents/templates/salary_adjustment_template.dart && flutter test test/features/documents/`
Expected: `No issues found!` then all documents tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/documents/templates/salary_adjustment_template.dart test/features/documents/salary_adjustment_body_test.dart
git commit -m "feat(comp): per-mode notice bodies + autofill from compensation change"
```

---

### Task 7: Workflow seeder + document-type helper

**Files:**
- Modify: `lib/features/workflows/seeders.dart` (add `seedCompensationChangeWorkflow`, `compensationDocumentType`, `compensationDocTitle`)
- Test: `test/features/workflows/compensation_seeder_test.dart`

**Interfaces:**
- Consumes: `WorkflowSeed`, `WorkflowInstanceInput`, `WorkflowStepInput` (existing).
- Produces:
  - `String compensationDocumentType(String changeType)` → `SALARY_ADJUSTMENT | PROMOTION | LATERAL_TRANSFER | DEMOTION`.
  - `WorkflowSeed seedCompensationChangeWorkflow({required String companyId, employeeId, employeeFullName, String changeType, required String employeeDocumentId, required String initiatedById})` → instance `workflow_type` is `ROLE_CHANGE` when `changeType` is `PROMOTION|LATERAL_TRANSFER|DEMOTION`, else `SALARY_CHANGE`; one `DOCUMENT_GENERATION` step with `input_data = {template_id: 'salary_adjustment', change_type, employee_document_id}` and `generatedDocumentId = employeeDocumentId`.

- [ ] **Step 1: Write the failing test**

Create `test/features/workflows/compensation_seeder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workflows/seeders.dart';

void main() {
  test('compensationDocumentType maps every change type', () {
    expect(compensationDocumentType('SALARY_INCREASE'), 'SALARY_ADJUSTMENT');
    expect(compensationDocumentType('SALARY_DECREASE'), 'SALARY_ADJUSTMENT');
    expect(compensationDocumentType('PROMOTION'), 'PROMOTION');
    expect(compensationDocumentType('LATERAL_TRANSFER'), 'LATERAL_TRANSFER');
    expect(compensationDocumentType('DEMOTION'), 'DEMOTION');
  });

  test('role changes seed a ROLE_CHANGE workflow', () {
    final seed = seedCompensationChangeWorkflow(
      companyId: 'CO1', employeeId: 'E1', employeeFullName: 'Jane Cruz',
      changeType: 'PROMOTION', employeeDocumentId: 'DOC1', initiatedById: 'U1',
    );
    expect(seed.instance.workflowType, 'ROLE_CHANGE');
    expect(seed.steps.single.stepType, 'DOCUMENT_GENERATION');
    expect(seed.steps.single.inputData!['template_id'], 'salary_adjustment');
    expect(seed.steps.single.inputData!['change_type'], 'PROMOTION');
    expect(seed.steps.single.generatedDocumentId, 'DOC1');
  });

  test('pay-only changes seed a SALARY_CHANGE workflow', () {
    final seed = seedCompensationChangeWorkflow(
      companyId: 'CO1', employeeId: 'E1', employeeFullName: 'Jane Cruz',
      changeType: 'SALARY_INCREASE', employeeDocumentId: 'DOC1', initiatedById: 'U1',
    );
    expect(seed.instance.workflowType, 'SALARY_CHANGE');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/workflows/compensation_seeder_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Add the seeder + helpers**

Append to `lib/features/workflows/seeders.dart`:

```dart
/// employee_documents.document_type for a compensation change notice.
/// Pay-only changes file as SALARY_ADJUSTMENT; role changes file distinctly.
String compensationDocumentType(String changeType) => switch (changeType) {
      'PROMOTION' => 'PROMOTION',
      'LATERAL_TRANSFER' => 'LATERAL_TRANSFER',
      'DEMOTION' => 'DEMOTION',
      _ => 'SALARY_ADJUSTMENT', // SALARY_INCREASE | SALARY_DECREASE
    };

String compensationDocTitle(String changeType) => switch (changeType) {
      'PROMOTION' => 'Notice of Promotion',
      'LATERAL_TRANSFER' => 'Notice of Lateral Transfer',
      'DEMOTION' => 'Notice of Change in Role',
      _ => 'Notice of Salary Adjustment',
    };

/// Build a SALARY_CHANGE (pay-only) or ROLE_CHANGE (role moved) workflow with a
/// single DOCUMENT_GENERATION step wired to the pre-inserted DRAFT notice row.
WorkflowSeed seedCompensationChangeWorkflow({
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  required String changeType,
  required String employeeDocumentId,
  required String initiatedById,
}) {
  final isRole = changeType == 'PROMOTION' ||
      changeType == 'LATERAL_TRANSFER' ||
      changeType == 'DEMOTION';
  final label = compensationDocTitle(changeType);
  return WorkflowSeed(
    instance: WorkflowInstanceInput(
      companyId: companyId,
      employeeId: employeeId,
      workflowType: isRole ? 'ROLE_CHANGE' : 'SALARY_CHANGE',
      title: '$label — $employeeFullName',
      context: {'change_type': changeType},
      initiatedById: initiatedById,
    ),
    steps: [
      WorkflowStepInput(
        stepIndex: 0,
        stepType: 'DOCUMENT_GENERATION',
        name: 'Generate $label',
        description: 'Render the $label PDF and mark this step complete.',
        inputData: {
          'template_id': 'salary_adjustment',
          'change_type': changeType,
          'employee_document_id': employeeDocumentId,
        },
        generatedDocumentId: employeeDocumentId,
      ),
    ],
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/workflows/compensation_seeder_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workflows/seeders.dart test/features/workflows/compensation_seeder_test.dart
git commit -m "feat(comp): compensation-change workflow seeder + doc-type helpers"
```

---

### Task 8: Payroll wiring — resolve effective compensation + apply due

**Files:**
- Modify: `lib/features/payroll/runs/compute/compute_service.dart`
- Test: `test/engine/compensation_gating_test.dart`

**Interfaces:**
- Consumes: `effectiveCompensation` (Task 3), `CompensationChangeRepository.applyDue` (Task 4), `CompensationChange` (Task 2).
- Produces: within `computeRun`, `applyDue` is called before the employees are loaded; the per-employee base rate/wage type/scorecard resolves the effective comp row (fallback to scorecard). No new public signature — behavior change is covered by the gating test at the resolver boundary plus a `flutter analyze`/smoke check.

- [ ] **Step 1: Write the failing test (gating at the boundary the engine relies on)**

The live Supabase read isn't unit-tested (matches repo convention). Instead, prove the exact selection rule the wiring depends on, using a period-boundary scenario. Create `test/engine/compensation_gating_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/features/payroll/engine/effective_compensation.dart';

CompensationChange _raise(String effective, String newSalary) => CompensationChange(
      id: 'R-$effective',
      companyId: 'CO1',
      employeeId: 'E1',
      changeType: 'SALARY_INCREASE',
      status: 'SCHEDULED',
      effectiveDate: DateTime.parse(effective),
      prevBaseSalary: Decimal.parse('30000'),
      newBaseSalary: Decimal.parse(newSalary),
      newWageType: 'MONTHLY',
      initiatedById: 'U1',
      createdAt: DateTime.parse('2026-07-08T00:00:00Z'),
    );

void main() {
  final changes = [_raise('2026-09-01', '38000')];

  test('a raise dated 2026-09-01 does not affect an August period', () {
    // Period end 2026-08-31 -> no effective row -> caller uses scorecard.
    final r = effectiveCompensation(changes, DateTime.parse('2026-08-31'));
    expect(r, isNull);
  });

  test('the same raise applies to the September period', () {
    final r = effectiveCompensation(changes, DateTime.parse('2026-09-30'));
    expect(r, isNotNull);
    expect(r!.newBaseSalary, Decimal.parse('38000'));
    expect(r.newWageType, 'MONTHLY');
  });
}
```

- [ ] **Step 2: Run test to verify it fails, then passes**

Run: `flutter test test/engine/compensation_gating_test.dart`
Expected: PASS immediately (it exercises Task 3 code). This test guards the contract the wiring depends on; keep it.

- [ ] **Step 3: Load compensation changes per run**

In `compute_service.dart`, extend the run's data loading. Add an import: `import '../../../../data/repositories/compensation_change_repository.dart';` and `import '../../../../data/models/compensation_change.dart';` and `import '../../engine/effective_compensation.dart';`.

Near the start of `computeRun`, after `companyId` and the period (`payPeriodInput` / period end date) are known and **before** the employees `select`, call apply-due so the stored `role_scorecard_id` reflects any change now in effect:

```dart
    // Materialize any SCHEDULED compensation changes now due (no cron). Must run
    // before the employees select so joined role_scorecards reflect role moves.
    await CompensationChangeRepository(_client)
        .applyDue(companyId: companyId, asOf: periodEnd);
```

(Use the run's period-end `DateTime` variable that already exists in scope — locate it near where `payPeriodInput` is built; name may be `periodEnd`/`end`. Do not invent a new query for it.)

Then fetch the changes for the run's employees into a map, mirroring how `attendanceByEmp` is built. After the employees list is loaded:

```dart
    final compRows = await _client
        .from('compensation_changes')
        .select('*')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .inFilter('employee_id', employees.map((e) => e['id'] as String).toList());
    final compByEmp = <String, List<CompensationChange>>{};
    for (final r in (compRows as List).cast<Map<String, dynamic>>()) {
      (compByEmp[r['employee_id'] as String] ??= []).add(CompensationChange.fromRow(r));
    }
```

Pass `comp: compByEmp[row['id']] ?? const []` into `_buildEmployeeInput` (add the named param to the call at line ~198 and to the method signature).

- [ ] **Step 4: Resolve the effective comp inside `_buildEmployeeInput`**

In `_buildEmployeeInput` (around line 612–635), add the `comp` parameter and replace the `baseRate`/`wageType` derivation (lines 631–635) with:

```dart
    // Effective compensation overrides the scorecard's base rate for actual
    // earnings. Falls back to the scorecard when no change is in effect.
    final effective = effectiveCompensation(comp, payPeriod.periodEnd);
    final wageTypeStr = effective?.newWageType ??
        (roleCard['wage_type'] as String?) ?? 'DAILY';
    final baseRate = effective?.newBaseSalary ??
        Decimal.tryParse((roleCard['base_salary'] ?? '0').toString()) ??
        Decimal.zero;
    final wageType = _parseWageType(wageTypeStr);
```

(Use whatever the in-scope period-end accessor is on `payPeriod`; check `PayPeriodInput`/`types.dart` for the exact field name — likely `periodEnd`. Match it exactly.)

- [ ] **Step 5: Verify analyze + full engine suite still green**

Run: `flutter analyze lib/features/payroll/runs/compute/compute_service.dart && flutter test test/engine/`
Expected: `No issues found!`, then all engine tests PASS (parity/smoke unaffected — no employee has comp rows in fixtures, so the scorecard fallback keeps existing results identical).

- [ ] **Step 6: Commit**

```bash
git add lib/features/payroll/runs/compute/compute_service.dart test/engine/compensation_gating_test.dart
git commit -m "feat(comp): payroll resolves effective compensation + applies due changes"
```

---

### Task 9: The change dialog + Role tab entry point

**Files:**
- Create: `lib/features/employees/profile/widgets/compensation_change_dialog.dart`
- Modify: `lib/features/employees/profile/tabs/role_tab.dart` (replace "Change Role" button; add "Pending changes" strip)
- Test: `test/features/employees/compensation_change_dialog_test.dart`

**Interfaces:**
- Produces:
  - `class CompensationChangeRequest { final String changeType; final Decimal newSalary; final String newWageType; final String? newScorecardId; final DateTime effectiveDate; final String reason; }`
  - `Future<CompensationChangeRequest?> showCompensationChangeDialog(BuildContext context, {required Employee employee, required RoleScorecard? currentCard, required List<RoleScorecard> allCards})` — returns null on cancel; returns a validated request on confirm. Field visibility follows the selected change type; validation reuses `validateSalaryAdjustment` semantics (build a `SalaryAdjustmentInputs` internally to validate before returning).

- [ ] **Step 1: Write the failing widget test**

Create `test/features/employees/compensation_change_dialog_test.dart`. Verify (a) the dialog surfaces a validation error when confirming a salary increase equal to current, and (b) selecting "Lateral transfer" hides the salary field. Pump the dialog inside a `ProviderScope` + `MaterialApp`. (Use `find.text`, `find.byKey`. Give the salary field `key: const Key('newSalaryField')` and the type dropdown `key: const Key('changeTypeDropdown')` in the implementation so the test can target them.)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ... imports for the dialog, Employee, RoleScorecard fixtures ...

void main() {
  testWidgets('salary field hidden for lateral transfer', (tester) async {
    // pump a button that calls showCompensationChangeDialog, tap it,
    // select 'Lateral Transfer' in the dropdown, expect newSalaryField absent.
    // (Full fixture wiring written during implementation.)
  }, skip: false);
}
```

> During implementation, flesh out the fixture (a minimal `Employee` + two `RoleScorecard`s). Keep the two assertions above. If widget-pumping the full dialog proves heavy, extract the pure validation into a top-level `List<ValidationError> validateCompensationRequest(...)` and unit-test THAT instead (preferred — faster, deterministic), and keep the widget test to the field-visibility assertion only.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/employees/compensation_change_dialog_test.dart`
Expected: FAIL — dialog symbol undefined.

- [ ] **Step 3: Implement the dialog**

Create `lib/features/employees/profile/widgets/compensation_change_dialog.dart`. Requirements:
- A `StatefulWidget` dialog with: a change-type `DropdownButtonFormField` (`Key('changeTypeDropdown')`) over the five types (labels from `SalaryAdjustmentTypeX.label` where applicable, plus "Salary Increase"/"Salary Decrease" for the two pay-only variants); a new-salary `TextFormField` (`Key('newSalaryField')`, shown for all types except `LATERAL_TRANSFER`, where it's hidden and the request carries the current salary); a wage-type dropdown (defaults to the current card's `wageType`); a role `DropdownButtonFormField` over `allCards` shown only for `PROMOTION|LATERAL_TRANSFER|DEMOTION`; an effective-date picker (default `DateTime(now.year, now.month + 1, 1)`); a reason `TextFormField`.
- On "Confirm", build a `SalaryAdjustmentInputs` from the fields + current values and run `validateSalaryAdjustment`; if non-empty, show the first error under the offending field and do not pop. On success, `Navigator.pop(context, CompensationChangeRequest(...))`.
- Currency parsing via `Decimal.parse` on the cleaned string; reject non-positive.

Follow the visual conventions in `PRODUCT.md` (6px radius, Luxium purple CTA, 4px spacing grid) — match the existing dialogs in `lib/features/employees/profile/widgets/`.

- [ ] **Step 4: Wire the Role tab**

In `role_tab.dart`, replace the "Change Role" `FilledButton` (lines 82–86) with an **"Adjust Compensation / Change Role"** button that:
1. reads `roleScorecardListProvider` (already watched as `cards`),
2. calls `showCompensationChangeDialog(context, employee: employee, currentCard: card, allCards: cards)`,
3. on a non-null result, calls the confirm handler from Task 10 (`runCompensationChange(...)`).

Add a "Pending changes" strip above "Current Role": watch `pendingCompensationChangesProvider(employee.id)`; for each row render a tinted card (reuse `_TintedCard` styling) showing the change type label, new value (`Money.fmtPhp`), `effective ${date}`, and a "View workflow" text button that `context.go('/workflows/${row.workflowId}')` when `workflowId != null`.

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/features/employees/compensation_change_dialog_test.dart && flutter analyze lib/features/employees/profile/`
Expected: PASS, then `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/employees/profile/widgets/compensation_change_dialog.dart lib/features/employees/profile/tabs/role_tab.dart test/features/employees/compensation_change_dialog_test.dart
git commit -m "feat(comp): change dialog + Role tab entry point and pending strip"
```

---

### Task 10: Confirm handler — change → timeline → draft notice → workflow

**Files:**
- Create: `lib/features/employees/profile/widgets/compensation_change_action.dart`
- Test: covered by Tasks 4/7 (pure pieces); this task is integration — verified by analyze + the end-to-end smoke in Task 12.

**Interfaces:**
- Consumes: `CompensationChangeRepository` (Task 4), `seedCompensationChangeWorkflow` + `compensationDocumentType` + `compensationDocTitle` (Task 7), `workflowRepositoryProvider.insertWithSteps` (existing), `CompensationChangeRequest` (Task 9).
- Produces: `Future<void> runCompensationChange({required WidgetRef ref, required BuildContext context, required Employee employee, required RoleScorecard? currentCard, required CompensationChangeRequest req})` — performs the full chain and shows a snackbar, mirroring the separation handler in `profile_header.dart:300-399`.

- [ ] **Step 1: Implement the handler**

Create `lib/features/employees/profile/widgets/compensation_change_action.dart`. Sequence (best-effort atomic, like separation):

```dart
// Pseudocode-precise sequence — write real Dart following profile_header.dart.
// 0. actorId = ref.read(userProfileProvider).asData?.value?.userId (match how
//    profile_header resolves the acting user id).
// 1. final applyImmediately = !req.effectiveDate.isAfter(today);
// 2. final change = await repo.insert(
//      companyId: employee.companyId, employeeId: employee.id,
//      changeType: req.changeType, effectiveDate: req.effectiveDate,
//      prevBaseSalary: currentCard?.baseSalary, newBaseSalary: req.newSalary,
//      prevWageType: currentCard?.wageType, newWageType: req.newWageType,
//      prevScorecardId: employee.roleScorecardId,
//      newScorecardId: req.newScorecardId ?? employee.roleScorecardId,
//      reason: req.reason, initiatedById: actorId, applyImmediately: applyImmediately);
// 3. if (applyImmediately && req.newScorecardId != null &&
//        req.newScorecardId != employee.roleScorecardId) {
//      await client.from('employees').update(
//        {'role_scorecard_id': req.newScorecardId}).eq('id', employee.id);
//    }
// 4. final eventType = switch (req.changeType) {
//      'PROMOTION' => 'PROMOTION', 'DEMOTION' => 'DEMOTION',
//      'LATERAL_TRANSFER' => 'DEPARTMENT_TRANSFER', _ => 'SALARY_CHANGE' };
//    final eventRow = await client.from('employment_events').insert({
//      'employee_id': employee.id, 'event_type': eventType,
//      'event_date': req.effectiveDate (yyyy-mm-dd), 'status': 'APPROVED',
//      'payload': {'change_id': change.id, 'reason': req.reason,
//                  'old_salary': currentCard?.baseSalary?.toString(),
//                  'new_salary': req.newSalary.toString()},
//      if (actorId != null) 'requested_by_id'/'approved_by_id'/'approved_at': ...,
//    }).select('id').single();
// 5. final docType = compensationDocumentType(req.changeType);
//    final docTitle = compensationDocTitle(req.changeType);
//    final docRow = await client.from('employee_documents').insert({
//      'employee_id': employee.id, 'document_type': docType, 'title': docTitle,
//      'file_name': '${employee.fullName} — $docTitle.pdf', 'status': 'DRAFT',
//      'generated_from_event_id': eventRow['id'],
//      if (actorId != null) 'uploaded_by_id': actorId,
//    }).select('id').single();
// 6. if (actorId != null) {
//      final seed = seedCompensationChangeWorkflow(
//        companyId: employee.companyId, employeeId: employee.id,
//        employeeFullName: employee.fullName, changeType: req.changeType,
//        employeeDocumentId: docRow['id'], initiatedById: actorId);
//      final wfId = await ref.read(workflowRepositoryProvider)
//        .insertWithSteps(instance: seed.instance, steps: seed.steps);
//      await repo.linkWorkflow(id: change.id, workflowId: wfId,
//        documentId: docRow['id'] as String);
//    }
// 7. invalidate: employeeByIdProvider(employee.id), employeeListProvider,
//    timelineProvider(employee.id), employeeDocumentsProvider(employee.id),
//    workflowListProvider, compensationChangesByEmployeeProvider(employee.id),
//    pendingCompensationChangesProvider(employee.id).
// 8. snackbar: '${employee.fullName}: ${compensationDocTitle(req.changeType)} '
//    'queued · effective ${date}.'
// Wrap in try/catch -> error snackbar, exactly like separation.
```

Match the imports, `ProviderContainer`/`ref` usage, actor resolution, and messenger pattern used in `profile_header.dart:280-399` verbatim so this behaves identically to separation.

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/features/employees/profile/widgets/compensation_change_action.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/employees/profile/widgets/compensation_change_action.dart
git commit -m "feat(comp): confirm handler (change -> event -> draft notice -> workflow)"
```

---

### Task 11: Workflow detail — "Apply now" + "Cancel" for a scheduled change

**Files:**
- Modify: `lib/features/workflows/workflow_detail_screen.dart`

**Interfaces:**
- Consumes: `CompensationChangeRepository.applyDue` / `.cancel` (Task 4), `workflowByIdProvider` context.
- Produces: for a `SALARY_CHANGE`/`ROLE_CHANGE` workflow whose linked change is still `SCHEDULED`, two actions: **Apply now** (calls `applyDue(companyId, asOf: DateTime.now())` scoped so it materializes this employee's due change) and **Cancel change** (calls `.cancel(changeId)` + `workflowRepository.cancelInstance`).

- [ ] **Step 1: Add the actions**

In `workflow_detail_screen.dart`, when `workflow.workflowType` is `SALARY_CHANGE` or `ROLE_CHANGE`:
- Look up the linked change: query `compensation_changes` by `workflow_id == workflow.id` (add `CompensationChangeRepository.byWorkflowId(String)` returning `CompensationChange?`, following the existing repo query style).
- If its `status == 'SCHEDULED'`, render an **"Apply now"** `FilledButton` and a **"Cancel change"** `TextButton` in the detail header area (near the existing "Generate now" action at line ~277).
  - Apply now → `await ref.read(compensationChangeRepositoryProvider).applyDue(companyId: workflow.companyId, asOf: DateTime.now());` then invalidate `workflowByIdProvider(workflow.id)`, `employeeByIdProvider(workflow.employeeId)`, `pendingCompensationChangesProvider(workflow.employeeId)`; snackbar "Change applied."
  - Cancel change → confirm dialog → `repo.cancel(changeId)` + `workflowRepository.cancelInstance(instanceId: workflow.id, cancelReason: 'Compensation change cancelled')`; invalidate the same providers; snackbar "Change cancelled."
- If `status != 'SCHEDULED'`, show a read-only chip ("Applied {date}" / "Cancelled").

Add `Future<CompensationChange?> byWorkflowId(String workflowId)` to `CompensationChangeRepository`:

```dart
  Future<CompensationChange?> byWorkflowId(String workflowId) async {
    final row = await _client
        .from('compensation_changes')
        .select('*')
        .eq('workflow_id', workflowId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    return row == null ? null : CompensationChange.fromRow(row);
  }
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/features/workflows/workflow_detail_screen.dart lib/data/repositories/compensation_change_repository.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/workflows/workflow_detail_screen.dart lib/data/repositories/compensation_change_repository.dart
git commit -m "feat(comp): apply-now / cancel actions on comp-change workflows"
```

---

### Task 12: Full verification + end-to-end smoke

**Files:** none (verification only).

- [ ] **Step 1: Whole suite + analyze**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all tests green (no regressions in engine/documents/widgets suites).

- [ ] **Step 2: Launch the app and drive the flow (use the `run` skill)**

Run the app: `flutter run -d linux --dart-define-from-file=env/prod.json` (memory: run-command). Then:
1. Open an employee → **Role** tab → "Adjust Compensation / Change Role".
2. Do a **Salary Increase** effective next month → confirm. Verify: a "Pending changes" strip appears; a `SALARY_CHANGE` workflow shows in `/workflows`; opening it shows a "Generate Notice of Salary Adjustment" step + an "Apply now" / "Cancel change" control.
3. Click **Generate now** → the notice renders with the new salary, old salary, and effective date.
4. Repeat for a **Promotion** (pick a different role) → verify `ROLE_CHANGE` workflow + "Notice of Promotion" body naming both roles.
5. Confirm the employee's stored role does **not** change until the effective date (future-dated) — the Role tab still shows the current role, with the pending strip noting the upcoming move.

- [ ] **Step 3: Final commit (if any doc/tidy changes)**

```bash
git add -A
git commit -m "chore(comp): verification pass for compensation & role change workflow"
```

---

## Self-Review

**Spec coverage:**
- `compensation_changes` table + effective-dated truth → Task 1, 2.
- Payroll resolves effective comp, scorecard fallback, no cron → Task 3, 8.
- Future-dated auto-applies; materialize-on-compute + manual "Apply now" → Task 4 (`applyDue`), 8, 11.
- Confirm mirrors separation (change → event → draft doc → workflow → Generate now) → Task 10, using seeder Task 7; render path is the existing `/documents/generate/:templateId`.
- Five change types; notice modes lateral + demotion → Task 5, 6.
- Entry point on Role tab + pending strip → Task 9.
- New document_type codes (varchar, no migration) → Task 7 helper + Task 10 draft insert.
- Tests (resolver, seeder, validation, payroll gating) → Tasks 3, 5, 7, 8.

**Deviations from the spec (deliberate, lower-risk):**
1. **No enum migration for `document_type` or `employment_event_type`** — `document_type` is `varchar(50)`, and `employment_event_type` already contains `SALARY_CHANGE/ROLE_CHANGE/DEPARTMENT_TRANSFER/PROMOTION/DEMOTION`. The migration is just the one new table. (Spec assumed enum additions might be needed; they aren't.)
2. **`compensation_changes.change_type`/`status` use `text` + `check`** rather than new Postgres enum types, matching the recent `job_listings.status` idiom.
3. **Lateral transfer maps to the `DEPARTMENT_TRANSFER` employment-event type** (closest existing value) while its workflow is `ROLE_CHANGE` and its notice is "Notice of Lateral Transfer".

**Placeholder scan:** No TBD/TODO. The one intentionally deferred detail is the exact in-scope variable name for the run's period-end in `compute_service` (Task 8 Steps 3–4) and the block field names in Task 6 — both call out "confirm the real name in the file; do not invent," because they depend on code the implementer will have open. Every code block is otherwise complete.

**Type consistency:** `CompensationChange` fields, `buildCompensationChangeInsert` params, `seedCompensationChangeWorkflow` signature, and `compensationDocumentType`/`compensationDocTitle` names are used identically across Tasks 2/4/7/10/11. `SalaryAdjustmentType` gains exactly `lateral`, `demotion` and is referenced consistently in Tasks 5/6.
