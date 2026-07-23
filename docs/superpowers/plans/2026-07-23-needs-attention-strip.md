# Needs-Attention Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A derived "needs attention" strip at the top of the Balance tab that surfaces what a manager should fix — grouped in the HRBoK gap categories People / Process / Structure / Tools, ranked by severity, each row deep-linking to where the fix lives.

**Architecture:** One pure derivation (`needs_attention.dart`) aggregates the signals computable on CURRENT data into a ranked `List<AttentionItem>`; it reuses step-3a's orphan predicate (extracted to a shared `orphanTasks` helper, no third copy) and the KPI-library's existing `kpiIsAssigned`. A self-contained `NeedsAttentionStrip` `ConsumerWidget` watches its own inputs so the Balance tab needn't gate on them, and maps each item's target to a hub-tab switch (`DefaultTabController`) or a route push. This is the second half of step 3; signals that need `wp_task_assignments` (shares≠100%, literal no-PRIMARY, CONTRIBUTOR-based key-person risk) are deliberately deferred to step 4.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), `flutter_test`. No Supabase changes — pure derivation over existing providers.

## Global Constraints

- Repo gates on `flutter analyze` only (0 errors). Do NOT run `dart format`; match each file's surrounding style.
- NO migration — this reads existing columns/providers only.
- Managers-only surface (the whole workforce hub is HR/admin gated); no employee-facing anything.
- Signals shipped here are exactly those correct on pre-`wp_task_assignments` data. Do NOT implement shares≠100%, literal "no PRIMARY assignment", or CONTRIBUTOR-based key-person risk — those belong to step 4 and would be wrong now.
- HRBoK gap categories are exactly **People, Process, Structure, Tools** (spec §"Needs attention"); Tools has no signals today but the category is kept.
- Design system (`PRODUCT.md`): `StatusChip`/`StatusTone` (`lib/app/status_colors.dart`) — red 🔴 = `StatusTone.danger` (high severity), amber 🟡 = `StatusTone.warning` (medium); numbers via `AppTheme.mono`; `TabIntro`/`WpGlossary` for new vocabulary. Single purple CTA.
- Reuse, don't re-derive: the orphan predicate is extracted from `unassigned_workspace.dart` (step 3a) into a shared `orphanTasks` helper; KPI "measuring nobody" uses the existing `kpiIsAssigned` (`lib/features/kpi_library/kpi_rows.dart`); over-capacity uses `capacity_math.dart` (`loadStatus(personLoad(p)) == LoadStatus.over`).

---

## File Structure

- `lib/features/workforce_planning/unassigned_workspace.dart` — **modify.** Extract the orphan predicate into `List<WpTask> orphanTasks({required List<WpTask> tasks, required List<Employee> employees})`; have `buildUnassignedWorkspace` call it (behavior unchanged).
- `lib/features/workforce_planning/needs_attention.dart` — **create.** `AttentionCategory`, `AttentionSeverity`, `AttentionTarget`, `AttentionItem`, `buildNeedsAttention(...)`. Pure.
- `lib/features/workforce_planning/tabs/needs_attention_strip.dart` — **create.** Self-contained `NeedsAttentionStrip` `ConsumerWidget` + deep-link handling.
- `lib/features/workforce_planning/tabs/balance_tab.dart` — **modify.** Embed `const NeedsAttentionStrip()` at the top of the tab body.
- `lib/features/workforce_planning/tabs/tab_intro.dart` — **modify.** Add `WpGlossary.needsAttention`.
- Tests: `test/features/workforce_planning/needs_attention_test.dart` (create); `unassigned_workspace_test.dart` (must stay green after the refactor).

---

### Task 1: The needs-attention derivation

**Files:**
- Modify: `lib/features/workforce_planning/unassigned_workspace.dart` (extract `orphanTasks`)
- Create: `lib/features/workforce_planning/needs_attention.dart`
- Test: `test/features/workforce_planning/needs_attention_test.dart`
- Verify still green: `test/features/workforce_planning/unassigned_workspace_test.dart`

