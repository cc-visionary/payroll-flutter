# Direct-Hours Workload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a responsibility's workload be set as one plain number — "65.8 hours/month" — instead of times-per-month × minutes-each, while keeping the driver/rate model available as an "Advanced: scales with volume" path.

**Architecture:** Add a nullable `hours_per_month` column to `wp_tasks`. It is the direct figure and, when present, **wins** over the driver calc. The one place that turns a task into hours — the `wp_task_computed` view — becomes `coalesce(hours_per_month, times × minutes / 60)`, so every downstream load number (`wp_person_load`, the Balance/Roles tabs, the cost grid) honours it with no further change. The Dart costing mirror (`task_costing.dart`) and the per-task editor (`TaskFormDialog`) and the bulk cost grid gain the same rule. A task is direct-hours **or** driver-calc, never both: setting direct hours nulls the driver/rate columns.

**Tech Stack:** Flutter (Material 3, Riverpod), Supabase (Postgres views), Deno-less pure Dart for the costing logic. Tests via `flutter test`; static gate `flutter analyze` (errors only — the repo does not gate on `dart format`).

## Global Constraints

- **`flutter analyze` must report zero errors.** Pre-existing warnings are acceptable; add no new ones in touched files. Do **not** run `dart format` — match each file's surrounding style.
- **Full suite green** (`flutter test`) — currently ~974 passing.
- **Migrations are forward-only.** Prod DB is GameCove Inc., the only company. The `service_role` key in `env/prod.json` is used read-only to verify; flag each use.
- **Run command:** `flutter run -d linux --dart-define-from-file=env/prod.json` (not individual `--dart-define` flags). Not needed for this plan, but that is how the app launches.
- **Direct hours wins.** When `hours_per_month` is non-null it is the workload; the driver/rate columns are ignored and are nulled on write. A direct-hours task never "grows" (a manual figure is flat at any multiplier).
- **"Costed" is derived, never stored** — a task is costed when it resolves to > 0 hours by either path.

---

### Task 1: Migration — `hours_per_month` column + view

**Files:**
- Create: `supabase/migrations/20260723000003_task_direct_hours.sql`

**Interfaces:**
- Produces: `wp_tasks.hours_per_month numeric` (nullable); `wp_task_computed.hours_per_month_base` now = `coalesce(hours_per_month, times × minutes / 60)`; `wp_task_computed.is_growing` is `false` whenever `hours_per_month` is set. The view's output columns are **unchanged in name, order and type**, so `wp_person_load` (which reads only `hours_per_month_base`, `is_growing`, `owner_employee_id`, `task_id`) keeps working untouched.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260723000003_task_direct_hours.sql`:

```sql
-- Direct-hours workload: a plain hours/month figure that wins over the
-- times x minutes driver calc.
--
-- HRCI's own model for "how much work" is a plain estimatedHours figure; the
-- times x minutes x driver machinery is this app's addition for volume work.
-- Making the simple field the default is what removes the editing friction.
--
-- A task is EITHER direct-hours OR driver-calc: when hours_per_month is set the
-- driver/rate columns are ignored (and nulled on write by the app). A
-- direct-hours task is flat -- it never responds to the growth multiplier,
-- because a manual number does not scale with volume.

alter table wp_tasks
  add column if not exists hours_per_month numeric
    check (hours_per_month is null or hours_per_month >= 0);

comment on column wp_tasks.hours_per_month is
  'Direct monthly-hours figure. When set it is the workload and wins over the '
  'times x minutes driver calc; the driver/rate columns are then ignored.';

-- Re-point the one place that turns a task into hours. Output columns are
-- unchanged in name/order/type, so wp_person_load needs no change. The outer
-- column list is written explicitly (not x.*) so the added inner column does
-- not shift the output shape.
create or replace view wp_task_computed with (security_invoker = true) as
select
  x.task_id,
  x.company_id,
  x.owner_employee_id,
  x.node_id,
  x.skill_tier,
  x.risk,
  x.is_growing,
  x.times_per_month_base,
  x.minutes_each,
  case when x.direct_hours is not null
       then x.direct_hours
       else x.times_per_month_base * x.minutes_each / 60.0 end as hours_per_month_base
from (
  select
    t.id                as task_id,
    t.company_id,
    t.owner_employee_id,
    t.node_id,
    t.skill_tier,
    t.risk,
    t.hours_per_month   as direct_hours,
    -- A direct-hours task is never growing: only a driver-bound, growing task
    -- (with no direct figure overriding it) responds to the multiplier.
    (t.hours_per_month is null
       and t.times_source = 'driver'
       and coalesce(d.grows, false)) as is_growing,
    case when t.times_source = 'driver'
         then coalesce(d.value, 0) * t.driver_factor
         else coalesce(t.times_manual, 0) end as times_per_month_base,
    case when t.minutes_source = 'rate'
         then coalesce(r.minutes_each, 0)
         else coalesce(t.minutes_manual, 0) end as minutes_each
  from wp_tasks t
  left join wp_drivers d on d.id = t.driver_id
  left join wp_rates   r on r.id = t.rate_id
) x;
```

