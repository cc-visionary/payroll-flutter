# Compensation History + Hard Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a per-employee compensation history, and let HR hard-delete a mistaken compensation change together with its workflow, its notice document, and its timeline event — refusing once released payroll has paid at that rate.

**Architecture:** A prerequisite fix makes one compensation change own exactly one `employee_documents` row (today "Generate now" mints a second, unlinked ISSUED row, so a cascade delete cannot find the real notice). Delete then runs as a single `SECURITY INVOKER` Postgres RPC so the guard, the scorecard-pointer revert, and a four-table cascade are atomic. History is a new section on the employee's Role tab reading the existing `compensationChangesByEmployeeProvider`.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase Postgres (plpgsql RPC), Dart `decimal`, `flutter_test`.

## Global Constraints

- Package import prefix for tests is `package:payroll_flutter/…`; files under `lib/` use **relative** imports. Run tests with `flutter test <path>`.
- Repo gates on `flutter analyze` (**0 errors**). It has ~189 pre-existing info/warning lints (baseline: 0 errors, 20 warnings, 169 infos) — **add zero new ones**. Do NOT run `dart format`; match each file's surrounding style.
- Money is `Decimal` (`package:decimal/decimal.dart`), never `double`. Render with `Money.fmtPhp` from `lib/core/money.dart`.
- Chips must be theme-aware: use `StatusChip` / `StatusTone` from `lib/app/status_colors.dart`. **No hardcoded light-mode hex** — CLAUDE.md mandates system-driven light+dark.
- Change statuses are exactly `'SCHEDULED' | 'APPLIED' | 'CANCELLED'`.
- **Delete is blocked** when any `payroll_runs` row with `status = 'RELEASED'` and `period_end >= effective_date` has a `payslips` row for that employee. The guard lives in the RPC, not in Dart.
- **The RPC must not raise on a missing workflow, document, or event.** `workflow_id`/`document_id` are null when the confirm handler could not resolve an actor. `delete … where id = null` deletes zero rows — that is intended.
- FK order is forced: `compensation_changes` → `workflow_instances` (steps cascade) → `employee_documents` → `employment_events`. `workflow_steps.generated_document_id` and `employee_documents.generated_from_event_id` block any other order.
- RLS already permits DELETE on all four tables via existing `for all` policies for `SUPER_ADMIN/ADMIN/HR`. **No RLS migration.**
- Multiple Claude sessions share this working dir — implement on an isolated git worktree/branch.

---

### Task 1: `buildUpdatePayload` marks the document ISSUED

**Files:**
- Modify: `lib/data/repositories/employee_document_repository.dart:53-68`
- Test: `test/data/repositories/employee_document_payload_test.dart` (existing `buildUpdatePayload` group at `:57`)

**Interfaces:**
- Produces: `buildUpdatePayload({required String fileName, required Map<String, dynamic> generationOptions, required DateTime updatedAt, String? templateId})` now includes `'status': 'ISSUED'`.

Why: the update path is taken when `saveGenerated` receives a `sessionRecordId`. Task 2 makes that id the pre-inserted **DRAFT** row, so the update must flip it to `ISSUED`. For the pre-existing in-session re-save case the row is already `ISSUED`, so this is idempotent.

- [ ] **Step 1: Write the failing test**

Append inside the existing `group('buildUpdatePayload', …)` in `test/data/repositories/employee_document_payload_test.dart`:

```dart
    test('marks the row ISSUED so a DRAFT placeholder becomes the real notice', () {
      final payload = buildUpdatePayload(
        fileName: 'notice.pdf',
        generationOptions: const {'foo': 'bar'},
        updatedAt: DateTime.utc(2026, 7, 10),
        templateId: 'salary_adjustment',
      );
      expect(payload['status'], 'ISSUED');
      expect(payload['file_name'], 'notice.pdf');
      expect(payload['updated_at'], DateTime.utc(2026, 7, 10).toIso8601String());
      final opts = payload['generation_options'] as Map<String, dynamic>;
      expect(opts['__template_id'], 'salary_adjustment');
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/employee_document_payload_test.dart`
Expected: FAIL — `Expected: 'ISSUED'  Actual: <null>`.

- [ ] **Step 3: Add the status**

