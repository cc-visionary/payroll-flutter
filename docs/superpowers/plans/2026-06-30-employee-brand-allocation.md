# Employee Brand Allocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Dispatch Flutter/Dart implementer subagents as **mobile-app-builder**.

**Goal:** Make the employee's brand allocation (`employees.hiring_entity_id`) settable on the Edit Employee form — required, either derived from the role scorecard or set manually — and actually persisted (it never was), so the employee's company stops showing missing/null.

**Architecture:** Add an optional company column to `role_scorecards` so a scorecard can define a default brand. Add a required "Company (brand)" control to the employee form with a Derive/Manual toggle; derive reads the selected scorecard's entity (resolved synchronously from the already-loaded scorecard list), manual uses an explicit hiring-entity dropdown. Persist via a new `hiringEntityId` param on `EmployeeRepository.upsert`. Carry the brand over on applicant→employee conversion.

**Tech Stack:** Flutter (Material 3, Riverpod), Supabase Postgres.

## Global Constraints

- Package name for test imports: **`payroll_flutter`** (`package:payroll_flutter/...`).
- Brand control is **HR/Admin editable only** — gate with `profile.isHrOrAdmin` (mirrors `_buildStatutoryEntityField`).
- Brand is **required at the form layer** (save blocked until it resolves to non-null). The DB column `employees.hiring_entity_id` stays **nullable** (no NOT NULL) so existing null-brand rows don't break.
- `role_scorecards.hiring_entity_id` is **nullable** (a scorecard may have no default brand).
- Next migration filename: **`20260630000002_role_scorecards_hiring_entity.sql`** (latest existing is `20260630000001_hiring_entities_logo.sql`).
- Do NOT touch the "Statutory Employer of Record" field (`statutory_entity_id`) — separate concern.
- Run app: `flutter run -d linux --dart-define-from-file=env/prod.json`. Tests: `flutter test <path>`.
- Branch: `feat/employee-brand-allocation` (already created off `main`).

---

## File Structure

**Create:**
- `supabase/migrations/20260630000002_role_scorecards_hiring_entity.sql`
- `test/data/models/role_scorecard_hiring_entity_test.dart`
- `test/features/employees/brand_allocation_resolver_test.dart`

**Modify:**
- `lib/data/models/role_scorecard.dart` — `hiringEntityId` field + ctor + `fromRow` + `toUpsertPayload`.
- `lib/features/responsibility_cards/role_scorecard_form_screen.dart` — "Company (brand)" picker.
- `lib/data/repositories/employee_repository.dart` — `hiringEntityId` param + payload write.
- `lib/features/employees/employee_form_screen.dart` — brand-allocation control, resolver, validation, load, applicant seed, pass to upsert.

---

## Task 1: Migration — `role_scorecards.hiring_entity_id`

**Files:**
- Create: `supabase/migrations/20260630000002_role_scorecards_hiring_entity.sql`

**Interfaces:**
- Produces: nullable column `role_scorecards.hiring_entity_id uuid` (FK → `hiring_entities(id)`).

- [ ] **Step 1: Write the migration**

```sql
-- Default brand (hiring entity) for a role scorecard. Lets the Edit Employee
-- form derive an employee's brand allocation from their selected scorecard.
-- Nullable: a scorecard may have no default brand, in which case the employee
-- form requires the brand to be set manually.
alter table role_scorecards
  add column if not exists hiring_entity_id uuid
    references hiring_entities(id) on delete restrict;

create index if not exists role_scorecards_hiring_entity_id_idx
  on role_scorecards (hiring_entity_id)
  where hiring_entity_id is not null;

comment on column role_scorecards.hiring_entity_id is
  'Default brand allocation for employees assigned this scorecard. The Edit '
  'Employee form uses it in derive mode; NULL means the employee must set the '
  'brand manually.';
```

- [ ] **Step 2: Verify SQL by review**

Do NOT run against any DB (no `supabase db reset`). Confirm the file parses on review. Expected: valid PostgreSQL.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260630000002_role_scorecards_hiring_entity.sql
git commit -m "feat(scorecards): add hiring_entity_id (default brand) to role_scorecards"
```

---

## Task 2: `RoleScorecard` model — `hiringEntityId`

**Files:**
- Modify: `lib/data/models/role_scorecard.dart`
- Test: `test/data/models/role_scorecard_hiring_entity_test.dart` (create)

**Interfaces:**
- Consumes: column `hiring_entity_id` (Task 1).
- Produces: `RoleScorecard.hiringEntityId` (`String?`); `fromRow` maps `r['hiring_entity_id']`; `toUpsertPayload()` includes `'hiring_entity_id': hiringEntityId`.

- [ ] **Step 1: Write the failing test**

Create `test/data/models/role_scorecard_hiring_entity_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';