**Interfaces:**
- Produces:
  - `List<WpTask> orphanTasks({required List<WpTask> tasks, required List<Employee> employees})` (in `unassigned_workspace.dart`) — ACTIVE tasks reaching nobody, per the step-3a predicate.
  - `enum AttentionCategory { people, process, structure, tools }`
  - `enum AttentionSeverity { high, medium }`
  - `enum AttentionTarget { balance, roles, tasks, unassigned, kpiLibrary }`
  - `class AttentionItem { final AttentionCategory category; final AttentionSeverity severity; final String label; final int count; final AttentionTarget target; }`
  - `List<AttentionItem> buildNeedsAttention({required List<WpPersonLoad> loads, required List<WpTask> tasks, required List<Employee> employees, required List<RoleScorecard> cards, required List<Kpi> kpis, required Map<String, List<KpiAssignee>> kpiAssignedByKpi})`

**Signals (each emitted only when count > 0), category · severity · target:**
- People · high · balance — people over capacity: `loads.where((p) => loadStatus(personLoad(p)) == LoadStatus.over)`.
- People · high · unassigned — CRITICAL unassigned work: `orphanTasks(...).where((t) => t.criticality == 'CRITICAL')`.
- People · medium · unassigned — unassigned accountabilities (all): `orphanTasks(...).length`.
- Process · medium · tasks — uncosted essential work: `tasks.where((t) => t.status == 'ACTIVE' && t.isEssential && !t.isExpectation && isTaskNotCosted(t))`.
- Process · medium · kpiLibrary — KPIs measuring nobody: active kpis where `!kpiIsAssigned(k, kpiAssignedByKpi)`.
- Process · medium · kpiLibrary — KPIs with no measurement defined: active kpis where `(k.measurementUnit ?? '').trim().isEmpty`.
- Structure · medium · roles — unstaffed role cards carrying CRITICAL work: active cards with no active holder that have ≥1 ACTIVE CRITICAL task on them.
- Structure · medium · roles — role cards with no department: active cards where `departmentId == null`.
- Structure · medium · kpiLibrary — KPIs with no department: active kpis where `departmentId == null`.

Ranking: `severity` high before medium; within a severity, descending `count`. Grouping is by `category` in the UI (Task 2), so the returned list stays a single ranked list. "active kpi" = `k.isActive`; "active card" = `c.isActive`. "active holder" of a card = an employee with `employmentStatus == 'ACTIVE' && deletedAt == null && roleScorecardId == card.id` (same predicate as `orphanTasks`).

- [ ] **Step 1: Extract `orphanTasks` (refactor, keep 3a green)**

In `lib/features/workforce_planning/unassigned_workspace.dart`, pull the orphan loop out of `buildUnassignedWorkspace` into a reusable function and call it. Add:

```dart
/// The ACTIVE accountabilities reaching nobody — the shared orphan predicate
/// (mirrors rebalance.dart's `unassignedTasks`): ACTIVE, no owner, and either
/// (no card AND no externalRef) or (a card with no ACTIVE non-deleted holder).
/// Legacy capacity-model rows (no card + externalRef) are excluded.
List<WpTask> orphanTasks({
  required List<WpTask> tasks,
  required List<Employee> employees,
}) {
  final out = <WpTask>[];
  for (final t in tasks) {
    if (t.status != 'ACTIVE') continue;
    if (t.ownerEmployeeId != null) continue;
    final cardId = t.roleScorecardId;
    if (cardId == null && t.externalRef != null) continue;
    final orphaned = cardId == null || !_cardStaffed(employees, cardId);
    if (!orphaned) continue;
    out.add(t);
  }
  return out;
}
```

Then change `buildUnassignedWorkspace`'s orphan-collection loop to `final orphans = orphanTasks(tasks: tasks, employees: employees);` (delete the now-duplicated inline loop). `_cardStaffed` already exists in this file — reuse it.

- [ ] **Step 2: Verify the 3a tests still pass (refactor is behavior-preserving)**

Run: `flutter test test/features/workforce_planning/unassigned_workspace_test.dart`
Expected: PASS (unchanged — 4 tests). If any fail, the extraction changed behavior; fix it before continuing.

- [ ] **Step 3: Write the failing needs-attention tests**

