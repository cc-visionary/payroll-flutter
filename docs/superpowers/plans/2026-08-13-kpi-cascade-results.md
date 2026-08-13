# KPI Cascade — Results Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn KPI definitions into monthly results at Personal, Department and Company scope — computed from data the app already owns wherever possible, and honest about what it does not know.

**Architecture:** Four pure Dart modules carry the correctness (status, population, roll-up eligibility, exception aggregation) and are tested with no database at all. Three new tables store results and the two manual input records. One compute service assembles them. The screens are thin. The surface that COLLECTS manual input is the last task, because that decision is still open.

**Tech Stack:** Flutter (Material 3, Riverpod 3.x), Supabase Postgres, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-13-kpi-cascade-design.md` — read it first, especially "How results are produced", "The ingestion boundary" and "Pure logic, tested apart from the UI".

**Depends on:** `docs/superpowers/plans/2026-08-13-kpi-cascade-definitions.md` — **landed and merged** at `bf05079`. Its three migrations (`20260814000001..3`) are committed and UNAPPLIED, as is `20260811000001`. `employee_kpis` no longer exists in the schema this plan targets: a person's KPIs are their role's KPIs.

## Global Constraints

- The repo gates on `flutter analyze` only: **0 errors, 0 warnings**. There are 192 pre-existing `info` lints — add none.
- **Do not run `dart format`.** This repo has mixed old/new formatter style and is not gated on it. Match the file you are editing.
- Never claim a test passed or the analyzer was clean without pasting the command output.
- **Migrations are applied by the user, never by an implementer.** You have no authority to run `supabase db push` or any database command. Commit the file and hand it over.
- Migrations must be idempotent in this repo's style: `add column if not exists`, `create table if not exists`, `drop policy if exists` before `create policy`. Read a recent migration before writing yours.
- Widget tests use `initSupabaseStub()` from `test/support/supabase_stub.dart`.
- Baseline: **1370 passing, 1 skipped**; `flutter analyze lib test` 0 errors / 0 warnings / 192 infos. Do not regress it.
- Vocabulary is **role**, never "seat". EOS is not the framework here.
- Existing enum values you must match exactly, not invent: `kpis.value_type` is `COUNT | RATIO | CURRENCY | PERCENT | DURATION`; `role_scorecard_kpis.goal_direction` is `GTE | LTE | EQ | BETWEEN`, modelled as `GoalDirection { gte, lte, eq, between }` in `lib/data/models/kpi_goal.dart`.
- Migration numbering: the definitions plan used `20260814000001..3` and an unrelated leave fix took `20260815000001`. `20260814000004` and `...005` are still free and are what this plan uses, so its migrations sort BEFORE the leave fix. That is harmless — the two touch different tables — but do not renumber to "look newer".

## A spec gap this plan fills, deliberately

The spec's "How results are produced" names three input paths and gives the record shape for a **period reading** — `(kpi, scope, period, numerator, denominator, note)` — but its Data model section only defines `kpi_results` and `kpi_exceptions`. There is nowhere for a reading to live.

This plan adds **`kpi_readings`** rather than writing readings straight into `kpi_results`. The reason matters: `kpi_results` is *derived* and must stay recomputable. If a hand-entered numerator lived there, the next recompute would either destroy it or have to special-case around it, and within a month nobody would know which rows were safe to regenerate. Inputs live in input tables; `kpi_results` is only ever output.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260814000004_kpi_results.sql` (new) | `kpi_results` + RLS |
| `supabase/migrations/20260814000005_kpi_inputs.sql` (new) | `kpi_exceptions`, `kpi_readings` + RLS |
| `lib/features/kpi_results/kpi_status.dart` (new) | Pure: numerator + denominator + target + direction → status |
| `lib/data/models/kpi_result.dart` (new) | `KpiScope`, `KpiStatus`, `SourceCompleteness`, `KpiResult` |
| `lib/features/kpi_results/kpi_population.dart` (new) | Pure: KPI + scope → whose data counts |
| `lib/features/kpi_results/kpi_rollup.dart` (new) | Pure: which scopes a KPI computes at |
| `lib/features/kpi_results/exception_aggregation.dart` (new) | Pure: confirmed exceptions → a month's count |
| `lib/data/models/kpi_input.dart` (new) | `KpiException`, `KpiReading`, `ReportedVia` |
| `lib/data/repositories/kpi_result_repository.dart` (new) | Results read/upsert; the ingestion boundary for both input records |
| `lib/features/kpi_results/automatic_sources.dart` (new) | The source registry and its four in-app sources |
| `lib/features/kpi_results/compute_kpi_results.dart` (new) | Assembles inputs → status → rows |
| `lib/features/kpi_results/kpi_results_screen.dart` (new) | Monthly view per scope |
| `lib/features/kpi_results/kpi_dashboard_screen.dart` (new) | Company + Department for a month |
| `lib/app/router.dart`, `lib/app/shell.dart` (modify) | Routes and nav for the two screens |

---

### Task 1: Status, and the difference between missing and bad

**Files:**
- Create: `lib/features/kpi_results/kpi_status.dart`
- Test: `test/features/kpi_results/kpi_status_test.dart`

**Interfaces:**
- Produces: `({num? value, KpiStatus status}) evaluateKpi({required String valueType, num? numerator, num? denominator, num? target, GoalDirection? direction, num? targetMax})`.
- Produces: `enum KpiStatus { onTrack, offTrack, noData }` and `enum KpiScope { personal, department, company }`, both in **`lib/data/models/kpi_result.dart`** — created by this task, extended by Tasks 2 and 4.
- Consumes: `GoalDirection` from `lib/data/models/kpi_goal.dart`.

**Where the enums live, and why it is not where you would first put them.**
`KpiStatus` is tempting to declare in `kpi_status.dart` beside the rule that
produces it. Do not. `lib/data/models/kpi_result.dart` has to name it, and no
model in this repo imports a feature — that is why `kpi_goal.dart` sits under
`models/` even though only the KPI feature uses it. Enums in the model layer,
rules in the feature layer, dependencies pointing one way.

This is the rule the whole dashboard rests on. Build it before anything that stores or renders it.

The one thing it must never do is call a missing number a failure. A red square that only means "nobody entered anything" teaches people to ignore red squares, and then the tool is worthless.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_status.dart';