void main() {
  test('fromRow maps hiring_entity_id; null when absent', () {
    final withEntity = RoleScorecard.fromRow({
      'id': 's1', 'company_id': 'c1', 'job_title': 'Dev',
      'mission_statement': 'm', 'key_responsibilities': [], 'kpis': [],
      'wage_type': 'MONTHLY', 'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday', 'is_active': true,
      'effective_date': '2026-01-01', 'hiring_entity_id': 'he1',
    });
    expect(withEntity.hiringEntityId, 'he1');

    final without = RoleScorecard.fromRow({
      'id': 's2', 'company_id': 'c1', 'job_title': 'Dev',
      'mission_statement': 'm', 'key_responsibilities': [], 'kpis': [],
      'wage_type': 'MONTHLY', 'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday', 'is_active': true,
      'effective_date': '2026-01-01',
    });
    expect(without.hiringEntityId, isNull);
  });

  test('toUpsertPayload includes hiring_entity_id', () {
    final card = RoleScorecard.fromRow({
      'id': 's1', 'company_id': 'c1', 'job_title': 'Dev',
      'mission_statement': 'm', 'key_responsibilities': [], 'kpis': [],
      'wage_type': 'MONTHLY', 'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday', 'is_active': true,
      'effective_date': '2026-01-01', 'hiring_entity_id': 'he1',
    });
    expect(card.toUpsertPayload()['hiring_entity_id'], 'he1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/role_scorecard_hiring_entity_test.dart`
Expected: FAIL — `hiringEntityId` not defined.

- [ ] **Step 3: Implement**

In `lib/data/models/role_scorecard.dart`:
- Add field near `shiftTemplateId`: `final String? hiringEntityId;`
- Add ctor param (optional): `this.hiringEntityId,`
- In `fromRow`, add to the returned constructor: `hiringEntityId: r['hiring_entity_id'] as String?,`
- In `toUpsertPayload()`, add an entry: `'hiring_entity_id': hiringEntityId,`

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/role_scorecard_hiring_entity_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify no regression + commit**

Run: `flutter test test/data/ && flutter analyze lib/data/models/role_scorecard.dart`
Expected: green, no new analyzer issues.
```bash
git add lib/data/models/role_scorecard.dart test/data/models/role_scorecard_hiring_entity_test.dart
git commit -m "feat(scorecards): RoleScorecard.hiringEntityId field + payload"
```

---

## Task 3: Role scorecard form — "Company (brand)" picker

**Files:**
- Modify: `lib/features/responsibility_cards/role_scorecard_form_screen.dart`

**Interfaces:**
- Consumes: `RoleScorecard.hiringEntityId` (Task 2), `hiringEntityListProvider`.
- Produces: the scorecard form sets `hiringEntityId` on the `RoleScorecard` it upserts.

- [ ] **Step 1: Add state + load**

In `_State` add a field: `String? _hiringEntityId;`
In the existing-load block (after `_existing = e;`, alongside `_departmentId = ...`), add: `_hiringEntityId = e.hiringEntityId;`
(If the form reads `_departmentId = e.departmentId;` there, place this next to it. If not present, add `_hiringEntityId = e.hiringEntityId;` right after `_existing = e;`.)

- [ ] **Step 2: Add the picker to build()**

Add this import if missing: `import '../../data/repositories/hiring_entity_repository.dart';` (for `hiringEntityListProvider`).
Immediately after the existing Department `DropdownButtonFormField<String?>` block, add:
```dart
const SizedBox(height: 12),
Builder(builder: (context) {
  final entities =
      ref.watch(hiringEntityListProvider).asData?.value ?? const [];
  return DropdownButtonFormField<String?>(
    initialValue: _hiringEntityId,
    decoration: const InputDecoration(
      labelText: 'Company (brand)',
      helperText: 'Default brand for employees on this scorecard.',
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('(none)')),
      for (final e in entities)
        DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
    ],
    onChanged: (v) => setState(() => _hiringEntityId = v),
  );
}),
```

- [ ] **Step 3: Persist on save**

In the `RoleScorecard(...)` constructed in the save handler, add: `hiringEntityId: _hiringEntityId,` (next to `departmentId: _departmentId,`).

- [ ] **Step 4: Verify it builds**

Run: `flutter analyze lib/features/responsibility_cards/role_scorecard_form_screen.dart`
Expected: no new issues. (GUI — manual smoke deferred to user: open a scorecard, set Company, save, reopen → persists.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/responsibility_cards/role_scorecard_form_screen.dart
git commit -m "feat(scorecards): edit a scorecard's default Company (brand)"
```

---

## Task 4: `EmployeeRepository.upsert` — write `hiring_entity_id`

**Files:**
- Modify: `lib/data/repositories/employee_repository.dart`

**Interfaces:**
- Produces: `upsert(... String? hiringEntityId ...)` writes `payload['hiring_entity_id'] = hiringEntityId`.

- [ ] **Step 1: Add the param**

In the `upsert({...})` signature, add (near `companyId`): `String? hiringEntityId,`

- [ ] **Step 2: Write it into the base payload**

In the `payload` map literal (the always-written block, alongside `'company_id': companyId,`), add:
```dart
      'hiring_entity_id': hiringEntityId,
```
(Always written — the employee form is the only caller and always passes a resolved, validated value. Insert and update both set it.)

- [ ] **Step 3: Verify it builds**

Run: `flutter analyze lib/data/repositories/employee_repository.dart`
Expected: no new issues. (No unit test — `upsert` hits Supabase; the param is exercised by the form's resolver test in Task 5 and manual smoke.)

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/employee_repository.dart
git commit -m "feat(employees): upsert persists hiring_entity_id (brand allocation)"
```

---

## Task 5: Employee form — required brand-allocation control

**Files:**
- Modify: `lib/features/employees/employee_form_screen.dart`
- Test: `test/features/employees/brand_allocation_resolver_test.dart` (create)

**Interfaces:**
- Consumes: `RoleScorecard.hiringEntityId` (Task 2), `EmployeeRepository.upsert(hiringEntityId:)` (Task 4), `hiringEntityListProvider`, `roleScorecardListProvider`, `Employee.hiringEntityId`, `ApplicantSeed.hiringEntityId`.
- Produces: a top-level `enum BrandMode { derive, manual }` and a pure `String? resolveBrandAllocation({required bool deriveFromScorecard, required String? scorecardHiringEntityId, required String? manualHiringEntityId})`.

- [ ] **Step 1: Write the failing test (pure resolver)**

Create `test/features/employees/brand_allocation_resolver_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/employees/employee_form_screen.dart';

void main() {
  test('derive uses scorecard entity; manual uses explicit pick', () {
    expect(
      resolveBrandAllocation(
        deriveFromScorecard: true,
        scorecardHiringEntityId: 'sc-entity',
        manualHiringEntityId: 'manual-entity',
      ),
      'sc-entity',
    );
    expect(
      resolveBrandAllocation(
        deriveFromScorecard: false,
        scorecardHiringEntityId: 'sc-entity',
        manualHiringEntityId: 'manual-entity',
      ),
      'manual-entity',
    );
  });

  test('derive with no scorecard entity resolves null (form blocks save)', () {
    expect(
      resolveBrandAllocation(
        deriveFromScorecard: true,
        scorecardHiringEntityId: null,
        manualHiringEntityId: 'manual-entity',
      ),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/employees/brand_allocation_resolver_test.dart`
Expected: FAIL — `resolveBrandAllocation` / `BrandMode` not defined.

- [ ] **Step 3: Add the enum + resolver (top-level, in employee_form_screen.dart)**

At top level (outside the widget classes), add:
```dart
/// Brand-allocation entry mode for the employee form.
enum BrandMode { derive, manual }

/// Resolves the brand allocation to persist for an employee. In derive mode the
/// selected role scorecard's entity is used; in manual mode the explicit pick is
/// used. Returns null when nothing resolves — the form must block save then.
String? resolveBrandAllocation({
  required bool deriveFromScorecard,
  required String? scorecardHiringEntityId,
  required String? manualHiringEntityId,
}) =>
    deriveFromScorecard ? scorecardHiringEntityId : manualHiringEntityId;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/employees/brand_allocation_resolver_test.dart`
Expected: PASS.

- [ ] **Step 5: Add form state**

In `_EmployeeFormScreenState` (near `_statutoryEntityId`), add:
```dart
  BrandMode _brandMode = BrandMode.derive;
  String? _hiringEntityId;       // manual selection
  String? _origHiringEntityId;
```

In `_loadExisting()` (near `_statutoryEntityId = e.statutoryEntityId;`), add:
```dart
      _hiringEntityId = e.hiringEntityId;
      _origHiringEntityId = e.hiringEntityId;
      // Existing employees with a stored brand open in manual mode showing it
      // (lossless); legacy null-brand rows default to derive.
      _brandMode = e.hiringEntityId == null ? BrandMode.derive : BrandMode.manual;
```

In `_applyApplicantSeed(...)`, replace the comment block about hiringEntityId with:
```dart
    if (s.hiringEntityId != null && s.hiringEntityId!.isNotEmpty) {
      _hiringEntityId = s.hiringEntityId;
      _brandMode = BrandMode.manual;
    }
```

- [ ] **Step 6: Add the brand control widget**

Add this method to the state class:
```dart
  Widget _buildBrandAllocationField() {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canEdit = profile?.isHrOrAdmin ?? false;
    final entities =
        ref.watch(hiringEntityListProvider).asData?.value ?? const [];
    final cards = ref.watch(roleScorecardListProvider).asData?.value ?? const [];
    final selectedCard = _roleScorecardId == null
        ? null
        : cards.where((c) => c.id == _roleScorecardId).firstOrNull;
    final derivedId = selectedCard?.hiringEntityId;
    String nameOf(String? id) => id == null
        ? '—'
        : (entities.where((e) => e.id == id).firstOrNull?.name ?? '(unavailable)');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<BrandMode>(
          segments: const [
            ButtonSegment(value: BrandMode.derive, label: Text('From role scorecard')),
            ButtonSegment(value: BrandMode.manual, label: Text('Set manually')),
          ],
          selected: {_brandMode},
          onSelectionChanged:
              canEdit ? (s) => setState(() => _brandMode = s.first) : null,
        ),
        const SizedBox(height: 8),
        if (_brandMode == BrandMode.derive)
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Company (brand)',
              helperText: derivedId == null
                  ? 'This role scorecard has no company set — choose "Set '
                      'manually", or set it on the scorecard.'
                  : 'Derived from the role scorecard.',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(derivedId == null ? '— None —' : nameOf(derivedId)),
          )
        else
          DropdownButtonFormField<String?>(
            initialValue:
                entities.any((e) => e.id == _hiringEntityId) ? _hiringEntityId : null,
            decoration: const InputDecoration(
              labelText: 'Company (brand)',
              helperText: 'Required.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— Select —')),
              for (final e in entities)
                DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
            ],
            onChanged:
                canEdit ? (v) => setState(() => _hiringEntityId = v) : null,
          ),
      ],
    );
  }
```
Add `import 'package:collection/collection.dart';` if `firstOrNull` isn't already available in the file (it is used elsewhere in the codebase; check imports).

- [ ] **Step 7: Place the control in build()**

In the Employment `Card`, insert right before `_buildStatutoryEntityField()`:
```dart
                          const SizedBox(height: 12),
                          _buildBrandAllocationField(),
```

- [ ] **Step 8: Resolve + validate + pass to upsert**

In the save handler, where `selectedCard` is computed (the block with `derivedJobTitle`/`derivedDepartmentId`), add right after it:
```dart
      final effectiveHiringEntityId = resolveBrandAllocation(
        deriveFromScorecard: _brandMode == BrandMode.derive,
        scorecardHiringEntityId: selectedCard?.hiringEntityId,
        manualHiringEntityId: _hiringEntityId,
      );
      if (effectiveHiringEntityId == null) {
        setState(() => _error =
            'Company (brand) is required. Pick a brand, or choose a role '
            'scorecard that has a company set.');
        return;
      }
```
> The save handler already references `selectedCard` (used for `derivedJobTitle`). If `cards` is not in scope there, read it first: `final cards = ref.read(roleScorecardListProvider).asData?.value ?? const [];` and `final selectedCard = _roleScorecardId == null ? null : cards.where((c) => c.id == _roleScorecardId).firstOrNull;`

Then add to the `upsert(...)` call (near `roleScorecardId: _roleScorecardId,`):
```dart
            hiringEntityId: effectiveHiringEntityId,
```
Confirm `_error` is the field the form renders for save errors (it is — used by the statutory/save paths). Ensure the early `return` is before `setState(() => _saving = ...)` completion / inside the same guard pattern other validations use.

- [ ] **Step 9: Run tests + analyze**

Run: `flutter test test/features/employees/ test/data/ && flutter analyze lib/features/employees/employee_form_screen.dart`
Expected: green; no new analyzer issues.

- [ ] **Step 10: Commit**

```bash
git add lib/features/employees/employee_form_screen.dart test/features/employees/brand_allocation_resolver_test.dart
git commit -m "feat(employees): required Company (brand) field — derive or manual"
```

---

## Task 6: Full regression + analyzer + final review

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: no NEW errors (pre-existing project info/warning lints are acceptable; do not introduce new warnings in changed files).

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A
git commit -m "chore(employees): analyzer + test fixups for brand allocation"
```

---

## Self-Review notes (for the implementer)

- The employee form's brand control is **required at the form layer only**; the DB column stays nullable. Save is blocked (inline `_error`) when neither derive nor manual resolves a brand.
- Derive mode reads the **already-loaded** scorecard list (`roleScorecardListProvider`) — no new provider/async. The control rebuilds reactively when the role scorecard changes (both are in the same Employment card).
- `firstOrNull` comes from `package:collection`. Confirm the import exists in each file you use it in.
- Do NOT modify the "Statutory Employer of Record" field or `statutory_entity_id`.
- After this lands, existing employees with a null brand will be forced to pick one the next time they're edited — expected per the spec.