```dart
// test/features/workforce_planning/needs_attention_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart' show KpiAssignee;
import 'package:payroll_flutter/features/workforce_planning/needs_attention.dart';

WpPersonLoad _load(String id, {required double fixed, double cap = 160}) =>
    WpPersonLoad(employeeId: id, companyId: 'c', hoursFixed: fixed, capacityHours: cap);

Employee _e(String id, {String? card}) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: id, lastName: 'x',
      employmentType: 'REGULAR', employmentStatus: 'ACTIVE', hireDate: DateTime(2026),
      isRankAndFile: true, isOtEligible: false, isNdEligible: false,
      isHolidayPayEligible: false, taxOnFullEarnings: false, roleScorecardId: card);

WpTask _t(String id, {String? card, String? owner, String? crit,
        bool essential = true, bool expectation = false}) =>
    WpTask(id: id, companyId: 'c', name: id, roleScorecardId: card,
        ownerEmployeeId: owner, criticality: crit, isEssential: essential,
        isExpectation: expectation);

RoleScorecard _card(String id, {bool active = true, String? dept}) => RoleScorecard(
      id: id, companyId: 'c', jobTitle: id, missionStatement: '', departmentId: dept,
      responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
      workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: active,
      effectiveDate: DateTime(2026));

Kpi _kpi(String id, {bool active = true, String? unit, String? dept}) => Kpi(
      id: id, companyId: 'c', name: id, isActive: active,
      measurementUnit: unit, departmentId: dept);

List<AttentionItem> _run({
  List<WpPersonLoad> loads = const [], List<WpTask> tasks = const [],
  List<Employee> employees = const [], List<RoleScorecard> cards = const [],
  List<Kpi> kpis = const [], Map<String, List<KpiAssignee>> assigned = const {},
}) =>
    buildNeedsAttention(loads: loads, tasks: tasks, employees: employees,
        cards: cards, kpis: kpis, kpiAssignedByKpi: assigned);

AttentionItem? _find(List<AttentionItem> items, AttentionTarget target, AttentionSeverity sev) {
  final hits = items.where((i) => i.target == target && i.severity == sev);
  return hits.isEmpty ? null : hits.first;
}

void main() {
  test('no signals -> empty', () {
    expect(_run(), isEmpty);
  });

  test('over-capacity person is a high People/balance item', () {
    final items = _run(loads: [_load('a', fixed: 200), _load('b', fixed: 80)]);
    final over = _find(items, AttentionTarget.balance, AttentionSeverity.high)!;
    expect(over.category, AttentionCategory.people);
    expect(over.count, 1);
  });

  test('a CRITICAL orphan is high; all orphans are a medium item', () {
    final items = _run(
      tasks: [_t('o1', crit: 'CRITICAL'), _t('o2')], // both unowned, no card -> orphans
    );
    final crit = _find(items, AttentionTarget.unassigned, AttentionSeverity.high)!;
    expect(crit.count, 1);
    final all = _find(items, AttentionTarget.unassigned, AttentionSeverity.medium)!;
    expect(all.count, 2);
  });

  test('uncosted essential (not expectation) is a Process/tasks item', () {
    final items = _run(tasks: [
      _t('u1', owner: 'x'), // essential, no hours, owned so NOT an orphan
      _t('u2', owner: 'x', expectation: true, essential: false), // expectation, excluded
    ]);
    final proc = _find(items, AttentionTarget.tasks, AttentionSeverity.medium)!;
    expect(proc.count, 1); // only u1
  });

  test('KPI signals: measuring nobody, no measurement, no department', () {
    final items = _run(
      kpis: [_kpi('k1', unit: 'orders', dept: 'd1')], // assigned below -> only... see asserts
      assigned: {'k1': [const KpiAssignee(employeeId: 'e', name: 'E')]},
    );
    // k1 is assigned, has a unit and a dept -> no KPI signals at all
    expect(items.where((i) => i.target == AttentionTarget.kpiLibrary), isEmpty);

    final bad = _run(kpis: [_kpi('k2')]); // unassigned, no unit, no dept
    final lib = bad.where((i) => i.target == AttentionTarget.kpiLibrary).toList();
    expect(lib.length, 3); // measuring-nobody + no-measurement + no-department
  });

  test('unstaffed card with CRITICAL work, and card with no department', () {
    final items = _run(
      cards: [_card('rs1'), _card('rs2', dept: 'd1')],
      tasks: [_t('t1', card: 'rs1', crit: 'CRITICAL')], // rs1 has no holders
      employees: const [], // nobody staffs rs1
    );
    final struct = items.where((i) =>
        i.category == AttentionCategory.structure && i.target == AttentionTarget.roles);
    // unstaffed-critical (rs1) + no-department (rs1 only; rs2 has a dept)
    expect(struct.any((i) => i.count == 1), isTrue);
    expect(struct.length, 2);
  });

  test('high-severity items rank before medium', () {
    final items = _run(
      loads: [_load('a', fixed: 200)],          // high
      tasks: [_t('u1', owner: 'x')],            // medium (uncosted essential)
    );
    expect(items.first.severity, AttentionSeverity.high);
  });
}
```