void main() {
  ({num? value, KpiStatus status}) run({
    String valueType = 'RATIO',
    num? numerator,
    num? denominator,
    num? target,
    GoalDirection? direction = GoalDirection.gte,
    num? targetMax,
  }) => evaluateKpi(
    valueType: valueType,
    numerator: numerator,
    denominator: denominator,
    target: target,
    direction: direction,
    targetMax: targetMax,
  );

  group('missing data is never a failure', () {
    test('no numerator at all is NO_DATA', () {
      expect(run(denominator: 100, target: 0.99).status, KpiStatus.noData);
    });

    test('a RATIO with no denominator is NO_DATA, not OFF_TRACK', () {
      // The tempting bug: treat a null denominator as 0, divide, get 0,
      // and report a catastrophic miss on a KPI nobody has data for.
      expect(run(numerator: 398, target: 0.99).status, KpiStatus.noData);
    });

    test('a zero denominator is NO_DATA, not a division error', () {
      final r = run(numerator: 0, denominator: 0, target: 0.99);
      expect(r.status, KpiStatus.noData);
      expect(r.value, isNull);
    });

    test('no target is NO_DATA even with real inputs', () {
      // A number with nothing to judge it against is not a verdict.
      expect(run(numerator: 398, denominator: 400, target: null).status,
          KpiStatus.noData);
    });
  });

  group('a real zero is a real result', () {
    test('zero numerator over a real denominator is a genuine miss', () {
      final r = run(numerator: 0, denominator: 400, target: 0.99);
      expect(r.value, 0);
      expect(r.status, KpiStatus.offTrack);
    });

    test('a COUNT of zero against a LTE target is on track', () {
      // "Confirmed purchasing errors, at most 0" — zero is success, and it
      // must not be mistaken for missing.
      final r = run(
        valueType: 'COUNT',
        numerator: 0,
        target: 0,
        direction: GoalDirection.lte,
      );
      expect(r.value, 0);
      expect(r.status, KpiStatus.onTrack);
    });
  });

  group('the boundary is inclusive both ways', () {
    test('exactly meeting a GTE target is on track', () {
      expect(run(numerator: 99, denominator: 100, target: 0.99).status,
          KpiStatus.onTrack);
    });

    test('exactly meeting a LTE target is on track', () {
      expect(
        run(
          valueType: 'COUNT',
          numerator: 3,
          target: 3,
          direction: GoalDirection.lte,
        ).status,
        KpiStatus.onTrack,
      );
    });

    test('EQ is on track only on the nose', () {
      expect(
        run(valueType: 'COUNT', numerator: 5, target: 5,
            direction: GoalDirection.eq).status,
        KpiStatus.onTrack,
      );
      expect(
        run(valueType: 'COUNT', numerator: 4, target: 5,
            direction: GoalDirection.eq).status,
        KpiStatus.offTrack,
      );
    });

    test('BETWEEN is inclusive at both ends', () {
      final inside = run(
        valueType: 'COUNT', numerator: 5, target: 4, targetMax: 6,
        direction: GoalDirection.between,
      );
      expect(inside.status, KpiStatus.onTrack);
      expect(
        run(valueType: 'COUNT', numerator: 4, target: 4, targetMax: 6,
            direction: GoalDirection.between).status,
        KpiStatus.onTrack,
      );
      expect(
        run(valueType: 'COUNT', numerator: 7, target: 4, targetMax: 6,
            direction: GoalDirection.between).status,
        KpiStatus.offTrack,
      );
    });

    test('BETWEEN with no upper bound is NO_DATA, not a one-sided test', () {
      // A half-configured band cannot judge anything.
      expect(
        run(valueType: 'COUNT', numerator: 5, target: 4,
            direction: GoalDirection.between).status,
        KpiStatus.noData,
      );
    });
  });

  group('value derivation by type', () {
    test('COUNT ignores the denominator entirely', () {
      final r = run(valueType: 'COUNT', numerator: 3, denominator: 999,
          target: 5, direction: GoalDirection.lte);
      expect(r.value, 3);
      expect(r.status, KpiStatus.onTrack);
    });

    test('RATIO divides', () {
      expect(run(numerator: 398, denominator: 400, target: 0.99).value,
          closeTo(0.995, 0.0001));
    });

    test('CURRENCY and DURATION behave like COUNT', () {
      for (final t in ['CURRENCY', 'DURATION']) {
        final r = run(valueType: t, numerator: 250, target: 200);
        expect(r.value, 250, reason: t);
        expect(r.status, KpiStatus.onTrack, reason: t);
      }
    });

    test('a null direction defaults to GTE rather than refusing to judge', () {
      expect(
        run(valueType: 'COUNT', numerator: 10, target: 5, direction: null)
            .status,
        KpiStatus.onTrack,
      );
    });
  });
}
```

- [ ] **Step 2: Run it, watch it fail**

Run: `flutter test test/features/kpi_results/kpi_status_test.dart`
Expected: FAIL — `kpi_status.dart` does not exist.

- [ ] **Step 3: Implement**

First `lib/data/models/kpi_result.dart`:

```dart
/// The three levels a KPI result can be computed at.
enum KpiScope { personal, department, company }

/// A period's verdict on one KPI.
///
/// [noData] is NOT a soft failure — it means the engine could not form a
/// judgement, and it must never render as red. Red means data existed and the
/// target was missed. Conflating them trains people to ignore red.
enum KpiStatus { onTrack, offTrack, noData }

const kpiScopeCodes = {
  KpiScope.personal: 'PERSONAL',
  KpiScope.department: 'DEPARTMENT',
  KpiScope.company: 'COMPANY',
};

const kpiStatusCodes = {
  KpiStatus.onTrack: 'ON_TRACK',
  KpiStatus.offTrack: 'OFF_TRACK',
  KpiStatus.noData: 'NO_DATA',
};
```

Then `lib/features/kpi_results/kpi_status.dart`:

```dart
import '../../data/models/kpi_goal.dart';
import '../../data/models/kpi_result.dart';