In `lib/data/repositories/employee_document_repository.dart`, change the returned map of `buildUpdatePayload` to:

```dart
  return {
    'file_name': fileName,
    'generation_options': opts,
    'updated_at': updatedAt.toIso8601String(),
    // The update path is also how a pre-inserted DRAFT placeholder becomes the
    // issued notice (see workflow_detail_screen's "Generate now"). Idempotent
    // for the in-session re-save case, where the row is already ISSUED.
    'status': 'ISSUED',
  };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/employee_document_payload_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Verify analyze + commit**

Run: `flutter analyze lib/data/repositories/employee_document_repository.dart`
Expected: `No issues found!`

```bash
git add lib/data/repositories/employee_document_repository.dart test/data/repositories/employee_document_payload_test.dart
git commit -m "fix(docs): saving a generated document marks it ISSUED"
```

---

### Task 2: Thread the DRAFT's documentId through the generate route

**Files:**
- Create: `lib/features/workflows/generate_url.dart`
- Create: `test/features/workflows/generate_url_test.dart`
- Modify: `lib/features/workflows/workflow_detail_screen.dart` (`_generateNow`, the URL build at ~`:465-468`)
- Modify: `lib/app/router.dart:267-274`
- Modify: `lib/features/documents/generate_screen.dart` (constructor + `_sessionRecordId` seeding at `:195`)

**Interfaces:**
- Consumes: `buildUpdatePayload` marking `ISSUED` (Task 1).
- Produces:
  - `String buildGenerateDocumentUrl({required String templateId, required String employeeId, String? changeId, String? documentId})` — a pure URL builder.
  - `GenerateScreen` gains `final String? documentId;` and seeds `_sessionRecordId = widget.documentId` in `initState`.

Why: `_generateNow` already holds `step.generatedDocumentId` (the DRAFT row) and discards it. Passing it makes `saveGenerated` take its update path, so the DRAFT **becomes** the issued notice instead of a second row being minted. This also stops separation notices from orphaning.

- [ ] **Step 1: Write the failing test**

Create `test/features/workflows/generate_url_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workflows/generate_url.dart';