(Confirm the exact `Kpi` and `KpiAssignee` constructors by reading `lib/data/models/kpi.dart` and where `KpiAssignee` is declared — adjust the helper field names to the real ones, keep the assertions.)

- [ ] **Step 4: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/needs_attention_test.dart`
Expected: FAIL — `needs_attention.dart` / its symbols do not exist.

- [ ] **Step 5: Implement `needs_attention.dart`**

```dart
import '../../data/models/employee.dart';
import '../../data/models/kpi.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import '../../data/repositories/role_scorecard_repository.dart' show KpiAssignee;
import '../kpi_library/kpi_rows.dart' show kpiIsAssigned;
import 'capacity_math.dart';
import 'tasks_rows.dart' show isTaskNotCosted;
import 'unassigned_workspace.dart' show orphanTasks;

enum AttentionCategory { people, process, structure, tools }

enum AttentionSeverity { high, medium }

/// Where the fix lives — the strip maps this to a hub-tab switch or a route.
enum AttentionTarget { balance, roles, tasks, unassigned, kpiLibrary }

/// One derived "needs attention" row: a gap the manager should close.
class AttentionItem {
  final AttentionCategory category;
  final AttentionSeverity severity;
  final String label;
  final int count;
  final AttentionTarget target;
  const AttentionItem({
    required this.category,
    required this.severity,
    required this.label,
    required this.count,
    required this.target,
  });
}