/// Derives a period's value and status from raw inputs.
///
/// Pure and total: every combination of inputs returns a record, never throws.
/// `PERCENT` carries its value in the numerator, like `COUNT` — the UI is what
/// appends a `%`. Only `RATIO` divides.
({num? value, KpiStatus status}) evaluateKpi({
  required String valueType,
  num? numerator,
  num? denominator,
  num? target,
  GoalDirection? direction,
  num? targetMax,
}) {
  // ONLY RATIO. PERCENT looks like it should need a denominator and does not:
  // kpi_reading.dart:15 already treats it like COUNT, the Library form only
  // populates denominator fields for RATIO, and 20260811000001's own comment
  // says "RATIO requires both denominator columns". Requiring one here would
  // make every PERCENT KPI permanently NO_DATA.
  final needsDenominator = valueType == 'RATIO';

  num? value;
  if (numerator == null) {
    value = null;
  } else if (!needsDenominator) {
    value = numerator;
  } else if (denominator == null || denominator == 0) {
    value = null;
  } else {
    value = numerator / denominator;
  }

  if (value == null || target == null) {
    return (value: value, status: KpiStatus.noData);
  }

  final dir = direction ?? GoalDirection.gte;
  if (dir == GoalDirection.between && targetMax == null) {
    return (value: value, status: KpiStatus.noData);
  }

  final ok = switch (dir) {
    GoalDirection.gte => value >= target,
    GoalDirection.lte => value <= target,
    GoalDirection.eq => value == target,
    GoalDirection.between => value >= target && value <= targetMax!,
  };
  return (value: value, status: ok ? KpiStatus.onTrack : KpiStatus.offTrack);
}
```

- [ ] **Step 4: Run it, watch it pass**

Run: `flutter test test/features/kpi_results/kpi_status_test.dart`
Expected: PASS, 15 tests.

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/data/models/kpi_result.dart lib/features/kpi_results/kpi_status.dart test/features/kpi_results/kpi_status_test.dart
git commit -m "feat(kpi): the status rule, where missing is not the same as bad"
```

---

### Task 2: Whose data counts

**Files:**
- Create: `lib/features/kpi_results/kpi_population.dart`
- Test: `test/features/kpi_results/kpi_population_test.dart`

**Interfaces:**
- Produces: `List<String> populationFor({required KpiScope scope, String? departmentId, required List<Employee> employees, required List<RoleScorecard> roles})` returning employee ids.
- Consumes: `KpiScope` from `lib/data/models/kpi_result.dart`, created by Task 1.

**A trap specific to this codebase.** `employees.department_id` exists AND `role_scorecards.department_id` exists. The employee column is a denormalized copy written at save time — `employee_form_screen.dart:346` derives it from the selected role card. It therefore goes stale the moment a role is moved to a different department and existing holders are not re-saved.

**Resolve the department from the ROLE, every time.** It is the authoritative one, it cannot drift, and it makes the spec's rule literally true: a person with no role has no department.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_population.dart';

Employee _e(
  String id, {
  String? roleId,
  String? deptId,
  String status = 'ACTIVE',
  DateTime? deletedAt,
}) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: id,
  lastName: 'X',
  roleScorecardId: roleId,
  departmentId: deptId,
  employmentType: 'FULL_TIME',
  employmentStatus: status,
  deletedAt: deletedAt,
  hireDate: DateTime(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  sssEligibilityOverride: false,
  philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false,
  taxOnFullEarnings: false,
);

RoleScorecard _r(String id, {String? deptId}) => RoleScorecard(
  id: id,
  companyId: 'c',
  departmentId: deptId,
  jobTitle: 'Role $id',
  missionStatement: '',
  responsibilities: const [],
  kpis: const [],
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026),
);

void main() {
  final roles = [_r('r-ops', deptId: 'd-ops'), _r('r-mkt', deptId: 'd-mkt')];

  test('company scope is every active holder', () {
    final ids = populationFor(
      scope: KpiScope.company,
      employees: [_e('a', roleId: 'r-ops'), _e('b', roleId: 'r-mkt')],
      roles: roles,
    );
    expect(ids, ['a', 'b']);
  });

  test('department scope resolves the department through the ROLE', () {
    final ids = populationFor(
      scope: KpiScope.department,
      departmentId: 'd-ops',
      employees: [_e('a', roleId: 'r-ops'), _e('b', roleId: 'r-mkt')],
      roles: roles,
    );
    expect(ids, ['a']);
  });

  test('a stale employees.department_id does not win over the role', () {
    // The employee row still says d-mkt from before the role moved.
    // The role is authoritative, so this person counts under d-ops.
    final ids = populationFor(
      scope: KpiScope.department,
      departmentId: 'd-ops',
      employees: [_e('a', roleId: 'r-ops', deptId: 'd-mkt')],
      roles: roles,
    );
    expect(ids, ['a']);
  });

  test('a person with no role falls out of department scope entirely', () {
    final ids = populationFor(
      scope: KpiScope.department,
      departmentId: 'd-ops',
      employees: [_e('a', roleId: 'r-ops'), _e('nobody', deptId: 'd-ops')],
      roles: roles,
    );
    expect(ids, ['a'], reason: 'the roleless person has no department');
  });

  test('a roleless person still counts at company scope', () {
    final ids = populationFor(
      scope: KpiScope.company,
      employees: [_e('nobody')],
      roles: roles,
    );
    expect(ids, ['nobody']);
  });

  test('a role pointing at no department contributes nobody', () {
    final ids = populationFor(
      scope: KpiScope.department,
      departmentId: 'd-ops',
      employees: [_e('a', roleId: 'r-orphan')],
      roles: [_r('r-orphan')],
    );
    expect(ids, isEmpty);
  });

  test('terminated and soft-deleted people are excluded at every scope', () {
    final emps = [
      _e('active', roleId: 'r-ops'),
      _e('gone', roleId: 'r-ops', status: 'TERMINATED'),
      _e('deleted', roleId: 'r-ops', deletedAt: DateTime(2026, 1, 1)),
    ];
    expect(populationFor(scope: KpiScope.company, employees: emps, roles: roles),
        ['active']);
    expect(
      populationFor(
        scope: KpiScope.department,
        departmentId: 'd-ops',
        employees: emps,
        roles: roles,
      ),
      ['active'],
    );
  });

  test('department scope with no department id is empty, not everyone', () {
    // Guards the worst failure mode: a misconfigured department KPI silently
    // reporting the whole company as its population.
    expect(
      populationFor(
        scope: KpiScope.department,
        employees: [_e('a', roleId: 'r-ops')],
        roles: roles,
      ),
      isEmpty,
    );
  });

  test('the result is sorted, so two identical calls agree', () {
    final ids = populationFor(
      scope: KpiScope.company,
      employees: [_e('z', roleId: 'r-ops'), _e('a', roleId: 'r-ops')],
      roles: roles,
    );
    expect(ids, ['a', 'z']);
  });
}
```

- [ ] **Step 2: Run it, watch it fail**

Run: `flutter test test/features/kpi_results/kpi_population_test.dart`
Expected: FAIL — neither `kpi_population.dart` nor `KpiScope` exists.

- [ ] **Step 3: Implement**

`KpiScope` already exists from Task 1. Create `lib/features/kpi_results/kpi_population.dart`:

```dart
import '../../data/models/employee.dart';
import '../../data/models/kpi_result.dart';
import '../../data/models/role_scorecard.dart';