- [ ] **Step 2: Apply to prod**

Run: `supabase db push`
Expected: `Applying migration 20260723000003_task_direct_hours.sql...` then `Finished supabase db push.`

- [ ] **Step 3: Verify the view still returns the same shape and unaffected rows are unchanged**

This reads prod with the `service_role` key (read-only — flag to the user). Run:

```bash
URL=$(python3 -c "import json;print(json.load(open('env/prod.json'))['SUPABASE_URL'])")
KEY=$(python3 -c "import json;print(json.load(open('env/prod.json'))['SUPABASE_SERVICE_ROLE_KEY'])")
curl -s "$URL/rest/v1/wp_task_computed?select=task_id,is_growing,hours_per_month_base&limit=3" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: three rows with the same columns as before (a driver task still shows its computed hours; nothing null-crashes). No `hours_per_month` value is set yet on any row, so every `hours_per_month_base` equals its old `times × minutes / 60`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260723000003_task_direct_hours.sql
git commit -m "data(workforce): add hours_per_month direct-workload column + view

A nullable hours_per_month on wp_tasks; wp_task_computed now uses
coalesce(hours_per_month, times x minutes / 60) and marks a direct-hours
task not-growing. Output columns unchanged, so wp_person_load is
untouched. APPLIED to prod; existing rows unaffected (none set yet).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `WpTask` model — `hoursPerMonth` field

**Files:**
- Modify: `lib/data/models/workforce_planning.dart` (the `WpTask` class: fields, constructor, `fromRow`, `copyWithSort`, `toUpsert`)
- Test: `test/data/models/wp_task_direct_hours_test.dart`

**Interfaces:**
- Consumes: the `hours_per_month` column from Task 1.
- Produces: `WpTask.hoursPerMonth` (`double?`); `WpTask.fromRow` reads `hours_per_month`; `WpTask.toUpsert` writes `hours_per_month` and, when it is non-null, nulls `times_manual`/`driver_id`/`minutes_manual`/`rate_id` with both sources `'manual'`; `copyWithSort` carries it.

- [ ] **Step 1: Write the failing test**

Create `test/data/models/wp_task_direct_hours_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('fromRow reads hours_per_month', () {
    final t = WpTask.fromRow({
      'id': 't1', 'company_id': 'c', 'name': 'Pack', 'hours_per_month': 65.8,
    });
    expect(t.hoursPerMonth, 65.8);
  });

  test('fromRow leaves hoursPerMonth null when absent', () {
    final t = WpTask.fromRow({'id': 't1', 'company_id': 'c', 'name': 'Pack'});
    expect(t.hoursPerMonth, isNull);
  });

  test('toUpsert writes hours_per_month and nulls the driver path when direct', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Pack', hoursPerMonth: 65.8,
      timesSource: 'driver', driverId: 'd1', minutesSource: 'rate', rateId: 'r1',
    );
    final u = t.toUpsert('c');
    expect(u['hours_per_month'], 65.8);
    expect(u['times_manual'], isNull);
    expect(u['driver_id'], isNull);
    expect(u['minutes_manual'], isNull);
    expect(u['rate_id'], isNull);
    expect(u['times_source'], 'manual');
    expect(u['minutes_source'], 'manual');
  });

  test('toUpsert keeps the driver path when there is no direct figure', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Pack',
      timesSource: 'driver', driverId: 'd1', minutesSource: 'manual', minutesManual: 30,
    );
    final u = t.toUpsert('c');
    expect(u['hours_per_month'], isNull);
    expect(u['driver_id'], 'd1');
    expect(u['minutes_manual'], 30);
  });

  test('copyWithSort carries hoursPerMonth', () {
    const t = WpTask(id: 't1', companyId: 'c', name: 'Pack', hoursPerMonth: 10);
    expect(t.copyWithSort(areaSort: 1, taskSort: 2).hoursPerMonth, 10);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/models/wp_task_direct_hours_test.dart`
Expected: FAIL — `hoursPerMonth` is not defined / named parameter not found.

- [ ] **Step 3: Add the field to `WpTask`**

In `lib/data/models/workforce_planning.dart`, add the field after `isExpectation`:

```dart
  final bool isExpectation;

  /// Direct monthly-hours figure. When non-null it IS the workload and wins
  /// over the times x minutes driver calc (mirrors wp_task_computed). A
  /// direct-hours task never responds to the growth multiplier.
  final double? hoursPerMonth;
```

Add to the constructor (after `this.isExpectation = false`):

```dart
    this.isExpectation = false, this.hoursPerMonth});