bool _cardHasActiveHolder(List<Employee> employees, String cardId) => employees.any(
    (e) => e.employmentStatus == 'ACTIVE' &&
        e.deletedAt == null &&
        e.roleScorecardId == cardId);

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// The ranked list of gaps computable on CURRENT data (pre-assignments).
/// Grouped by category in the UI; ordered here high-severity first, then by
/// descending count. Each signal appears only when its count > 0.
List<AttentionItem> buildNeedsAttention({
  required List<WpPersonLoad> loads,
  required List<WpTask> tasks,
  required List<Employee> employees,
  required List<RoleScorecard> cards,
  required List<Kpi> kpis,
  required Map<String, List<KpiAssignee>> kpiAssignedByKpi,
}) {
  final items = <AttentionItem>[];
  void add(AttentionCategory c, AttentionSeverity s, int n, String label, AttentionTarget t) {
    if (n > 0) items.add(AttentionItem(category: c, severity: s, count: n, label: label, target: t));
  }

  // People
  final over = loads
      .where((p) => loadStatus(personLoad(p)) == LoadStatus.over)
      .length;
  add(AttentionCategory.people, AttentionSeverity.high, over,
      '${_plural(over, 'person', 'people')} over capacity', AttentionTarget.balance);

  final orphans = orphanTasks(tasks: tasks, employees: employees);
  final criticalOrphans = orphans.where((t) => t.criticality == 'CRITICAL').length;
  add(AttentionCategory.people, AttentionSeverity.high, criticalOrphans,
      '${_plural(criticalOrphans, 'critical responsibility', 'critical responsibilities')} nobody owns',
      AttentionTarget.unassigned);
  add(AttentionCategory.people, AttentionSeverity.medium, orphans.length,
      '${_plural(orphans.length, 'responsibility', 'responsibilities')} unassigned',
      AttentionTarget.unassigned);

  // Process
  final uncostedEssential = tasks
      .where((t) => t.status == 'ACTIVE' && t.isEssential && !t.isExpectation && isTaskNotCosted(t))
      .length;
  add(AttentionCategory.process, AttentionSeverity.medium, uncostedEssential,
      '${_plural(uncostedEssential, 'essential responsibility', 'essential responsibilities')} uncosted',
      AttentionTarget.tasks);

  final activeKpis = kpis.where((k) => k.isActive).toList();
  final measuringNobody = activeKpis.where((k) => !kpiIsAssigned(k, kpiAssignedByKpi)).length;
  add(AttentionCategory.process, AttentionSeverity.medium, measuringNobody,
      '${_plural(measuringNobody, 'KPI', 'KPIs')} measuring nobody', AttentionTarget.kpiLibrary);

  final noMeasurement = activeKpis.where((k) => (k.measurementUnit ?? '').trim().isEmpty).length;
  add(AttentionCategory.process, AttentionSeverity.medium, noMeasurement,
      '${_plural(noMeasurement, 'KPI', 'KPIs')} with no measurement', AttentionTarget.kpiLibrary);

  // Structure
  final activeCards = cards.where((c) => c.isActive).toList();
  final tasksByCard = <String, List<WpTask>>{};
  for (final t in tasks) {
    final id = t.roleScorecardId;
    if (id != null && t.status == 'ACTIVE') (tasksByCard[id] ??= []).add(t);
  }
  final unstaffedCritical = activeCards.where((c) =>
      !_cardHasActiveHolder(employees, c.id) &&
      (tasksByCard[c.id] ?? const []).any((t) => t.criticality == 'CRITICAL')).length;
  add(AttentionCategory.structure, AttentionSeverity.medium, unstaffedCritical,
      '${_plural(unstaffedCritical, 'unstaffed role carries', 'unstaffed roles carry')} critical work',
      AttentionTarget.roles);

  final roleNoDept = activeCards.where((c) => c.departmentId == null).length;
  add(AttentionCategory.structure, AttentionSeverity.medium, roleNoDept,
      '${_plural(roleNoDept, 'role', 'roles')} with no department', AttentionTarget.roles);

  final kpiNoDept = activeKpis.where((k) => k.departmentId == null).length;
  add(AttentionCategory.structure, AttentionSeverity.medium, kpiNoDept,
      '${_plural(kpiNoDept, 'KPI', 'KPIs')} with no department', AttentionTarget.kpiLibrary);

  // Tools — reserved, no signals today.

  items.sort((a, b) {
    if (a.severity != b.severity) {
      return a.severity == AttentionSeverity.high ? -1 : 1;
    }
    return b.count.compareTo(a.count);
  });
  return items;
}
```

(`personLoad(WpPersonLoad p)` (capacity_math.dart:16) returns the load FRACTION directly — `loadFraction(projectedHours(...), p.capacityHours)` using the row's own `growthMultiplier` — so compare `loadStatus(personLoad(p)) == LoadStatus.over`; do NOT wrap it in `loadFraction` again.)

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/needs_attention_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/features/workforce_planning/unassigned_workspace.dart \
        lib/features/workforce_planning/needs_attention.dart \
        test/features/workforce_planning/needs_attention_test.dart
git commit -m "feat(workforce): needs-attention derivation (People/Process/Structure/Tools)"
```

---

### Task 2: The strip widget + Balance integration

**Files:**
- Create: `lib/features/workforce_planning/tabs/needs_attention_strip.dart`
- Modify: `lib/features/workforce_planning/tabs/balance_tab.dart` (embed the strip at the top of the tab body)
- Modify: `lib/features/workforce_planning/tabs/tab_intro.dart` (add `WpGlossary.needsAttention`)
- Test: `test/features/workforce_planning/needs_attention_strip_test.dart`

**Interfaces:**
- Consumes: `buildNeedsAttention`, `buildUnassignedWorkspace` (not needed — the strip passes raw tasks/employees to `buildNeedsAttention`, which calls `orphanTasks` itself), and providers `wpTasksProvider`, `wpActiveEmployeesProvider`, `wpPersonLoadsProvider`, `roleScorecardListProvider`, `kpiLibraryProvider`, `kpiAssignedEmployeesProvider`.
- Produces: `class NeedsAttentionStrip extends ConsumerWidget` (const ctor).