/// Employee ids whose data belongs in a result at [scope], sorted.
///
/// A person's department is resolved through their ROLE, never through
/// `employees.department_id`. That column is a denormalized copy written when
/// the employee form saves (`employee_form_screen.dart` derives it from the
/// selected role card), so it goes stale the moment a role moves to another
/// department and its holders are not re-saved. The role is authoritative.
///
/// A consequence worth stating because it is load-bearing rather than
/// incidental: a person with no role has no department, so they are absent
/// from every Department result while still counting at Company scope.
List<String> populationFor({
  required KpiScope scope,
  String? departmentId,
  required List<Employee> employees,
  required List<RoleScorecard> roles,
}) {
  final deptByRole = {for (final r in roles) r.id: r.departmentId};

  bool holds(Employee e) =>
      e.employmentStatus == 'ACTIVE' && e.deletedAt == null;

  final ids = <String>[];
  for (final e in employees) {
    if (!holds(e)) continue;
    switch (scope) {
      case KpiScope.company:
        ids.add(e.id);
      case KpiScope.department:
        // No department asked for means no population. Falling back to
        // "everyone" would make a misconfigured department KPI silently
        // report the whole company.
        if (departmentId == null) continue;
        final roleId = e.roleScorecardId;
        if (roleId == null) continue;
        if (deptByRole[roleId] != departmentId) continue;
        ids.add(e.id);
      case KpiScope.personal:
        ids.add(e.id);
    }
  }
  ids.sort();
  return ids;
}
```

- [ ] **Step 4: Run it, watch it pass**

Run: `flutter test test/features/kpi_results/kpi_population_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/kpi_results/kpi_population.dart test/features/kpi_results/kpi_population_test.dart
git commit -m "feat(kpi): resolve a result's population from the role, not the stale copy"
```

---

### Task 3: Which scopes a KPI computes at

**Files:**
- Create: `lib/features/kpi_results/kpi_rollup.dart`
- Test: `test/features/kpi_results/kpi_rollup_test.dart`

**Interfaces:**
- Produces: `Set<KpiScope> scopesFor({required String level, required String rollupType})`.
- Consumes: `KpiScope` from Task 2.

`level` is where the KPI is *designed* to live; `rollup_type` says how far it travels. The pair decides which rows the engine writes.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_rollup.dart';

void main() {
  test('DIRECT from PERSONAL computes all three', () {
    expect(
      scopesFor(level: 'PERSONAL', rollupType: 'DIRECT'),
      {KpiScope.personal, KpiScope.department, KpiScope.company},
    );
  });

  test('SHARED never computes personal', () {
    // Critical Stockouts: the team owns it; blaming one person is unfair,
    // which is the entire reason SHARED exists.
    expect(
      scopesFor(level: 'DEPARTMENT', rollupType: 'SHARED'),
      {KpiScope.department, KpiScope.company},
    );
  });

  test('ALIGNED computes only its own level', () {
    expect(scopesFor(level: 'PERSONAL', rollupType: 'ALIGNED'),
        {KpiScope.personal});
    expect(scopesFor(level: 'DEPARTMENT', rollupType: 'ALIGNED'),
        {KpiScope.department});
  });

  test('INDEPENDENT computes only its own level', () {
    expect(scopesFor(level: 'COMPANY', rollupType: 'INDEPENDENT'),
        {KpiScope.company});
  });

  test('DIRECT from DEPARTMENT does not invent personal rows', () {
    // Rolling UP is meaningful; rolling DOWN is not. A department KPI has no
    // per-person decomposition just because it is direct.
    expect(
      scopesFor(level: 'DEPARTMENT', rollupType: 'DIRECT'),
      {KpiScope.department, KpiScope.company},
    );
  });

  test('DIRECT from COMPANY is company only', () {
    expect(scopesFor(level: 'COMPANY', rollupType: 'DIRECT'),
        {KpiScope.company});
  });

  test('an unknown roll-up type falls back to the level alone', () {
    // Safe direction: compute less, not more. A bad value must never fan a
    // KPI out across scopes nobody asked for.
    expect(scopesFor(level: 'PERSONAL', rollupType: 'NONSENSE'),
        {KpiScope.personal});
  });
}
```

- [ ] **Step 2: Run it, watch it fail**

Run: `flutter test test/features/kpi_results/kpi_rollup_test.dart`
Expected: FAIL — `kpi_rollup.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
import '../../data/models/kpi_result.dart';

const _order = [KpiScope.personal, KpiScope.department, KpiScope.company];

KpiScope _levelScope(String level) => switch (level) {
  'PERSONAL' => KpiScope.personal,
  'DEPARTMENT' => KpiScope.department,
  _ => KpiScope.company,
};

/// The scopes a KPI produces rows at.
///
/// Rolling UP is meaningful, rolling DOWN never is: a Department KPI has no
/// per-person decomposition merely because it is DIRECT. So every rule here
/// starts at the KPI's own level and only ever widens upward.
///
/// SHARED is the one that earns its own branch — it exists precisely so a team
/// outcome (Critical Stockouts) is never attributed to an individual, so it
/// starts at department however it is levelled.
Set<KpiScope> scopesFor({required String level, required String rollupType}) {
  final own = _levelScope(level);
  switch (rollupType) {
    case 'DIRECT':
      return _order.sublist(_order.indexOf(own)).toSet();
    case 'SHARED':
      final floor = own == KpiScope.personal ? KpiScope.department : own;
      return _order.sublist(_order.indexOf(floor)).toSet();
    default:
      // ALIGNED, INDEPENDENT, and anything unrecognised. Computing less than
      // asked is recoverable; inventing rows across scopes is not.
      return {own};
  }
}
```

- [ ] **Step 4: Run it, watch it pass**

Run: `flutter test test/features/kpi_results/kpi_rollup_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/kpi_results/kpi_rollup.dart test/features/kpi_results/kpi_rollup_test.dart
git commit -m "feat(kpi): roll-up eligibility widens upward and never downward"
```

---

### Task 4: The results table

**Files:**
- Create: `supabase/migrations/20260814000004_kpi_results.sql`
- Modify: `lib/data/models/kpi_result.dart`
- Create: `lib/data/repositories/kpi_result_repository.dart`
- Test: `test/data/models/kpi_result_test.dart`

**Interfaces:**
- Produces: `class KpiResult` with `fromRow` / `toUpsertPayload`; `KpiResultRepository.listByPeriod(String period)`, `.upsertAll(List<KpiResult>)`.
- Consumes: `KpiScope`, `KpiStatus`.

**Do not apply the migration.**

- [ ] **Step 1: Write the migration**