void main() {
  group('buildGenerateDocumentUrl', () {
    test('employee only (separation-style step with no linked ids)', () {
      expect(
        buildGenerateDocumentUrl(templateId: 'quitclaim', employeeId: 'E1'),
        '/documents/generate/quitclaim?employeeId=E1',
      );
    });

    test('appends documentId when the step has a pre-inserted DRAFT', () {
      expect(
        buildGenerateDocumentUrl(
          templateId: 'quitclaim',
          employeeId: 'E1',
          documentId: 'D1',
        ),
        '/documents/generate/quitclaim?employeeId=E1&documentId=D1',
      );
    });

    test('appends changeId for compensation workflows', () {
      expect(
        buildGenerateDocumentUrl(
          templateId: 'salary_adjustment',
          employeeId: 'E1',
          changeId: 'C1',
        ),
        '/documents/generate/salary_adjustment?employeeId=E1&changeId=C1',
      );
    });

    test('appends both, changeId before documentId', () {
      expect(
        buildGenerateDocumentUrl(
          templateId: 'salary_adjustment',
          employeeId: 'E1',
          changeId: 'C1',
          documentId: 'D1',
        ),
        '/documents/generate/salary_adjustment?employeeId=E1&changeId=C1&documentId=D1',
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/workflows/generate_url_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../generate_url.dart'`.

- [ ] **Step 3: Write the pure builder**

Create `lib/features/workflows/generate_url.dart`:

```dart
/// Builds the `/documents/generate/:templateId` URL for a workflow's
/// DOCUMENT_GENERATION step.
///
/// `changeId` makes the salary-adjustment notice render THIS compensation
/// change rather than the newest one. `documentId` is the step's pre-inserted
/// DRAFT `employee_documents` row — passing it makes the generate screen UPDATE
/// that row (flipping it to ISSUED) instead of inserting a second, unlinked
/// document. Both are omitted when the step has no such id.
String buildGenerateDocumentUrl({
  required String templateId,
  required String employeeId,
  String? changeId,
  String? documentId,
}) {
  final buffer = StringBuffer('/documents/generate/$templateId?employeeId=$employeeId');
  if (changeId != null) buffer.write('&changeId=$changeId');
  if (documentId != null) buffer.write('&documentId=$documentId');
  return buffer.toString();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/workflows/generate_url_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Use it in `_generateNow`**

In `lib/features/workflows/workflow_detail_screen.dart`, add `import 'generate_url.dart';` and replace the URL construction (the `final url = changeId == null ? … : …;` block, ~`:465-468`) with:

```dart
    final url = buildGenerateDocumentUrl(
      templateId: templateId,
      employeeId: workflow.employeeId,
      changeId: changeId,
      documentId: step.generatedDocumentId,
    );
    context.go(url);
```

Leave the existing `markStepInProgress`, the `compensationChangeByWorkflowProvider` lookup, and the `if (!context.mounted) return;` guard exactly as they are.

- [ ] **Step 6: Parse `documentId` in the router**

In `lib/app/router.dart:267-274`, add the new query parameter:

```dart
          GoRoute(
            path: '/documents/generate/:templateId',
            builder: (c, s) => GenerateScreen(
              templateId: s.pathParameters['templateId']!,
              employeeId: s.uri.queryParameters['employeeId'],
              compensationChangeId: s.uri.queryParameters['changeId'],
              documentId: s.uri.queryParameters['documentId'],
            ),
          ),
```

- [ ] **Step 7: Seed `_sessionRecordId` in `GenerateScreen`**

In `lib/features/documents/generate_screen.dart`:

1. Add the field + constructor param to the `GenerateScreen` widget (mirror how `compensationChangeId` at `:126` is declared):

```dart
  /// The workflow step's pre-inserted DRAFT `employee_documents` row. When set,
  /// saving UPDATES that row (marking it ISSUED) instead of inserting a second
  /// document. Null for ad-hoc generation from the Documents screen.
  final String? documentId;
```
and `this.documentId,` in the constructor.

2. In the state class, seed the session record id so the first save takes the update path. `_sessionRecordId` is declared at `:195`; add to `initState` (call `super.initState()` first, and keep any existing body):

```dart
  @override
  void initState() {
    super.initState();
    _sessionRecordId = widget.documentId;
    // ...existing initState body unchanged...
  }
```

If the state class has no `initState`, add one containing exactly those two lines plus the existing behaviour.

- [ ] **Step 7b: Reset `_sessionRecordId` when the employee changes (fixes a pre-existing hazard)**

`_sessionRecordId` is currently only ever *assigned* (`generate_screen.dart:856`, after a save) and never cleared. So saving for employee A and then switching to employee B via the picker would make the next save **UPDATE A's document row** with B's content — `saveGenerated`'s update path keys purely on `sessionRecordId` and never rewrites `employee_id`. Seeding the id from the route (Step 7) makes that reachable from the very first save.

At the top of `_onPickerEmployeeChanged(String newEmployeeId)` (around `:487`), before any autofill work, add:

```dart
    // The session record belongs to the PREVIOUS employee. Switching employees
    // must mint a fresh document row, never overwrite theirs.
    _sessionRecordId = null;
```

- [ ] **Step 8: Verify analyze + suites**

Run: `flutter analyze lib/features/workflows/ lib/features/documents/generate_screen.dart lib/app/router.dart`
Expected: no NEW issues (the payroll tree has pre-existing infos; these files must add none).

Run: `flutter test test/features/documents/ test/features/workflows/ test/data/repositories/`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/features/workflows/generate_url.dart lib/features/workflows/workflow_detail_screen.dart lib/app/router.dart lib/features/documents/generate_screen.dart test/features/workflows/generate_url_test.dart
git commit -m "fix(docs): Generate now updates the DRAFT notice in place"
```

---

### Task 3: Migration — `delete_compensation_change(uuid)` RPC

**Files:**
- Create: `supabase/migrations/20260710000001_delete_compensation_change.sql`

**Interfaces:**
- Produces: Postgres function `delete_compensation_change(p_change_id uuid) returns void`, `security invoker`, granted to `authenticated`. Raises `CHANGE_NOT_FOUND` or `RELEASED_PAYROLL` (with the offending run's period as `hint`). Task 4 calls it via `.rpc(...)`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260710000001_delete_compensation_change.sql`:

```sql
-- 20260710000001_delete_compensation_change.sql
--
-- Hard-deletes a compensation change together with everything it spawned:
-- its workflow (steps cascade), its notice document, and its timeline event.
-- Reverts employees.role_scorecard_id when an APPLIED role change is removed.
--
-- Refuses when a RELEASED payroll run has already paid at that rate: the money
-- went out, so erasing the record would leave the payslip unexplainable. Use
-- "Cancel change" for that case.
--
-- SECURITY INVOKER (the default): RLS still applies, so only SUPER_ADMIN/ADMIN/HR
-- can perform the deletes. Everything runs in one transaction, so the guard can
-- never leave partial state.
--
-- FK order is forced:
--   compensation_changes  (points outward at workflow + document)
--   -> workflow_instances (workflow_steps cascade, releasing generated_document_id)
--   -> employee_documents (generated_from_event_id still references the event)
--   -> employment_events
-- Null workflow_id / document_id / event id are EXPECTED (the confirm handler
-- skips the workflow + notice when it cannot resolve an actor); `where id = null`
-- deletes zero rows, which is intended -- do not raise on them.

create or replace function delete_compensation_change(p_change_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_employee_id    uuid;
  v_effective_date date;
  v_status         text;
  v_prev_scorecard uuid;
  v_new_scorecard  uuid;
  v_workflow_id    uuid;
  v_document_id    uuid;
  v_event_id       uuid;
  v_released_run   text;
begin
  select employee_id, effective_date, status,
         prev_scorecard_id, new_scorecard_id, workflow_id, document_id
    into v_employee_id, v_effective_date, v_status,
         v_prev_scorecard, v_new_scorecard, v_workflow_id, v_document_id
  from compensation_changes
  where id = p_change_id and deleted_at is null;

  if not found then
    raise exception 'CHANGE_NOT_FOUND';
  end if;

  -- Guard: has released payroll already paid at this rate?
  select pr.period_start::text || ' to ' || pr.period_end::text
    into v_released_run
  from payslips ps
  join payroll_runs pr on pr.id = ps.payroll_run_id
  where ps.employee_id = v_employee_id
    and pr.status = 'RELEASED'
    and pr.period_end >= v_effective_date
  limit 1;

  if v_released_run is not null then
    raise exception 'RELEASED_PAYROLL' using hint = v_released_run;
  end if;

  -- Revert the scorecard pointer only when applyDue actually moved it, and the
  -- employee is still sitting on the role this change assigned.
  if v_status = 'APPLIED'
     and v_new_scorecard is not null
     and v_new_scorecard is distinct from v_prev_scorecard
     and (select role_scorecard_id from employees where id = v_employee_id) = v_new_scorecard
  then
    update employees set role_scorecard_id = v_prev_scorecard where id = v_employee_id;
  end if;

  select id into v_event_id
  from employment_events
  where employee_id = v_employee_id
    and payload->>'change_id' = p_change_id::text
  limit 1;

  delete from compensation_changes where id = p_change_id;
  delete from workflow_instances  where id = v_workflow_id;

  update employee_documents
     set supersedes_document_id = null
   where supersedes_document_id = v_document_id;

  delete from employee_documents where id = v_document_id;
  delete from employment_events  where id = v_event_id;
end;
$$;

grant execute on function delete_compensation_change(uuid) to authenticated;
```

- [ ] **Step 2: Apply it to a scratch database and prove the guard blocks**

Prefer the local Supabase stack: `supabase start` then `supabase db reset`.
Expected: completes without error and lists `20260710000001_delete_compensation_change.sql`.

If the local stack is unavailable (a port conflict has happened before), create a scratch database and apply the full migration chain in order, then run the assertions below. Do NOT run any of this against prod.

```bash
psql "$SCRATCH_URL" -c "select delete_compensation_change('00000000-0000-0000-0000-000000000000'::uuid);"
```
Expected: `ERROR:  CHANGE_NOT_FOUND`

- [ ] **Step 3: Prove the RELEASED guard and the cascade**

With a seeded employee, a `RELEASED` run whose `period_end >= effective_date` and a payslip for that employee:

```sql
select delete_compensation_change('<change-id>');
-- Expected: ERROR:  RELEASED_PAYROLL   HINT:  2026-07-01 to 2026-07-31
select count(*) from compensation_changes where id = '<change-id>';  -- expect 1 (nothing deleted)
```

Then flip the run to `REVIEW` and re-run against an **APPLIED role change**:

```sql
select delete_compensation_change('<change-id>');
select count(*) from compensation_changes where id = '<change-id>';            -- 0
select count(*) from workflow_instances  where id = '<workflow-id>';           -- 0
select count(*) from workflow_steps      where workflow_instance_id = '<workflow-id>'; -- 0 (cascade)
select count(*) from employee_documents  where id = '<document-id>';           -- 0
select count(*) from employment_events   where id = '<event-id>';              -- 0
select role_scorecard_id from employees  where id = '<employee-id>';           -- = prev_scorecard_id
```

- [ ] **Step 4: Prove the pointer revert is conditional**

```sql
-- pay-only change (new_scorecard_id = prev_scorecard_id): pointer must NOT move
-- SCHEDULED role change (never applied):                  pointer must NOT move
```
Run `delete_compensation_change` for each and assert `employees.role_scorecard_id` is unchanged.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260710000001_delete_compensation_change.sql
git commit -m "feat(comp): atomic delete_compensation_change RPC with released-payroll guard"
```

---

### Task 4: `deleteChange` + `ReleasedPayrollException`

**Files:**
- Modify: `lib/data/repositories/compensation_change_repository.dart`
- Test: `test/data/repositories/released_payroll_exception_test.dart`

**Interfaces:**
- Consumes: the RPC from Task 3.
- Produces:
  - `class ReleasedPayrollException implements Exception { final String? runPeriod; }`
  - `ReleasedPayrollException? releasedPayrollFrom(Object error)` — pure mapper; returns non-null when the error is the RPC's `RELEASED_PAYROLL`.
  - `Future<void> deleteChange(String changeId)` on `CompensationChangeRepository` — calls `.rpc('delete_compensation_change', params: {'p_change_id': changeId})` and rethrows a `ReleasedPayrollException` when the mapper matches.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/released_payroll_exception_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/compensation_change_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('releasedPayrollFrom', () {
    test('maps the RPC guard error, carrying the run period from the hint', () {
      final err = PostgrestException(
        message: 'RELEASED_PAYROLL',
        hint: '2026-07-01 to 2026-07-31',
      );
      final mapped = releasedPayrollFrom(err);
      expect(mapped, isNotNull);
      expect(mapped!.runPeriod, '2026-07-01 to 2026-07-31');
    });

    test('returns null for any other Postgrest error', () {
      final err = PostgrestException(message: 'CHANGE_NOT_FOUND');
      expect(releasedPayrollFrom(err), isNull);
    });

    test('returns null for a non-Postgrest error', () {
      expect(releasedPayrollFrom(StateError('boom')), isNull);
    });
  });
}
```

> Before running, confirm `PostgrestException`'s constructor parameter names against the installed `supabase_flutter` (`message`, `hint` are named). Adjust the fixture to the real signature — do not invent parameters.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/released_payroll_exception_test.dart`
Expected: FAIL — `releasedPayrollFrom` is not defined.

- [ ] **Step 3: Implement the exception, mapper, and repository method**

Append to `lib/data/repositories/compensation_change_repository.dart` (top-level, alongside `buildCompensationChangeInsert`):

```dart
/// Thrown when `delete_compensation_change` refuses because a RELEASED payroll
/// run already paid at this rate. The change must be cancelled, not erased.
class ReleasedPayrollException implements Exception {
  /// The offending run's period, e.g. `2026-07-01 to 2026-07-31`. Null when the
  /// RPC did not supply a hint.
  final String? runPeriod;
  const ReleasedPayrollException(this.runPeriod);

  @override
  String toString() => 'ReleasedPayrollException($runPeriod)';
}

/// Pure mapper: recognises the RPC's `RELEASED_PAYROLL` guard error.
/// Returns null for every other error so callers can rethrow unchanged.
ReleasedPayrollException? releasedPayrollFrom(Object error) {
  if (error is PostgrestException && error.message.contains('RELEASED_PAYROLL')) {
    return ReleasedPayrollException(error.hint?.toString());
  }
  return null;
}
```

Add to the `CompensationChangeRepository` class:

```dart
  /// Hard-deletes the change plus its workflow, notice document, and timeline
  /// event, atomically, via the `delete_compensation_change` RPC. Reverts the
  /// employee's scorecard pointer when an APPLIED role change is removed.
  ///
  /// Throws [ReleasedPayrollException] when released payroll already paid at
  /// this rate — nothing is deleted in that case.
  Future<void> deleteChange(String changeId) async {
    try {
      await _client.rpc(
        'delete_compensation_change',
        params: {'p_change_id': changeId},
      );
    } catch (e) {
      final released = releasedPayrollFrom(e);
      if (released != null) throw released;
      rethrow;
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/released_payroll_exception_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify analyze + commit**

Run: `flutter analyze lib/data/repositories/compensation_change_repository.dart`
Expected: `No issues found!`

```bash
git add lib/data/repositories/compensation_change_repository.dart test/data/repositories/released_payroll_exception_test.dart
git commit -m "feat(comp): deleteChange RPC call + ReleasedPayrollException"
```

---

### Task 5: Compensation history section

**Files:**
- Create: `lib/features/employees/profile/widgets/compensation_history_section.dart`
- Modify: `lib/features/employees/profile/tabs/role_tab.dart` (mount it under Current Role)
- Test: `test/features/employees/compensation_history_section_test.dart`

**Interfaces:**
- Consumes: `compensationChangesByEmployeeProvider(employeeId)` (existing; `listByEmployee` already returns non-deleted rows newest-first by `effective_date`), `compensationChangeTypeLabel(String)` from `compensation_change_dialog.dart:47`, `StatusChip` / `StatusTone` from `lib/app/status_colors.dart`, `Money.fmtPhp`.
- Produces: `class CompensationHistorySection extends ConsumerWidget` taking `{required Employee employee, required bool canManage}`.
- Produces: `StatusTone statusToneFor(String status)` — pure: `SCHEDULED` → `warning`, `APPLIED` → `success`, `CANCELLED` → `danger`.

- [ ] **Step 1: Write the failing test**

Create `test/features/employees/compensation_history_section_test.dart`. Test the pure tone mapper directly; that is the logic worth pinning.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/app/status_colors.dart';
import 'package:payroll_flutter/features/employees/profile/widgets/compensation_history_section.dart';

void main() {
  group('statusToneFor', () {
    test('SCHEDULED is a warning tone', () {
      expect(statusToneFor('SCHEDULED'), StatusTone.warning);
    });
    test('APPLIED is a success tone', () {
      expect(statusToneFor('APPLIED'), StatusTone.success);
    });
    test('CANCELLED is a danger tone', () {
      expect(statusToneFor('CANCELLED'), StatusTone.danger);
    });
  });
}
```

> Confirm the exact `StatusTone` enum member names in `lib/app/status_colors.dart:10` before running (they are used elsewhere as `StatusTone.warning` / `.success` / `.danger`). If a name differs, use the real one — do not invent members.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/employees/compensation_history_section_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Build the section**

Create `lib/features/employees/profile/widgets/compensation_history_section.dart`.

Requirements:
- `StatusTone statusToneFor(String status)` as a top-level pure function with the mapping above (default arm: `StatusTone.warning`).
- `CompensationHistorySection` is a `ConsumerWidget`. It watches `compensationChangesByEmployeeProvider(employee.id)`.
- `loading` → a `SizedBox.shrink()`. `error` → a muted one-line message.
- Empty list → an empty-state line: `'No compensation changes recorded. Pay comes from the role scorecard.'`
- Otherwise one row per change, newest first (the provider already orders it), each showing:
  - `compensationChangeTypeLabel(change.changeType)`
  - `'${Money.fmtPhp(change.prevBaseSalary ?? Decimal.zero)} → ${Money.fmtPhp(change.newBaseSalary ?? Decimal.zero)}'` — render `—` in place of a null side rather than `₱0.00`.
  - `'Effective ${change.effectiveDate.toIso8601String().substring(0, 10)}'`
  - `StatusChip(label: <Title-cased status>, tone: statusToneFor(change.status))`
  - a `TextButton` **Workflow** → `context.go('/workflows/${change.workflowId}')`, rendered only when `change.workflowId != null`
  - a `TextButton` **Notice** → `context.go('/documents/view/${change.documentId}')`, rendered only when `change.documentId != null`
  - a delete `IconButton` (`Icons.delete_outline`), rendered only when `canManage`. Wire it in Task 6; for now give it `onPressed: null` and a `// wired in Task 6` comment.
- Wrap the whole thing in the same `_Section`-style card used by the Role tab. Use **theme-derived colours only** (no hardcoded hex).

- [ ] **Step 4: Mount it on the Role tab**

In `lib/features/employees/profile/tabs/role_tab.dart`, inside `_RoleDetail.build`'s `ListView` children, immediately **after** the `_Section(title: 'Current Role', …)` widget, add:

```dart
        const SizedBox(height: 16),
        CompensationHistorySection(employee: employee, canManage: canManage),
```

Add `import '../widgets/compensation_history_section.dart';` to the import block.

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/features/employees/compensation_history_section_test.dart && flutter analyze lib/features/employees/profile/`
Expected: PASS (3 tests), then no NEW analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/employees/profile/widgets/compensation_history_section.dart lib/features/employees/profile/tabs/role_tab.dart test/features/employees/compensation_history_section_test.dart
git commit -m "feat(comp): compensation history section on the Role tab"
```

---

### Task 6: Delete action — confirm dialog, RPC call, invalidations

**Files:**
- Create: `lib/features/employees/profile/widgets/delete_compensation_change_action.dart`
- Modify: `lib/features/employees/profile/widgets/compensation_history_section.dart` (wire the delete button)

**Interfaces:**
- Consumes: `CompensationChangeRepository.deleteChange(String)` and `ReleasedPayrollException` (Task 4); `compensationChangeTypeLabel` (existing).
- Produces: `Future<void> runDeleteCompensationChange({required WidgetRef ref, required BuildContext context, required Employee employee, required CompensationChange change})`.

- [ ] **Step 1: Implement the action**

Create `lib/features/employees/profile/widgets/delete_compensation_change_action.dart`.

Sequence (mirror the messenger/container/try-catch pattern of `compensation_change_action.dart`):

```dart
// 0. final messenger = ScaffoldMessenger.of(context);
//    final container = ProviderScope.containerOf(context, listen: false);
//
// 1. Build the confirmation body. Always name what dies:
//      'This permanently deletes the {label}, its workflow, its notice document,
//       and its timeline entry. This cannot be undone.'
//    When change.status == 'APPLIED' && change.isRoleChange, append:
//      '\n\n{employee.fullName} will be moved back to their previous role.'
//    Show an AlertDialog with Cancel / Delete (destructive styling).
//    if (confirmed != true) return;
//
// 2. try { await container.read(compensationChangeRepositoryProvider)
//              .deleteChange(change.id); }
//    on ReleasedPayrollException catch (e) {
//      messenger.showSnackBar(SnackBar(content: Text(
//        'Cannot delete: released payroll (${e.runPeriod ?? "a released run"}) '
//        'already paid at this rate. Cancel the change instead.')));
//      return;
//    } catch (e) {
//      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
//      return;
//    }
//
// 3. Invalidate (same set the confirm handler uses, plus the workflow lookup):
//      compensationChangesByEmployeeProvider(employee.id)
//      pendingCompensationChangesProvider(employee.id)
//      employeeByIdProvider(employee.id)
//      employeeListProvider
//      timelineProvider(employee.id)
//      employeeDocumentsProvider(employee.id)
//      workflowListProvider
//      compensationChangeByWorkflowProvider(change.workflowId!)  // only when non-null
//
// 4. if (context.mounted) messenger.showSnackBar(
//      SnackBar(content: Text('${compensationChangeTypeLabel(change.changeType)} deleted.')));
```

Guard every post-await use of `context` with `context.mounted`. Use the captured `container` (not `ref`) for post-await provider reads and invalidations.

- [ ] **Step 2: Wire the delete button**

In `compensation_history_section.dart`, replace the placeholder `onPressed: null` with:

```dart
                        onPressed: () => runDeleteCompensationChange(
                          ref: ref,
                          context: context,
                          employee: employee,
                          change: change,
                        ),
```

Add the import for the action file.

- [ ] **Step 3: Verify analyze + the employees suite**

Run: `flutter analyze lib/features/employees/profile/ && flutter test test/features/employees/`
Expected: no NEW analyzer issues; all employees tests PASS.

There is no unit test for this handler — it is a live-Supabase call, and the repo's convention is that such code is not unit-tested. Its correctness rests on Task 3's SQL assertions and Task 4's mapper test.

- [ ] **Step 4: Commit**

```bash
git add lib/features/employees/profile/widgets/delete_compensation_change_action.dart lib/features/employees/profile/widgets/compensation_history_section.dart
git commit -m "feat(comp): delete a compensation change and everything it spawned"
```

---

### Task 7: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Whole suite + analyze**

Run: `flutter analyze`
Expected: **0 errors**; the info/warning counts must not exceed the baseline (169 infos, 20 warnings). Report the severity breakdown.

Run: `flutter test`
Expected: all pass, 0 failures. Baseline before this plan is 632 passed / 1 skipped; this plan adds ~14 tests.

- [ ] **Step 2: Drive the flow (use the `run` skill)**

Launch: `flutter run -d linux --dart-define-from-file=env/prod.json`

The `compensation_changes` migration is already applied to prod; the new RPC migration from Task 3 must be applied before delete will work.

1. Employee → Role & Responsibilities → **Adjust Compensation** → salary increase, effective next month → confirm.
2. The **Compensation history** section shows the change with a `Scheduled` chip and links to its workflow.
3. Open the workflow → **Generate now** → save. Confirm in the employee's Documents tab that there is exactly **one** notice (not a DRAFT plus an ISSUED duplicate).
4. Back on the Role tab → delete the change → confirm. The history row, the workflow (`/workflows`), the notice (Documents tab), and the Timeline entry all disappear.
5. Repeat with a change whose effective date falls inside a **RELEASED** run: delete must refuse and name the run period.

- [ ] **Step 3: Commit any tidy-ups**

```bash
git add -A
git commit -m "chore(comp): verification pass for history + delete"
```

---

## Self-Review

**Spec coverage:**
- Phase 1 document linkage → Tasks 1, 2.
- RPC with guard, conditional pointer revert, FK-ordered cascade, null-safe deletes → Task 3.
- `deleteChange` + `ReleasedPayrollException` → Task 4.
- History section on the Role tab (status chips, workflow/notice links, `canManage` gating, empty state) → Task 5.
- Confirm dialog naming what dies + the role-revert warning, invalidations → Task 6.
- Testing + deploy notes → Tasks 3, 7.
- Out-of-scope items (completing `cancel(...)`, undo/restore, org-wide reporting, baseline backfill) are intentionally untouched.

**Placeholder scan:** No TBD/TODO. Task 6's body is deliberately given as a precise commented sequence rather than final Dart, because it must mirror `compensation_change_action.dart`'s messenger/container idiom, which the implementer will have open; every value, provider name, and message string it needs is stated. Three steps instruct the implementer to **confirm real names** (`PostgrestException` params, `StatusTone` members, `initState` presence) rather than invent them.

**Type consistency:** `buildGenerateDocumentUrl({templateId, employeeId, changeId, documentId})` (Task 2) matches its call site. `GenerateScreen.documentId` is added in Task 2 and consumed by the router in the same task. `deleteChange(String)`, `ReleasedPayrollException.runPeriod`, and `releasedPayrollFrom(Object)` (Task 4) are used identically in Task 6. `statusToneFor(String)` is defined and tested in Task 5. `CompensationChange.isRoleChange` already exists on the model and is used in Task 6's warning condition.

**Found while planning (added to Task 2, Step 7b):** `_sessionRecordId` is never reset when the generate screen's employee picker changes employee, so a save after switching would overwrite the previous employee's document row. Pre-existing, but seeding the id from the route makes it reachable on the first save. The plan now clears it in `_onPickerEmployeeChanged`.

**Ordering note:** Task 2 depends on Task 1 (the update path must set `ISSUED` before we start routing DRAFTs into it). Task 4 depends on Task 3's RPC existing. Task 6 depends on Tasks 4 and 5. Do not reorder.