```

In `fromRow`, after `isExpectation: r['is_expectation'] as bool? ?? false`:

```dart
    isExpectation: r['is_expectation'] as bool? ?? false,
    hoursPerMonth: _dn(r['hours_per_month']));
```

In `copyWithSort`, after `isExpectation: isExpectation`:

```dart
    isExpectation: isExpectation, hoursPerMonth: hoursPerMonth);
```

Replace `toUpsert` so a direct figure nulls the driver path. Change the body's tail:

```dart
  Map<String, dynamic> toUpsert(String companyId) {
    final direct = hoursPerMonth != null;
    return {
      'company_id': companyId, 'name': name.trim(), 'node_id': nodeId,
      'brand_scope': _s(brandScope), 'cadence': _s(cadence),
      'times_source': direct ? 'manual' : timesSource,
      'times_manual': direct ? null : (timesSource == 'driver' ? null : timesManual),
      'driver_id': direct ? null : (timesSource == 'driver' ? driverId : null),
      'driver_factor': driverFactor,
      'minutes_source': direct ? 'manual' : minutesSource,
      'minutes_manual': direct ? null : (minutesSource == 'rate' ? null : minutesManual),
      'rate_id': direct ? null : (minutesSource == 'rate' ? rateId : null),
      'hours_per_month': hoursPerMonth,
      'skill_tier': _s(skillTier), 'risk': _s(risk), 'capability': _s(capability),
      'owner_employee_id': ownerEmployeeId, 'role_scorecard_id': roleScorecardId,
      'responsibility_area': _s(responsibilityArea), 'notes': _s(notes),
      'is_expectation': isExpectation,
      'area_sort': areaSort, 'task_sort': taskSort,
    };
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/data/models/wp_task_direct_hours_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Confirm nothing else broke and analyze is clean**

Run: `flutter analyze lib/data/models/workforce_planning.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/workforce_planning.dart test/data/models/wp_task_direct_hours_test.dart
git commit -m "feat(workforce): WpTask.hoursPerMonth direct-workload field

fromRow reads hours_per_month; toUpsert writes it and, when set, nulls
the driver/rate path so a task is direct-hours OR driver-calc, never
both; copyWithSort carries it.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Costing logic — direct hours in `task_costing.dart`

**Files:**
- Modify: `lib/features/workforce_planning/task_costing.dart` (`CostDraft`: field, `fromTask`, `copyWith`, `applyTo`, `==`, `hashCode`; the functions `draftHoursPerMonth`, `draftIsCosted`, `draftIsGrowing`, `draftPatch`)
- Test: `test/features/workforce_planning/task_costing_test.dart` (append a group)

**Interfaces:**
- Consumes: `WpTask.hoursPerMonth` (Task 2).
- Produces: `CostDraft.hoursPerMonth` (`double?`) + `copyWith({double? hoursPerMonth, bool clearHoursPerMonth})`; `draftHoursPerMonth` returns the direct figure when set; `draftIsCosted` is true when direct hours > 0 OR both driver-calc halves > 0; `draftIsGrowing` is false when direct hours set; `draftPatch` writes `hours_per_month` and nulls the driver path when direct.

- [ ] **Step 1: Write the failing test**

Append to `test/features/workforce_planning/task_costing_test.dart` (inside `main()`, before its final `}`):

```dart
  group('direct hours wins over the driver calc', () {
    test('draftHoursPerMonth returns the direct figure when set', () {
      const d = CostDraft(
          timesSource: 'driver', driverId: 'd1',
          minutesSource: 'rate', rateId: 'r1', hoursPerMonth: 65.8);
      expect(draftHoursPerMonth(d, _drivers, _rates), 65.8);
    });

    test('a direct figure counts as costed and is never growing', () {
      const d = CostDraft(
          timesSource: 'driver', driverId: 'd1', // a growing driver...
          minutesSource: 'manual', hoursPerMonth: 12);
      expect(draftIsCosted(d, _drivers, _rates), isTrue);
      expect(draftIsGrowing(d, _drivers), isFalse,
          reason: 'a manual hours figure is flat at any multiplier');
    });

    test('draftPatch writes hours_per_month and clears the driver path', () {
      const d = CostDraft(
          timesSource: 'driver', driverId: 'd1', driverFactor: 2,
          minutesSource: 'rate', rateId: 'r1', hoursPerMonth: 40);
      final p = draftPatch(d);
      expect(p['hours_per_month'], 40);
      expect(p['times_manual'], isNull);
      expect(p['driver_id'], isNull);
      expect(p['minutes_manual'], isNull);
      expect(p['rate_id'], isNull);
      expect(p['times_source'], 'manual');
    });

    test('with no direct figure the driver calc still applies', () {
      const d = CostDraft(
          timesSource: 'manual', timesManual: 20,
          minutesSource: 'manual', minutesManual: 45);
      expect(draftHoursPerMonth(d, _drivers, _rates), 15.0); // 20*45/60
      expect(draftPatch(d)['hours_per_month'], isNull);
    });

    test('clearHoursPerMonth returns to the driver calc', () {
      const d = CostDraft(
          timesSource: 'manual', timesManual: 20,
          minutesSource: 'manual', minutesManual: 45, hoursPerMonth: 99);
      final back = d.copyWith(clearHoursPerMonth: true);
      expect(back.hoursPerMonth, isNull);
      expect(draftHoursPerMonth(back, _drivers, _rates), 15.0);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/task_costing_test.dart`
Expected: FAIL — `hoursPerMonth` is not a parameter of `CostDraft`.

- [ ] **Step 3: Add the field and thread it through `CostDraft`**

In `lib/features/workforce_planning/task_costing.dart`, add the constructor param and field:

```dart
  const CostDraft({
    required this.timesSource,
    this.timesManual,
    this.driverId,
    this.driverFactor = 1,
    required this.minutesSource,
    this.minutesManual,
    this.rateId,
    this.nodeId,
    this.hoursPerMonth,
  });
```

```dart
  final String? nodeId;

  /// Direct monthly hours. When non-null it wins over the driver calc.
  final double? hoursPerMonth;
```

In `fromTask`, add `hoursPerMonth: t.hoursPerMonth,` to the returned `CostDraft`.

In `copyWith`, add the parameter and clear flag, and thread it:

```dart
  CostDraft copyWith({
    String? timesSource,
    double? timesManual,
    String? driverId,
    double? driverFactor,
    String? minutesSource,
    double? minutesManual,
    String? rateId,
    String? nodeId,
    double? hoursPerMonth,
    bool clearTimesManual = false,
    bool clearDriverId = false,
    bool clearMinutesManual = false,
    bool clearRateId = false,
    bool clearNodeId = false,
    bool clearHoursPerMonth = false,
  }) =>
      CostDraft(
        timesSource: timesSource ?? this.timesSource,
        timesManual: clearTimesManual ? null : (timesManual ?? this.timesManual),
        driverId: clearDriverId ? null : (driverId ?? this.driverId),
        driverFactor: driverFactor ?? this.driverFactor,
        minutesSource: minutesSource ?? this.minutesSource,
        minutesManual:
            clearMinutesManual ? null : (minutesManual ?? this.minutesManual),
        rateId: clearRateId ? null : (rateId ?? this.rateId),
        nodeId: clearNodeId ? null : (nodeId ?? this.nodeId),
        hoursPerMonth:
            clearHoursPerMonth ? null : (hoursPerMonth ?? this.hoursPerMonth),
      );
```

In `applyTo`, add `hoursPerMonth: hoursPerMonth,` to the returned `WpTask`.

Extend `==` and `hashCode` to include `hoursPerMonth`:

```dart
      other.rateId == rateId &&
      other.nodeId == nodeId &&
      other.hoursPerMonth == hoursPerMonth;

  @override
  int get hashCode => Object.hash(timesSource, timesManual, driverId,
      driverFactor, minutesSource, minutesManual, rateId, nodeId, hoursPerMonth);
```

- [ ] **Step 4: Make the computations honour it**

Replace the four functions:

```dart
double draftHoursPerMonth(
  CostDraft d,
  Map<String, WpDriver> driverById,
  Map<String, WpRate> rateById,
) {
  if (d.hoursPerMonth != null) return d.hoursPerMonth!;
  return draftTimesPerMonth(d, driverById) * draftMinutesEach(d, rateById) / 60.0;
}

bool draftIsCosted(
  CostDraft d,
  Map<String, WpDriver> driverById,
  Map<String, WpRate> rateById,
) {
  if ((d.hoursPerMonth ?? 0) > 0) return true;
  return draftTimesPerMonth(d, driverById) > 0 && draftMinutesEach(d, rateById) > 0;
}

bool draftIsGrowing(CostDraft d, Map<String, WpDriver> driverById) =>
    d.hoursPerMonth == null &&
    d.timesSource == 'driver' &&
    (driverById[d.driverId]?.grows ?? false);
```

And `draftPatch`:

```dart
Map<String, dynamic> draftPatch(CostDraft d) {
  if (d.hoursPerMonth != null) {
    return {
      'node_id': d.nodeId,
      'hours_per_month': d.hoursPerMonth,
      'times_source': 'manual', 'times_manual': null, 'driver_id': null,
      'driver_factor': d.driverFactor,
      'minutes_source': 'manual', 'minutes_manual': null, 'rate_id': null,
    };
  }
  return {
    'node_id': d.nodeId,
    'hours_per_month': null,
    'times_source': d.timesSource,
    'times_manual': d.timesSource == 'driver' ? null : d.timesManual,
    'driver_id': d.timesSource == 'driver' ? d.driverId : null,
    'driver_factor': d.driverFactor,
    'minutes_source': d.minutesSource,
    'minutes_manual': d.minutesSource == 'rate' ? null : d.minutesManual,
    'rate_id': d.minutesSource == 'rate' ? d.rateId : null,
  };
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/task_costing_test.dart`
Expected: PASS (all prior tests + the 5 new ones).

Note: the existing test `'patches only costing columns'` asserts `draftPatch(d).keys.toSet()` equals a fixed set. That set now also contains `hours_per_month`. **This is an intended contract change** — update that test's expected set to include `'hours_per_month'`, and add a one-line comment saying why. Do **not** weaken any other assertion.

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/workforce_planning/task_costing.dart`
Expected: `No issues found!`

```bash
git add lib/features/workforce_planning/task_costing.dart test/features/workforce_planning/task_costing_test.dart
git commit -m "feat(workforce): direct hours wins in the costing logic

CostDraft carries hoursPerMonth; draftHoursPerMonth/IsCosted/IsGrowing/
Patch honour it (direct figure wins, never grows, clears the driver
path). The 'patches only costing columns' test's column set gains
hours_per_month -- reported, not silently changed.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Per-task editor — the Workload field + Advanced expander

**Files:**
- Modify: `lib/features/workforce_planning/tabs/task_form_dialog.dart` (`buildTaskFromForm`, the dialog state + `build`)
- Test: `test/features/workforce_planning/task_form_dialog_test.dart` (append)

**Interfaces:**
- Consumes: `WpTask.hoursPerMonth` (Task 2).
- Produces: `buildTaskFromForm` gains a `String? hoursPerMonthText` param; when it parses to a number the result is a direct-hours task (driver path nulled), otherwise the existing times/minutes path is used. The dialog shows a "Workload (hours/month)" field by default and hides the times/minutes controls inside an "Advanced: scales with volume" `ExpansionTile`.

- [ ] **Step 1: Write the failing test**

Append to `test/features/workforce_planning/task_form_dialog_test.dart` (inside `main()`):

```dart
  test('buildTaskFromForm: a workload figure produces a direct-hours task', () {
    final t = buildTaskFromForm(
      companyId: 'c', name: 'Pack',
      timesSource: 'driver', minutesSource: 'rate',
      driverId: 'd1', rateId: 'r1',
      hoursPerMonthText: '65.8',
    );
    expect(t.hoursPerMonth, 65.8);
    expect(t.driverId, isNull, reason: 'direct hours clears the driver path');
    expect(t.rateId, isNull);
  });

  test('buildTaskFromForm: a blank workload falls to the times/minutes path', () {
    final t = buildTaskFromForm(
      companyId: 'c', name: 'Pack',
      timesSource: 'manual', minutesSource: 'manual',
      timesManualText: '20', minutesManualText: '45',
      hoursPerMonthText: '  ',
    );
    expect(t.hoursPerMonth, isNull);
    expect(t.timesManual, 20);
    expect(t.minutesManual, 45);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart`
Expected: FAIL — `hoursPerMonthText` is not a parameter of `buildTaskFromForm`.

- [ ] **Step 3: Add `hoursPerMonthText` to `buildTaskFromForm`**

In `lib/features/workforce_planning/tabs/task_form_dialog.dart`, add the parameter to `buildTaskFromForm` (alongside `timesManualText`), and at the **top of the body** short-circuit to a direct-hours task:

```dart
WpTask buildTaskFromForm({
  // ...existing params...
  String? hoursPerMonthText,
}) {
  final direct = double.tryParse((hoursPerMonthText ?? '').trim());
  // ...existing computation of ids/values...
  return WpTask(
    // ...existing fields, but override the four driver-path fields when direct:
    timesSource: direct != null ? 'manual' : timesSource,
    timesManual: direct != null
        ? null
        : (timesSource == 'manual' ? double.tryParse((timesManualText ?? '').trim()) : null),
    driverId: direct != null ? null : (timesSource == 'driver' ? driverId : null),
    minutesSource: direct != null ? 'manual' : minutesSource,
    minutesManual: direct != null
        ? null
        : (minutesSource == 'manual' ? double.tryParse((minutesManualText ?? '').trim()) : null),
    rateId: direct != null ? null : (minutesSource == 'rate' ? rateId : null),
    hoursPerMonth: direct,
    // ...remaining unchanged fields (name, nodeId, cadence, roleScorecardId,
    //    responsibilityArea, ownerEmployeeId, etc.)...
  );
}
```

(Keep every other field exactly as the current implementation builds it — only the six lines above and the new `hoursPerMonth` change.)

- [ ] **Step 4: Run the pure test to verify it passes**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart -N buildTaskFromForm`
Expected: PASS for both new `buildTaskFromForm` tests (existing tests still pass).

- [ ] **Step 5: Add the Workload field + Advanced expander to the dialog**

In `_TaskFormDialogState`, add a controller near the other field controllers:

```dart
  late final _hoursCtl = TextEditingController(
      text: widget.existing?.hoursPerMonth?.toString() ?? '');
```

Dispose it in `dispose()` alongside the others.

In `build`, **above** the times/minutes `SegmentedButton`s, add the primary field:

```dart
    TextField(
      controller: _hoursCtl,
      decoration: const InputDecoration(
        labelText: 'Workload (hours / month)',
        hintText: 'e.g. 10',
        helperText: 'One number. Leave blank to drive by volume below.',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: 8),
```

Wrap the existing times/minutes controls (the two `SegmentedButton`s and their value fields) in an expander so they are the advanced path:

```dart
    ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: _hoursCtl.text.trim().isEmpty &&
          (widget.existing?.timesSource == 'driver' ||
              widget.existing?.minutesSource == 'rate'),
      title: const Text('Advanced: scales with volume'),
      children: [
        // ...move the existing times/minutes widgets here unchanged...
      ],
    ),
```

In `_save`, pass the field through to `buildTaskFromForm`:

```dart
      hoursPerMonthText: _hoursCtl.text,
```

- [ ] **Step 6: Write a widget test for the dialog**

Append to `test/features/workforce_planning/task_form_dialog_test.dart`:

```dart
  testWidgets('the dialog leads with a Workload field and saves it', (tester) async {
    WpTask? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            saved = await showDialog<WpTask>(
              context: context,
              builder: (_) => const TaskFormDialog(
                  companyId: 'c', nodes: [], drivers: [], rates: [], employees: []),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Workload (hours / month)'), '12');
    await tester.enterText(find.widgetWithText(TextField, 'Name').first, 'Do the thing');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.hoursPerMonth, 12);
  });
```

(If the Name field's label differs, match the actual label used in the dialog — read the current `build` to confirm before writing the finder.)

- [ ] **Step 7: Run the dialog test**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart`
Expected: PASS.

- [ ] **Step 8: Analyze + commit**

Run: `flutter analyze lib/features/workforce_planning/tabs/task_form_dialog.dart`
Expected: `No issues found!`

```bash
git add lib/features/workforce_planning/tabs/task_form_dialog.dart test/features/workforce_planning/task_form_dialog_test.dart
git commit -m "feat(workforce): per-task editor leads with a Workload field

buildTaskFromForm takes hoursPerMonthText; a parseable figure makes a
direct-hours task (driver path nulled), else the times/minutes path is
used. The dialog shows Workload (hours/month) by default and hides the
times/minutes controls under an 'Advanced: scales with volume' expander.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Bulk cost grid — a direct-hours column

**Files:**
- Modify: `lib/features/workforce_planning/tabs/tasks_tab.dart` (`_costTable` and its row cells)
- Test: `test/features/workforce_planning/tasks_tab_costing_test.dart` (append)

**Interfaces:**
- Consumes: `CostDraft.hoursPerMonth`, `draftHoursPerMonth`, `draftPatch` (Task 3).
- Produces: the grid gains a leading **Hours/mo** editable cell; typing a value sets `hoursPerMonth` on that row's draft (and the live hours + Save use it); the existing times/minutes/node cells remain for the advanced path but are visually de-emphasised when a direct figure is present.

- [ ] **Step 1: Write the failing test**

Append to `test/features/workforce_planning/tasks_tab_costing_test.dart` (inside `main()`; reuse the file's existing `_FakeRepo`, `_host`, `_enterCostMode` helpers):

```dart
  testWidgets('typing a direct Hours figure computes and saves it', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await _enterCostMode(tester);

    await tester.enterText(find.byKey(const ValueKey('hours-t1')), '30');
    await tester.pumpAndSettle();

    expect(find.text('30.0'), findsOneWidget); // live hours
    await tester.tap(find.text('Save 1'));
    await tester.pumpAndSettle();

    final patch = repo.calls.single['t1']!;
    expect(patch['hours_per_month'], 30);
    expect(patch['driver_id'], isNull);
    expect(patch['times_manual'], isNull);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/tasks_tab_costing_test.dart`
Expected: FAIL — no widget with key `hours-t1`.

- [ ] **Step 3: Add the Hours column to `_costTable`**

In `_costTable`, add a `DataColumn(label: Text('Hours/mo'))` as the **second** column (after Task, before Node), and in each `DataRow` add a matching direct-hours cell:

```dart
                DataCell(SizedBox(
                  width: 70,
                  child: TextFormField(
                    key: ValueKey('hours-${t.id}'),
                    initialValue: _draftFor(t).hoursPerMonth == null
                        ? ''
                        : _num(_draftFor(t).hoursPerMonth!),
                    decoration: const InputDecoration(isDense: true, hintText: 'direct'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (raw) {
                      final v = parseCostField(raw);
                      _edit(
                        t,
                        v == null
                            ? _draftFor(t).copyWith(clearHoursPerMonth: true)
                            : _draftFor(t).copyWith(hoursPerMonth: v),
                      );
                    },
                  ),
                )),
```

The existing live-hours cell already calls `draftHoursPerMonth(...)`, which now honours the direct figure — no change needed there. The Node/Times/Minutes cells stay; wrap their `_costedHoursCell`/driver widgets so they read as secondary when `_draftFor(t).hoursPerMonth != null` (e.g. `Opacity(opacity: draft.hoursPerMonth == null ? 1 : 0.4, child: ...)`), so it is visually clear which path is active.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/tasks_tab_costing_test.dart`
Expected: PASS (new test + all existing grid tests).

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze lib/features/workforce_planning/tabs/tasks_tab.dart`
Expected: `No issues found!`

```bash
git add lib/features/workforce_planning/tabs/tasks_tab.dart test/features/workforce_planning/tasks_tab_costing_test.dart
git commit -m "feat(workforce): direct Hours/mo column in the bulk cost grid

A leading editable Hours cell sets hoursPerMonth on the row; the
times/minutes/node cells de-emphasise when a direct figure is present.
Live hours and Save already route through draftHoursPerMonth/draftPatch.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Full-suite gate + live smoke

**Files:** none (verification only)

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: `All tests passed!` (prior count + the new tests from Tasks 2–5).

- [ ] **Step 2: Analyze (whole project)**

Run: `flutter analyze`
Expected: zero lines containing `error •`. (Pre-existing warnings are fine.)

- [ ] **Step 3: Live smoke — set one task's direct hours end to end**

This writes ONE prod row with the `service_role` key (flag to the user first; it is a reversible costing edit on an already-costed task). Pick any costed task id from the Tasks tab, then:

```bash
URL=$(python3 -c "import json;print(json.load(open('env/prod.json'))['SUPABASE_URL'])")
KEY=$(python3 -c "import json;print(json.load(open('env/prod.json'))['SUPABASE_SERVICE_ROLE_KEY'])")
# read the row's current computed hours
curl -s "$URL/rest/v1/wp_task_computed?select=hours_per_month_base&task_id=eq.<TASK_ID>" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
# set a direct figure, then re-read: the view must now return exactly 7
curl -s "$URL/rest/v1/wp_tasks?id=eq.<TASK_ID>" -X PATCH \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" -d '{"hours_per_month": 7}'
curl -s "$URL/rest/v1/wp_task_computed?select=hours_per_month_base,is_growing&task_id=eq.<TASK_ID>" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Expected: after the PATCH the view returns `hours_per_month_base = 7` and `is_growing = false`, proving the view honours the direct figure. Then **restore** the row (`PATCH {"hours_per_month": null}`) so no test value is left in prod, and confirm the view returns to its original computed hours.

- [ ] **Step 4: Report**

Summarise to the user: what shipped (direct-hours workload, default in both editors), that the migration is applied to prod, the smoke result, and the honest caveat that no GUI run has happened — the dialog/grid render is verified by widget tests, not by eye.

---

## Notes for the implementer

- **This is step 1 of the accountability-model spec** (`docs/superpowers/specs/2026-07-23-accountability-model-design.md`). It intentionally ships with **no core-model migration** and **no sharing** — just the simpler workload editing. Do not pull in criticality, assignments, or the needs-attention strip; those are later steps with their own plans.
- **Do not run `dart format`.** Match each file's existing style (the repo has mixed formatter output and gates only on `flutter analyze`).
- **If any existing test fails**, report exactly which and why, and what you changed — do not silently rewrite assertions to make them pass. The one intended contract change is the `draftPatch` column-set test in Task 3, called out there.
- **Concurrent sessions share this repo.** If unexpected uncommitted changes appear, check `git reflog`/`git status` before assuming data loss.