```sql
-- Results are DERIVED. Every column here is reproducible from inputs plus a
-- KPI definition, which is why manual entry lives in kpi_readings instead:
-- anything hand-written into this table would be destroyed by the next
-- recompute, or would force the recompute to guess which rows are safe.

create table if not exists kpi_results (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id) on delete cascade,
  kpi_id              uuid not null references kpis(id) on delete cascade,
  period              text not null,
  scope               text not null check (scope in ('PERSONAL','DEPARTMENT','COMPANY')),
  employee_id         uuid references employees(id) on delete cascade,
  department_id       uuid references departments(id) on delete cascade,
  numerator           numeric,
  denominator         numeric,
  value               numeric,
  target_snapshot     numeric,
  target_max_snapshot numeric,
  direction_snapshot  text check (direction_snapshot is null or direction_snapshot in ('GTE','LTE','EQ','BETWEEN')),
  status              text not null check (status in ('ON_TRACK','OFF_TRACK','NO_DATA')),
  source_completeness text not null default 'COMPLETE'
    check (source_completeness in ('COMPLETE','MISSING_SOURCE')),
  computed_at         timestamptz not null default now(),
  created_at          timestamptz not null default now()
);

-- Postgres treats NULLs as distinct in a unique index, so a plain unique
-- constraint over the nullable scope columns would allow unlimited duplicate
-- COMPANY rows. coalesce to a fixed uuid to make the key total.
create unique index if not exists kpi_results_identity
  on kpi_results (
    kpi_id, period, scope,
    coalesce(employee_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists kpi_results_period on kpi_results (company_id, period);
create index if not exists kpi_results_employee on kpi_results (employee_id, period);

alter table kpi_results enable row level security;

-- Company-wide read: a scorecard everyone can see is the point of a cascade.
-- Personal rows are the exception -- an employee's own number is theirs and
-- their manager's, not the company's.
drop policy if exists kpi_results_read on kpi_results;
create policy kpi_results_read on kpi_results for select using (
  company_id = auth_company_id()
  and (
    scope <> 'PERSONAL'
    or auth_is_performance_admin_for_employee(employee_id)
    or employee_id = auth_employee_id()
    or exists (
      select 1 from employees e
      where e.id = employee_id and e.reports_to_id = auth_employee_id()
    )
  )
);

-- Writes come from the compute service, run by HR/admin.
drop policy if exists kpi_results_write on kpi_results;
create policy kpi_results_write on kpi_results for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR','HR_ADMIN')
    and company_id = auth_company_id())
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR','HR_ADMIN')
    and company_id = auth_company_id());
```

- [ ] **Step 2: Write the failing model test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_status.dart';