**Widget shape:** self-contained. Watch the six providers above. While any is loading OR the derived list is empty, render `const SizedBox.shrink()` (the strip simply doesn't appear when there's nothing to flag or data isn't ready — no spinner, no layout jump). Otherwise render a titled container: a small header "Needs attention" (with a `WpGlossary.needsAttention` info affordance via a tiny `TabIntro`-style tooltip or plain text) then the items grouped under their category label (People / Process / Structure / Tools — only categories with items), each item a tappable chip/row: a `StatusChip` toned by severity (`AttentionSeverity.high → StatusTone.danger`, `medium → StatusTone.warning`) showing `item.label`. Tapping routes via `_go(context, item.target)`:

```dart
void _go(BuildContext context, AttentionTarget target) {
  // Hub tabs live in the same DefaultTabController (Balance 0, Roles 1,
  // Structure 2, Tasks 3, Unassigned 4). KPI library is a separate route.
  const tabIndex = {
    AttentionTarget.balance: 0,
    AttentionTarget.roles: 1,
    AttentionTarget.tasks: 3,
    AttentionTarget.unassigned: 4,
  };
  final idx = tabIndex[target];
  if (idx != null) {
    DefaultTabController.of(context).animateTo(idx);
  } else if (target == AttentionTarget.kpiLibrary) {
    context.push('/kpi-library');
  }
}
```

**Provider inputs to `buildNeedsAttention`:** `loads` from `wpPersonLoadsProvider`; `tasks` from `wpTasksProvider`; `employees` from `wpActiveEmployeesProvider`; `cards` from `roleScorecardListProvider`; `kpis` from `kpiLibraryProvider`; `kpiAssignedByKpi` from `kpiAssignedEmployeesProvider`. Read each with `.asData?.value`; if any is null (still loading), render `SizedBox.shrink()`.

- [ ] **Step 1: Add the glossary entry**

In `lib/features/workforce_planning/tabs/tab_intro.dart`, in `class WpGlossary`, add:

```dart
  static const needsAttention = (
    term: 'Needs attention',
    meaning: 'Gaps derived from the current plan, grouped People / Process / '
        'Structure / Tools — over-capacity people, unowned or uncosted work, '
        'unstaffed critical roles, KPIs measuring nobody. Each links to its fix.',
  );
```

- [ ] **Step 2: Write the failing widget test**

```dart
// test/features/workforce_planning/needs_attention_strip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/needs_attention_strip.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/department_repository.dart';

const _over = WpPersonLoad(employeeId: 'a', companyId: 'c', hoursFixed: 200, capacityHours: 160);

Widget _host({required bool withSignal}) => ProviderScope(
      overrides: [
        wpPersonLoadsProvider.overrideWith((ref) async => withSignal ? const [_over] : const []),
        wpTasksProvider.overrideWith((ref) async => const []),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        roleScorecardListProvider.overrideWith((ref) async => const []),
        kpiLibraryProvider.overrideWith((ref) async => const []),
        kpiAssignedEmployeesProvider.overrideWith((ref) async => const {}),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: DefaultTabController(length: 5, child: NeedsAttentionStrip()),
        ),
      ),
    );

void main() {
  testWidgets('renders nothing when there are no gaps', (tester) async {
    await tester.pumpWidget(_host(withSignal: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('over capacity'), findsNothing);
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('surfaces an over-capacity gap under People', (tester) async {
    await tester.pumpWidget(_host(withSignal: true));
    await tester.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.textContaining('over capacity'), findsOneWidget);
  });
}
```

(Confirm the KPI/department provider names/imports resolve; `kpiAssignedEmployeesProvider` returns `Map<String, List<KpiAssignee>>` — override with `const {}`. Adjust imports to wherever those providers are declared.)

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/needs_attention_strip_test.dart`
Expected: FAIL — `needs_attention_strip.dart` does not exist.

- [ ] **Step 4: Implement `needs_attention_strip.dart`**

Build the `ConsumerWidget` per "Widget shape" above. Import `package:go_router/go_router.dart` for the route push, `../needs_attention.dart`, `../wp_providers.dart`, the KPI/department repository providers, `../../../app/status_colors.dart`, `../../../app/theme.dart`, and `tab_intro.dart`. Read `.asData?.value` for each provider; return `SizedBox.shrink()` if any is null. Call `buildNeedsAttention(...)`; if the result is empty, return `SizedBox.shrink()`. Otherwise render a `Container`/`Card` with a "Needs attention" header and the items grouped by `AttentionCategory` (iterate `AttentionCategory.values`, filter items in that category, render a small category label + a `Wrap` of tappable `StatusChip`s). Each chip: `InkWell(onTap: () => _go(context, item.target), child: StatusChip(label: item.label, tone: item.severity == AttentionSeverity.high ? StatusTone.danger : StatusTone.warning))`. Include the `_go` helper from the interface block.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/needs_attention_strip_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Embed in the Balance tab**

In `lib/features/workforce_planning/tabs/balance_tab.dart`, add `const NeedsAttentionStrip()` at the very top of the tab's scrolling body — immediately above the existing `_planBar(...)` call (around line 105, inside the `Column`/list of children the tab returns). Add the import. The strip renders `SizedBox.shrink()` when empty, so it costs nothing visually when there are no gaps.

Run: `flutter analyze lib/features/workforce_planning/`
Expected: 0 errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/workforce_planning/tabs/needs_attention_strip.dart \
        lib/features/workforce_planning/tabs/balance_tab.dart \
        lib/features/workforce_planning/tabs/tab_intro.dart \
        test/features/workforce_planning/needs_attention_strip_test.dart
git commit -m "feat(workforce): needs-attention strip on the Balance tab"
```

---

### Task 3: Full-suite + analyze gate

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: all pass (prior 1019 + the new tests; 1 pre-existing skip). If a PRE-EXISTING test fails unexpectedly, STOP and report — do not rewrite its assertions. In particular confirm `unassigned_workspace_test.dart` and `balance_tab_test.dart` are still green (the refactor + the Balance embed touched their surfaces).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: 0 errors.

---

## Self-Review

**Spec coverage** (spec §"'Needs attention' — changes surface themselves", §"KPI library alignment", Sequencing item 3):
- People: over-capacity ✓; CRITICAL with no owner ✓ (pre-step-4 "no owner" = orphan); unassigned with actions → the item deep-links to the Unassigned tab (which carries Assign/Archive/Propose from 3a) ✓. Key-person risk correctly DEFERRED (needs CONTRIBUTOR/assignments) — noted.
- Process: uncosted essential ✓; KPI measuring nobody ✓; KPI no measurement ✓. shares≠100% correctly DEFERRED (needs allocation_pct) — noted.
- Structure: unstaffed role with CRITICAL work ✓; role no department ✓; KPI no department ✓.
- Tools: reserved, category kept, no signals ✓.
- Grouped People/Process/Structure/Tools, ranked by severity, each deep-linking ✓ (Task 2).
- KPI library alignment (measuring-nobody / no-measurement / no-department fed into the shared strip) ✓.
- Rendered at top of Balance; "small dashboard" — no dashboard exists, so Balance-only (matches the recon; a separate dashboard is out of scope) — noted deferral.
- Deferred to step 4 (correctly NOT here): key-person risk, shares≠100%, literal no-PRIMARY, and the inline Assign/Archive/Propose actions *embedded in the strip row* (v1 deep-links to the Unassigned tab instead).

**Placeholder scan:** Task 2's widget step gives the exact `_go` navigation map, the provider list, the empty→`SizedBox.shrink()` rule, and the chip/tone mapping; it directs mirroring `TabIntro`/`StatusChip` for layout. No "TBD"/"handle edge cases".

**Type consistency:** `AttentionItem`/`AttentionCategory`/`AttentionSeverity`/`AttentionTarget` and `buildNeedsAttention(...)`'s signature are identical between Task 1's definition and Task 2's use. `orphanTasks({tasks, employees})` matches between the Task 1 extraction and its use inside `buildNeedsAttention`. The deep-link tab indices (Balance 0, Roles 1, Structure 2, Tasks 3, Unassigned 4) match the hub order set in step 3a.

**Open deferrals surfaced for the handoff:** (1) strip lives only on Balance (no separate dashboard surface exists); (2) the unassigned row deep-links to the Unassigned tab rather than embedding its actions inline — a v1 simplification; (3) assignment-dependent signals wait for step 4.