void main() {
  test('round-trips a personal row', () {
    final r = KpiResult.fromRow({
      'id': 'res-1',
      'company_id': 'c',
      'kpi_id': 'k-1',
      'period': '2026-08',
      'scope': 'PERSONAL',
      'employee_id': 'e-1',
      'department_id': null,
      'numerator': 398,
      'denominator': 400,
      'value': 0.995,
      'target_snapshot': 0.99,
      'target_max_snapshot': null,
      'direction_snapshot': 'GTE',
      'status': 'ON_TRACK',
      'source_completeness': 'COMPLETE',
    });
    expect(r.scope, KpiScope.personal);
    expect(r.status, KpiStatus.onTrack);
    expect(r.direction, GoalDirection.gte);
    expect(r.employeeId, 'e-1');

    final p = r.toUpsertPayload();
    expect(p['scope'], 'PERSONAL');
    expect(p['status'], 'ON_TRACK');
    expect(p['direction_snapshot'], 'GTE');
    expect(p['numerator'], 398);
  });

  test('a NO_DATA row keeps its nulls rather than defaulting to zero', () {
    // Writing 0 here would turn "we do not know" into "it was nothing",
    // which is the same lie the status rule exists to prevent.
    final r = KpiResult.fromRow({
      'id': 'res-2',
      'company_id': 'c',
      'kpi_id': 'k-1',
      'period': '2026-08',
      'scope': 'COMPANY',
      'numerator': null,
      'denominator': null,
      'value': null,
      'status': 'NO_DATA',
      'source_completeness': 'MISSING_SOURCE',
    });
    expect(r.value, isNull);
    expect(r.numerator, isNull);
    expect(r.status, KpiStatus.noData);
    expect(r.sourceCompleteness, SourceCompleteness.missingSource);
    expect(r.toUpsertPayload()['value'], isNull);
  });

  test('a company row carries neither employee nor department', () {
    final r = KpiResult.fromRow({
      'id': 'res-3',
      'company_id': 'c',
      'kpi_id': 'k-1',
      'period': '2026-08',
      'scope': 'COMPANY',
      'status': 'NO_DATA',
      'source_completeness': 'COMPLETE',
    });
    expect(r.employeeId, isNull);
    expect(r.departmentId, isNull);
  });
}
```

- [ ] **Step 3: Run it, watch it fail. Step 4: Implement the model and repository.**

Add to `lib/data/models/kpi_result.dart` beside `KpiScope` and `KpiStatus`: `enum SourceCompleteness { complete, missingSource }` with `COMPLETE` / `MISSING_SOURCE` codes, and `class KpiResult` with fields `id, companyId, kpiId, period, scope, employeeId, departmentId, numerator, denominator, value, targetSnapshot, targetMaxSnapshot, direction, status, sourceCompleteness`, a `fromRow`, and a `toUpsertPayload` that emits every column including explicit nulls.

`KpiResultRepository` takes a `SupabaseClient`, and exposes:

```dart
Future<List<KpiResult>> listByPeriod(String period, {String? kpiId});
Future<void> upsertAll(List<KpiResult> rows);
```

`upsertAll` must pass `onConflict: 'kpi_id,period,scope,employee_id,department_id'`… **stop and read this before you write it.** That will NOT work: the unique index is on `coalesce(...)` expressions, and PostgREST cannot name an expression index in `onConflict`. This repo has hit exactly this before — see the note in `role_scorecard_repository.dart` about functional unique indexes. Use **find-then-insert/update**: read the period's rows once, build a key from `(kpiId, period, scope, employeeId ?? '', departmentId ?? '')`, then update the ids that exist and insert the rest.

- [ ] **Step 5: Run it, watch it pass. Analyzer. Commit.**

```bash
flutter analyze lib test
git add supabase/migrations/20260814000004_kpi_results.sql lib/data/models/kpi_result.dart lib/data/repositories/kpi_result_repository.dart test/data/models/kpi_result_test.dart
git commit -m "feat(kpi): the results table, keyed so a company row cannot duplicate"
```

---

### Task 5: The ingestion boundary

**Files:**
- Create: `supabase/migrations/20260814000005_kpi_inputs.sql`
- Create: `lib/data/models/kpi_input.dart`
- Create: `lib/features/kpi_results/exception_aggregation.dart`
- Modify: `lib/data/repositories/kpi_result_repository.dart`
- Test: `test/features/kpi_results/exception_aggregation_test.dart`

**Interfaces:**
- Produces: `KpiException`, `KpiReading`, `enum ReportedVia { app, lark }`; `num confirmedCountFor({required List<KpiException> exceptions, required String period, String? employeeId})`; repository methods `recordException`, `confirmException`, `recordReading`.
- Consumes: nothing from later tasks.

**Do not apply the migration.**

This is the task the spec's "ingestion boundary" section is about. Build the records and the write methods; **do not build a screen** — that is Task 10, gated on a decision the owner has not made.

- [ ] **Step 1: Write the migration**

Two tables. `kpi_exceptions` per the spec: `(id, company_id, kpi_id, employee_id, department_id, occurred_on date, quantity numeric not null default 1, note, reported_by, reported_via text check in ('APP','LARK'), external_ref text, confirmed_at, confirmed_by, created_at)`, with `unique (kpi_id, external_ref)` where `external_ref is not null` so a Lark re-sync is idempotent.

`kpi_readings`: `(id, company_id, kpi_id, period text, scope text check in ('PERSONAL','DEPARTMENT','COMPANY'), employee_id, department_id, numerator numeric, denominator numeric, note, reported_by, reported_via, external_ref, created_at)` with the same `coalesce`-based unique identity index as `kpi_results` — one reading per KPI × period × scope.

RLS on both: read and write for `SUPER_ADMIN/ADMIN/HR/HR_ADMIN` company-scoped, plus a manager for their own reports on rows that name an employee. **Write it deliberately; do not copy `employee_kpis`'s policy** — it carries a self-read clause that is right there and wrong here.

- [ ] **Step 2: Write the failing aggregation test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_input.dart';
import 'package:payroll_flutter/features/kpi_results/exception_aggregation.dart';

KpiException _x({
  required String on,
  num qty = 1,
  String? employeeId,
  DateTime? confirmedAt,
}) => KpiException(
  id: 'x-$on-$qty-${employeeId ?? ''}',
  companyId: 'c',
  kpiId: 'k-1',
  employeeId: employeeId,
  occurredOn: DateTime.parse(on),
  quantity: qty,
  reportedVia: ReportedVia.app,
  confirmedAt: confirmedAt,
);

void main() {
  final confirmed = DateTime(2026, 9, 20);

  test('unconfirmed exceptions do not count', () {
    final n = confirmedCountFor(
      exceptions: [_x(on: '2026-08-04'), _x(on: '2026-08-09')],
      period: '2026-08',
    );
    expect(n, 0);
  });

  test('confirmed exceptions sum their quantity, not their row count', () {
    final n = confirmedCountFor(
      exceptions: [
        _x(on: '2026-08-04', qty: 2, confirmedAt: confirmed),
        _x(on: '2026-08-09', qty: 1, confirmedAt: confirmed),
      ],
      period: '2026-08',
    );
    expect(n, 3);
  });

  test('a late confirmation lands in the month it HAPPENED', () {
    // Confirmed in September, occurred in August. August is the answer;
    // bucketing by confirmed_at would quietly move history.
    final n = confirmedCountFor(
      exceptions: [_x(on: '2026-08-31', confirmedAt: DateTime(2026, 9, 15))],
      period: '2026-08',
    );
    expect(n, 1);
  });

  test('other months are excluded', () {
    final n = confirmedCountFor(
      exceptions: [
        _x(on: '2026-07-31', confirmedAt: confirmed),
        _x(on: '2026-09-01', confirmedAt: confirmed),
      ],
      period: '2026-08',
    );
    expect(n, 0);
  });

  test('filtering by employee narrows to that person', () {
    final xs = [
      _x(on: '2026-08-04', employeeId: 'e-1', confirmedAt: confirmed),
      _x(on: '2026-08-05', employeeId: 'e-2', confirmedAt: confirmed),
    ];
    expect(confirmedCountFor(exceptions: xs, period: '2026-08',
        employeeId: 'e-1'), 1);
    expect(confirmedCountFor(exceptions: xs, period: '2026-08'), 2);
  });

  test('zero confirmed is zero, and the caller decides what that means', () {
    // Returning null here would conflate "none happened" with "none
    // confirmed yet"; that distinction belongs to the compute service, which
    // knows whether any exception rows exist at all.
    expect(confirmedCountFor(exceptions: const [], period: '2026-08'), 0);
  });
}
```

- [ ] **Step 3: Run, fail. Step 4: Implement the models, the aggregation, and the repository methods.**

`confirmedCountFor` filters `confirmedAt != null`, matches `'${occurredOn.year}-${month.toString().padLeft(2,'0')}' == period`, optionally matches `employeeId`, and sums `quantity`.

Repository methods on `KpiResultRepository`:

```dart
Future<void> recordException(KpiException e);
Future<void> confirmException(String id, {required String confirmedBy});
Future<void> recordReading(KpiReading r);
Future<List<KpiException>> exceptionsFor(String kpiId, String period);
Future<List<KpiReading>> readingsFor(String period);
```

`recordException` and `recordReading` stamp `reportedVia`. Document on both that a Lark sync would be another caller of the same method, using `externalRef` for idempotency — the point of the boundary.

- [ ] **Step 5: Run, pass. Analyzer. Commit.**

```bash
flutter analyze lib test
git add supabase/migrations/20260814000005_kpi_inputs.sql lib/data/models/kpi_input.dart lib/features/kpi_results/exception_aggregation.dart lib/data/repositories/kpi_result_repository.dart test/features/kpi_results/exception_aggregation_test.dart
git commit -m "feat(kpi): the ingestion boundary for exceptions and period readings"
```

---

### Task 6: The automatic source registry

**Files:**
- Create: `lib/features/kpi_results/automatic_sources.dart`
- Test: `test/features/kpi_results/automatic_sources_test.dart`

**Interfaces:**
- Produces: `typedef KpiSourceInput = ({num? numerator, num? denominator});`; `abstract class KpiSource { String get key; Future<KpiSourceInput> read({required KpiScope scope, required String period, List<String> employeeIds}); }`; `Map<String, KpiSource> buildSourceRegistry(...)`; four implementations.
- Consumes: `KpiScope`.

The four sources come from data the app already owns, so the HR Manager's whole KPI set computes without anyone typing a number. That is the point: it exercises the engine end to end instead of only on paper.

| Source key | Numerator | Denominator | Reads |
|---|---|---|---|
| `app.attendance.present_days` | Present days in the period | Scheduled days | `AttendanceRepository.listByRange` |
| `app.reviews.completed_on_time` | Reviews completed by their period end | Reviews due | `employee_reviews` |
| ~~`app.hiring.critical_vacancy_aging`~~ | DROPPED 2026-08-15 — `job_listings` has no criticality flag and no target age is stored anywhere | | |
| ~~`app.employees.documentation_complete`~~ | DROPPED 2026-08-15 — `employees` holds no documentation fields; only generated PDFs in `employee_documents` | | |

- [ ] **Step 1: Write the failing test** — each source against fake rows, asserting the pair it returns. Cover, per source: an empty period returns `(null, null)` and NOT `(0, 0)`, because zero scheduled days is missing data rather than a perfect score; and a source restricted to `employeeIds` ignores rows outside the population.

- [ ] **Step 2: Run, fail. Step 3: Implement. Step 4: Run, pass.**

Each source takes its repository by constructor injection so the test hands it fakes and no test touches Supabase.

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/kpi_results/automatic_sources.dart test/features/kpi_results/automatic_sources_test.dart
git commit -m "feat(kpi): four automatic sources from data the app already owns"
```

---

### Task 7: The compute service

**Files:**
- Create: `lib/features/kpi_results/compute_kpi_results.dart`
- Test: `test/features/kpi_results/compute_kpi_results_test.dart`

**Interfaces:**
- Produces: `Future<List<KpiResult>> computeResults({required String period, required List<Kpi> kpis, required List<Employee> employees, required List<RoleScorecard> roles, required Map<String, KpiSource> registry, required List<KpiException> exceptions, required List<KpiReading> readings})`.
- Consumes: everything from Tasks 1–6.

Assembly only — every rule it applies already has its own tested module. Per KPI, for each scope from `scopesFor`: resolve the population, obtain inputs by `data_method`, snapshot the target, evaluate, and produce a row.

Input precedence by `data_method`:

| `data_method` | Numerator from | Denominator from |
|---|---|---|
| `AUTOMATIC` | registry | registry |
| `HYBRID` | registry, minus confirmed exceptions | registry |
| `MANUAL_EXCEPTION` | confirmed exceptions | reading, if any |
| `MANUAL_PERIODIC` | reading | reading |

- [ ] **Step 1: Write the failing test.** Pin at minimum:
  - a `HYBRID` fulfillment-accuracy KPI: registry says 400 fulfilled, two confirmed exceptions → numerator 398, denominator 400, value 0.995, `ON_TRACK`;
  - the same KPI with the registry returning nulls → `NO_DATA` and `MISSING_SOURCE`, and **numerator stays null rather than becoming `0 - 2`**;
  - a `DIRECT` personal KPI producing three rows, with the department row recomputed over the department's population rather than averaged from the personal rows — assert this with two people of *different volumes* so an average and a recompute give different answers, or the test proves nothing;
  - a `SHARED` KPI producing no personal row;
  - target snapshotting: the row carries the target as it is now, and re-running with a changed target produces a changed snapshot while an untouched closed period is not revisited;
  - a `MANUAL_EXCEPTION` KPI with no exception rows at all → `NO_DATA`, distinct from one with rows that are all unconfirmed → `NO_DATA` with `MISSING_SOURCE`, distinct again from confirmed zero.

- [ ] **Step 2: Run, fail. Step 3: Implement. Step 4: Run, pass.**

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/kpi_results/compute_kpi_results.dart test/features/kpi_results/compute_kpi_results_test.dart
git commit -m "feat(kpi): compute a period's results across every eligible scope"
```

---

### Task 8: The results screen

**Files:**
- Create: `lib/features/kpi_results/kpi_results_screen.dart`
- Modify: `lib/app/router.dart`, `lib/app/shell.dart`
- Test: `test/features/kpi_results/kpi_results_screen_test.dart`

Route `/kpi-results`, HR/admin gated — add an explicit clause in `router.dart`'s redirect. **Check whether an existing prefix already covers your path before adding one, and say which you found**; the `/workforce-planning` prefix did not cover `/accountability-chart`, and that was nearly a hole.

A month picker, a scope switch, one row per result: KPI name, value, target, status chip, and where the number came from. A "Recompute this month" action calls Task 7 and upserts.

**`NO_DATA` must not render red.** Use a neutral chip with distinct text — the repo's status chips are tinted background + darker text, no colored borders (`PRODUCT.md`).

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_results_screen.dart';

import '../../support/supabase_stub.dart';

KpiResult _r({
  required String kpiId,
  required KpiStatus status,
  num? value,
  num? target,
}) => KpiResult(
  id: 'res-$kpiId',
  companyId: 'c',
  kpiId: kpiId,
  period: '2026-08',
  scope: KpiScope.company,
  value: value,
  targetSnapshot: target,
  status: status,
  sourceCompleteness: status == KpiStatus.noData
      ? SourceCompleteness.missingSource
      : SourceCompleteness.complete,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester, List<KpiResult> rows) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kpiResultsForPeriodProvider('2026-08').overrideWith((ref) async => rows),
        ],
        child: const MaterialApp(home: KpiResultsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a NO_DATA row does not read the same as an OFF_TRACK row', (
    tester,
  ) async {
    // The whole point of the status rule, made visible. If these two ever
    // render identically the rule is correct and the screen still lies.
    await pump(tester, [
      _r(kpiId: 'k-miss', status: KpiStatus.noData),
      _r(kpiId: 'k-bad', status: KpiStatus.offTrack, value: 0.80, target: 0.99),
    ]);
    expect(find.text('No data'), findsOneWidget);
    expect(find.text('Off track'), findsOneWidget);
  });

  testWidgets('a NO_DATA row shows no invented value', (tester) async {
    await pump(tester, [_r(kpiId: 'k-miss', status: KpiStatus.noData)]);
    expect(find.text('0'), findsNothing);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('a month with no results says so', (tester) async {
    await pump(tester, const []);
    expect(find.textContaining('No results'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it, watch it fail**

Run: `flutter test test/features/kpi_results/kpi_results_screen_test.dart`
Expected: FAIL — the screen and `kpiResultsForPeriodProvider` do not exist.

- [ ] **Step 3: Implement. Step 4: Run it, watch it pass.**

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/kpi_results/kpi_results_screen.dart lib/app/router.dart lib/app/shell.dart test/features/kpi_results/kpi_results_screen_test.dart
git commit -m "feat(kpi): the monthly results screen"
```

---

### Task 9: The dashboard

**Files:**
- Create: `lib/features/kpi_results/kpi_dashboard_screen.dart`
- Modify: `lib/app/router.dart`, `lib/app/shell.dart`
- Test: `test/features/kpi_results/kpi_dashboard_screen_test.dart`

Route `/kpi-dashboard`. Company KPIs for the month, then each department. Off-track first, then no-data, then on-track — a dashboard sorted alphabetically buries the only rows that need action.

- [ ] **Step 1: Write the failing widget test**

```dart
  testWidgets('off-track sorts first, then no-data, then on-track', (
    tester,
  ) async {
    // Feed them in the WRONG order deliberately -- asserting the order you
    // supplied proves nothing about the sort.
    await pump(tester, [
      _r(kpiId: 'k-ok', status: KpiStatus.onTrack, value: 1, target: 0.9),
      _r(kpiId: 'k-miss', status: KpiStatus.noData),
      _r(kpiId: 'k-bad', status: KpiStatus.offTrack, value: 0.1, target: 0.9),
    ]);
    final chips = tester
        .widgetList<Text>(find.byKey(const ValueKey('kpi-status-label')))
        .map((t) => t.data)
        .toList();
    expect(chips, ['Off track', 'No data', 'On track']);
  });

  testWidgets('a month with nothing computed is empty, not red', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(find.textContaining('Nothing computed'), findsOneWidget);
    expect(find.text('Off track'), findsNothing);
  });
```

Use the same `_r` helper and `pump` harness as Task 8, pointed at
`KpiDashboardScreen`. Give each status chip
`key: const ValueKey('kpi-status-label')` so the ordering assertion reads
rendered order rather than provider order.

- [ ] **Step 2: Run it, watch it fail**

Run: `flutter test test/features/kpi_results/kpi_dashboard_screen_test.dart`
Expected: FAIL — the screen does not exist.

- [ ] **Step 3: Implement. Step 4: Run it, watch it pass.**

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/kpi_results/kpi_dashboard_screen.dart lib/app/router.dart lib/app/shell.dart test/features/kpi_results/kpi_dashboard_screen_test.dart
git commit -m "feat(kpi): the monthly company and department dashboard"
```

---

### Task 10: Personal history in the quarterly check-in

**Files:**
- Modify: `lib/features/performance/performance_check_in_screen.dart`
- Test: `test/features/performance/check_in_kpi_history_test.dart`

**Interfaces:**
- Consumes: `KpiResultRepository.listByPeriod`, `KpiResult`, `KpiStatus`.

The spec is explicit that personal KPI history feeds the **existing** quarterly
check-in rather than a new surface, and that monthly dashboards and quarterly
reviews read the same underlying records. Without this task the results engine
produces numbers nobody ever reviews with a person.

Show the last three months of that employee's `PERSONAL` rows: KPI name, each
month's value, and the status. Read-only — the check-in does not edit results.

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('shows three months of the employee\'s own KPI results', (
    tester,
  ) async {
    await pumpCheckIn(tester, employeeId: 'e-1', results: [
      _personal(kpiId: 'k-1', period: '2026-06', value: 0.98,
          status: KpiStatus.onTrack),
      _personal(kpiId: 'k-1', period: '2026-07', value: 0.91,
          status: KpiStatus.offTrack),
      _personal(kpiId: 'k-1', period: '2026-08', value: 0.995,
          status: KpiStatus.onTrack),
    ]);
    expect(find.text('2026-06'), findsOneWidget);
    expect(find.text('2026-07'), findsOneWidget);
    expect(find.text('2026-08'), findsOneWidget);
  });

  testWidgets('another employee\'s rows never appear', (tester) async {
    await pumpCheckIn(tester, employeeId: 'e-1', results: [
      _personal(kpiId: 'k-1', period: '2026-08', value: 0.99,
          status: KpiStatus.onTrack, employeeId: 'e-2'),
    ]);
    expect(find.text('2026-08'), findsNothing);
  });

  testWidgets('a month with no result reads as no data, not as zero', (
    tester,
  ) async {
    await pumpCheckIn(tester, employeeId: 'e-1', results: [
      _personal(kpiId: 'k-1', period: '2026-08', status: KpiStatus.noData),
    ]);
    expect(find.text('No data'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
```

- [ ] **Step 2: Run, fail. Step 3: Implement. Step 4: Run, pass.**

- [ ] **Step 5: Analyzer and commit**

```bash
flutter analyze lib test
git add lib/features/performance/performance_check_in_screen.dart test/features/performance/check_in_kpi_history_test.dart
git commit -m "feat(kpi): the quarterly check-in reads the same monthly results"
```

---

### Task 11: The manual collection surface — GATED

**Do not start this task without an explicit decision from the owner.**

The spec leaves open whether manual input is collected **in this app** or **through Lark forms**. Task 5 built the boundary so the rest of the engine did not have to wait. This task is where the decision becomes code, and the two answers are not similar:

- **In-app:** new routes OUTSIDE the HR/admin gate, and RLS that lets an ordinary employee insert an exception about themselves while reading nobody else's. This makes employees a new class of user of an HR tool. Write the policy deliberately; do not adapt a neighbouring one.
- **Lark:** an edge function following `sync-lark-self-evals`, calling `recordException` / `recordReading` with `reportedVia: ReportedVia.lark` and an `externalRef` for idempotency. No new routes, no new RLS, no employee ever signs in.

If the decision has not been made when the previous ten tasks are done, **stop and report that** rather than picking one. The engine is useful without this task: HR and managers can record through the results screen, and the four automatic sources need nobody at all.

---

## Done when

- Status, population, roll-up eligibility and exception aggregation are pure Dart with unit tests, and `NO_DATA` is provably distinct from `OFF_TRACK` in both the rule and the UI.
- A month's results exist at every eligible scope, with department and company recomputed over their own population rather than averaged from children.
- The automatic sources compute without anyone entering a number. TWO ship: attendance present-days and review completion. `critical_vacancy_aging` and `documentation_complete` were DROPPED by the owner on 2026-08-15 — neither had a definition the schema could answer.
- Exceptions and readings are written through one repository boundary that stamps provenance, with no caller above it knowing which surface produced the record.
- The dashboard shows off-track first and an empty month as empty, not as failure.
- The quarterly check-in shows that person's last three months from the same records the dashboard reads.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.
- Two migrations committed and handed over, **not applied**: `20260814000004`, `20260814000005`.

## Not in this plan

Issues (an off-track result becoming an owned, dated action), external data integrations, and capacity simplification. Each is deferred by the spec to its own plan. Task 11 is in this plan but gated on a decision, and may finish unstarted.
