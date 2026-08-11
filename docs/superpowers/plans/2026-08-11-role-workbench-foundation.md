# Role Workbench — Plan 1: Measurable Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give KPIs an EOS-style definition (formula, named source, cadence) and a structured goal, with all the pure logic and persistence the role workbench will sit on top of — no UI change.

**Architecture:** One migration adds columns to `kpis` and `role_scorecard_kpis` and prunes the legacy orphans. Five small pure-Dart modules hold every rule (goal formatting, definition completeness, reading evaluation, KPI-set validation, removal lifecycle) so the UI in Plan 2 contains no logic worth testing. The repository is widened to carry the new fields and to write the legacy free-text `target` **from** the structured goal, keeping the card PDF and contract templates working untouched.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase Postgres, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-11-role-workbench-design.md`. Read it before starting.
- This plan ships **no UI change**. Plan 2 builds the workbench; Plan 3 retires the card editor; Plan 4 wires Needs attention.
- The repo gates on `flutter analyze` only (0 errors, 0 warnings). **Do not run `dart format`** — the codebase is a mix of old and new formatter styles; match the surrounding style of the file you edit.
- Verification claims require pasted command output. Never write "tests pass" without it.
- The legacy `role_scorecard_kpis.target` and `.frequency` text columns stay. They are written from the structured goal and the KPI cadence. Nothing may stop populating them — the card PDF, employment-contract templates and `review_kpi_results` snapshots read them.
- Do not add a stored `is_measurable` flag. Completeness is computed in Dart.
- Migrations are applied by the user with `supabase db push`, never by an implementer.
- Cadence vocabulary: `WEEKLY` · `MONTHLY` · `QUARTERLY`. Value types: `COUNT` · `RATIO` · `CURRENCY` · `PERCENT` · `DURATION`. Goal directions: `GTE` · `LTE` · `EQ` · `BETWEEN`. Proof types: `REPORT_EXPORT` · `SCREENSHOT` · `SYSTEM_LINK`.

## File Structure

| File | Responsibility |
|---|---|
| `lib/data/models/kpi_goal.dart` (new) | `KpiGoal` value object, `formatGoal`, `parseLegacyTarget`, `goalColumns`, `frequencyLabelFromCadence`. Lives under `models/`, not `features/`, because `kpi.dart` and `role_kpi.dart` consume it and no model in this repo imports a feature. |
| `lib/features/kpi_library/kpi_measurable.dart` (new) | vocabulary constants, `kpiDefinitionGaps`, `isKpiDefined`, `isMeasurableForRole` |
| `lib/features/kpi_library/kpi_reading.dart` (new) | `computeReadingValue`, `isOnTrack` |
| `lib/features/kpi_library/kpi_set_rules.dart` (new) | `validateKpiSet` — the 3-5 explicit-set rules |
| `lib/features/workforce_planning/removal_lifecycle.dart` (new) | `removalActionForTask`, `removalActionForKpiLink`, `removalActionForLibraryKpi` |
| `supabase/migrations/20260811000001_kpi_measurables.sql` (new) | columns + goal constraint + legacy orphan cleanup |
| `lib/data/models/kpi.dart` (modify) | new `Kpi` fields; `KpiLinkInput` carries a `KpiGoal` |
| `lib/data/models/role_kpi.dart` (modify) | `RoleKpi` carries its goal |
| `lib/data/repositories/role_scorecard_repository.dart` (modify) | persist the new fields; derive `target`/`frequency` |
| `test/support/supabase_stub.dart` (new) | reusable widget-test harness for Supabase-dependent screens |

---

### Task 1: KPI goal value object, formatting and legacy parsing

**Files:**
- Create: `lib/data/models/kpi_goal.dart`
- Test: `test/data/models/kpi_goal_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum GoalDirection { gte, lte, eq, between }`; `class KpiGoal` with `direction`, `value` (double), `valueMax` (double?), `KpiGoal.fromRow(Map<String, dynamic>)` returning `KpiGoal?`; `String formatGoal(KpiGoal goal, String? unit)`; `KpiGoal? parseLegacyTarget(String? text)`; `Map<String, dynamic> goalColumns(KpiGoal? goal, String? unit)`; `String? frequencyLabelFromCadence(String? cadence)`.

- [ ] **Step 1: Write the failing test**

Create `test/data/models/kpi_goal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';

void main() {
  group('formatGoal', () {
    test('renders each direction with its unit', () {
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.gte, value: 98), '%'),
        '≥ 98%',
      );
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.lte, value: 3), '%'),
        '≤ 3%',
      );
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.eq, value: 0), null),
        '= 0',
      );
      expect(
        formatGoal(
          const KpiGoal(
            direction: GoalDirection.between,
            value: 5,
            valueMax: 10,
          ),
          'days',
        ),
        '5 to 10 days',
      );
    });

    test('drops a trailing .0 so goals read like people write them', () {
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.lte, value: 3.0), '%'),
        '≤ 3%',
      );
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.lte, value: 3.5), '%'),
        '≤ 3.5%',
      );
    });

    test('separates a word unit from the number, but not a symbol', () {
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.lte, value: 14), 'days'),
        '≤ 14 days',
      );
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.gte, value: 20), '₱'),
        '≥ ₱20',
      );
    });
  });

  group('parseLegacyTarget', () {
    test('reads the at-least family as GTE', () {
      for (final s in ['At least 98%', '≥ 98%', '>= 98', 'minimum 98', 'Min 98%']) {
        final g = parseLegacyTarget(s);
        expect(g?.direction, GoalDirection.gte, reason: s);
        expect(g?.value, 98, reason: s);
      }
    });

    test('reads the at-most family as LTE', () {
      for (final s in [
        'At most 3%',
        '≤ 3%',
        '<= 3',
        'maximum 3',
        'No more than 3%',
        'Under 3',
        'Within 3 days',
      ]) {
        final g = parseLegacyTarget(s);
        expect(g?.direction, GoalDirection.lte, reason: s);
        expect(g?.value, 3, reason: s);
      }
    });

    test('reads zero-defect wording as LTE 0', () {
      expect(parseLegacyTarget('Zero')?.direction, GoalDirection.lte);
      expect(parseLegacyTarget('Zero')?.value, 0);
      expect(parseLegacyTarget('No preventable errors')?.value, 0);
    });

    test('refuses a bare number — direction is not knowable', () {
      // "98%" could be a floor or a ceiling. Guessing would silently invert a
      // goal, so the upgrade UI asks instead of assuming.
      expect(parseLegacyTarget('98%'), isNull);
      expect(parseLegacyTarget('100'), isNull);
    });

    test('returns null for prose with no number', () {
      expect(parseLegacyTarget('Consistently high quality'), isNull);
      expect(parseLegacyTarget(''), isNull);
      expect(parseLegacyTarget(null), isNull);
    });
  });

  group('goalColumns', () {
    test('writes the legacy target text from the structured goal', () {
      final cols = goalColumns(
        const KpiGoal(direction: GoalDirection.lte, value: 3),
        '%',
      );
      expect(cols['goal_direction'], 'LTE');
      expect(cols['goal_value'], 3);
      expect(cols['goal_value_max'], isNull);
      expect(cols['target'], '≤ 3%');
    });

    test('nulls every goal column when there is no goal', () {
      final cols = goalColumns(null, '%');
      expect(cols['goal_direction'], isNull);
      expect(cols['goal_value'], isNull);
      expect(cols['goal_value_max'], isNull);
      expect(cols['target'], isNull);
    });
  });

  group('KpiGoal.fromRow', () {
    test('returns null when the row carries no direction', () {
      expect(KpiGoal.fromRow({'goal_direction': null, 'goal_value': 3}), isNull);
    });

    test('reads numerics that Postgres returned as int or String', () {
      final a = KpiGoal.fromRow({'goal_direction': 'GTE', 'goal_value': 98});
      expect(a?.value, 98);
      final b = KpiGoal.fromRow({'goal_direction': 'LTE', 'goal_value': '3.5'});
      expect(b?.value, 3.5);
    });
  });

  group('frequencyLabelFromCadence', () {
    test('maps the cadence vocabulary to the legacy display text', () {
      expect(frequencyLabelFromCadence('WEEKLY'), 'Weekly');
      expect(frequencyLabelFromCadence('MONTHLY'), 'Monthly');
      expect(frequencyLabelFromCadence('QUARTERLY'), 'Quarterly');
      expect(frequencyLabelFromCadence(null), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/data/models/kpi_goal_test.dart
```

Expected: compile failure — `Target of URI doesn't exist: 'package:payroll_flutter/data/models/kpi_goal.dart'`.

- [ ] **Step 3: Implement**

Create `lib/data/models/kpi_goal.dart`:

```dart
/// A KPI's goal: the comparison a period's reading is judged against.
///
/// Lives on `role_scorecard_kpis` (per role), not on the library KPI — the same
/// measurable can carry a different bar on a different role. The legacy
/// free-text `target` column is DERIVED from this on save (see [goalColumns]);
/// the card PDF, employment-contract templates and review snapshots all still
/// read that text, so it can never stop being written.
library;

enum GoalDirection { gte, lte, eq, between }

const _codes = {
  GoalDirection.gte: 'GTE',
  GoalDirection.lte: 'LTE',
  GoalDirection.eq: 'EQ',
  GoalDirection.between: 'BETWEEN',
};

String goalDirectionCode(GoalDirection d) => _codes[d]!;

GoalDirection? goalDirectionFromCode(String? code) {
  for (final e in _codes.entries) {
    if (e.value == code) return e.key;
  }
  return null;
}

class KpiGoal {
  final GoalDirection direction;
  final double value;

  /// Upper bound. Only meaningful for [GoalDirection.between].
  final double? valueMax;

  const KpiGoal({
    required this.direction,
    required this.value,
    this.valueMax,
  });

  /// Null when the row has no goal — that is a legitimate state (a KPI can be
  /// defined in the library before any role sets a bar for it).
  static KpiGoal? fromRow(Map<String, dynamic> r) {
    final dir = goalDirectionFromCode(r['goal_direction'] as String?);
    if (dir == null) return null;
    final v = _num(r['goal_value']);
    if (v == null) return null;
    return KpiGoal(direction: dir, value: v, valueMax: _num(r['goal_value_max']));
  }

  /// Postgres numerics arrive as int, double or String depending on the driver
  /// and the column's scale — normalise all three.
  static double? _num(Object? v) => switch (v) {
    null => null,
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };
}

/// `98.0` reads as a typo in a goal; `98` is what a person wrote.
String _trimNumber(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// A symbol unit hugs its number (`₱20`, `98%`); a word unit needs a space
/// (`14 days`).
bool _unitIsWord(String unit) => RegExp(r'^[A-Za-z]').hasMatch(unit);

String _withUnit(double v, String? unit) {
  final n = _trimNumber(v);
  if (unit == null || unit.trim().isEmpty) return n;
  final u = unit.trim();
  if (u == '₱' || u == r'$') return '$u$n';
  return _unitIsWord(u) ? '$n $u' : '$n$u';
}

/// The human rendering of a goal, and the value written to the legacy
/// `target` column.
String formatGoal(KpiGoal goal, String? unit) => switch (goal.direction) {
  GoalDirection.gte => '≥ ${_withUnit(goal.value, unit)}',
  GoalDirection.lte => '≤ ${_withUnit(goal.value, unit)}',
  GoalDirection.eq => '= ${_withUnit(goal.value, unit)}',
  GoalDirection.between =>
    '${_trimNumber(goal.value)} to ${_withUnit(goal.valueMax ?? goal.value, unit)}',
};

final _gte = RegExp(r'(at\s*least|minimum|min\.?|no\s*less\s*than|≥|>=)', caseSensitive: false);
final _lte = RegExp(
  r'(at\s*most|maximum|max\.?|no\s*more\s*than|less\s*than|under|below|within|≤|<=)',
  caseSensitive: false,
);
final _zero = RegExp(r'\b(zero|none|no)\b', caseSensitive: false);
final _number = RegExp(r'-?\d+(\.\d+)?');

/// Best-effort reading of a legacy free-text target, used ONLY to pre-fill the
/// goal fields when a manager upgrades an old KPI. Deliberately conservative:
/// a bare "98%" carries no direction, and guessing would silently invert the
/// goal, so it returns null and the UI asks.
KpiGoal? parseLegacyTarget(String? text) {
  final s = (text ?? '').trim();
  if (s.isEmpty) return null;
  final m = _number.firstMatch(s);
  final value = m == null ? null : double.tryParse(m.group(0)!);
  if (_lte.hasMatch(s) && value != null) {
    return KpiGoal(direction: GoalDirection.lte, value: value);
  }
  if (_gte.hasMatch(s) && value != null) {
    return KpiGoal(direction: GoalDirection.gte, value: value);
  }
  // "Zero defects", "No preventable errors" — a ceiling of nothing.
  if (value == null && _zero.hasMatch(s)) {
    return const KpiGoal(direction: GoalDirection.lte, value: 0);
  }
  return null;
}

/// The columns a role→KPI link writes for its goal, including the derived
/// legacy `target` text. One place, so `target` can never drift from the goal.
Map<String, dynamic> goalColumns(KpiGoal? goal, String? unit) => {
  'goal_direction': goal == null ? null : goalDirectionCode(goal.direction),
  'goal_value': goal?.value,
  'goal_value_max': goal?.valueMax,
  'target': goal == null ? null : formatGoal(goal, unit),
};

/// The legacy `frequency` text, derived from the KPI's cadence — an EOS
/// measurable has one rhythm, so the link no longer carries its own.
String? frequencyLabelFromCadence(String? cadence) => switch (cadence) {
  'WEEKLY' => 'Weekly',
  'MONTHLY' => 'Monthly',
  'QUARTERLY' => 'Quarterly',
  _ => null,
};
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/data/models/kpi_goal_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Analyze**

```
flutter analyze lib test
```

Expected: no new `error` or `warning` lines (the repo carries pre-existing `info` lints).

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/kpi_goal.dart test/data/models/kpi_goal_test.dart
git commit -m "feat(kpi): structured goal value object with legacy target derivation"
```

---

### Task 2: Measurable-definition completeness

**Files:**
- Create: `lib/features/kpi_library/kpi_measurable.dart`
- Test: `test/features/kpi_library/kpi_measurable_test.dart`

**Interfaces:**
- Consumes: `KpiGoal` from Task 1.
- Produces: `const kKpiValueTypes`, `kKpiCadences`, `kKpiProofTypes` (each `List<String>`); `List<String> kpiDefinitionGaps({required String? valueType, required String? unit, required String? numeratorLabel, required String? numeratorSource, required String? denominatorLabel, required String? denominatorSource})`; `bool isKpiDefined({...same named params...})`; `bool isMeasurableForRole({required bool defined, required KpiGoal? goal})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/kpi_library/kpi_measurable_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_measurable.dart';

void main() {
  List<String> gapsFor({
    String? valueType = 'RATIO',
    String? unit = '%',
    String? numeratorLabel = 'Returns received',
    String? numeratorSource = 'BigSeller',
    String? denominatorLabel = 'Orders shipped',
    String? denominatorSource = 'BigSeller',
  }) => kpiDefinitionGaps(
    valueType: valueType,
    unit: unit,
    numeratorLabel: numeratorLabel,
    numeratorSource: numeratorSource,
    denominatorLabel: denominatorLabel,
    denominatorSource: denominatorSource,
  );

  test('a fully specified ratio has no gaps', () {
    expect(gapsFor(), isEmpty);
    expect(
      isKpiDefined(
        valueType: 'RATIO',
        unit: '%',
        numeratorLabel: 'Returns received',
        numeratorSource: 'BigSeller',
        denominatorLabel: 'Orders shipped',
        denominatorSource: 'BigSeller',
      ),
      isTrue,
    );
  });

  test('names every missing piece, not just the first', () {
    final gaps = gapsFor(numeratorSource: null, denominatorLabel: '  ');
    expect(gaps, containsAll(['numerator source', 'denominator']));
    expect(gaps.length, 2);
  });

  test('a COUNT needs no denominator', () {
    expect(
      gapsFor(
        valueType: 'COUNT',
        unit: 'orders',
        denominatorLabel: null,
        denominatorSource: null,
      ),
      isEmpty,
    );
  });

  test('a RATIO without a denominator is not defined', () {
    final gaps = gapsFor(denominatorLabel: null, denominatorSource: null);
    expect(gaps, contains('denominator'));
    expect(gaps, contains('denominator source'));
  });

  test('the legacy library rows read as undefined', () {
    // "Documentation Accuracy" — a name and prose, nothing countable.
    final gaps = kpiDefinitionGaps(
      valueType: 'COUNT',
      unit: null,
      numeratorLabel: null,
      numeratorSource: null,
      denominatorLabel: null,
      denominatorSource: null,
    );
    expect(gaps, containsAll(['unit', 'what is counted', 'source']));
  });

  test('measurable for a role needs a defined KPI AND a goal', () {
    const goal = KpiGoal(direction: GoalDirection.lte, value: 3);
    expect(isMeasurableForRole(defined: true, goal: goal), isTrue);
    expect(isMeasurableForRole(defined: true, goal: null), isFalse);
    expect(isMeasurableForRole(defined: false, goal: goal), isFalse);
  });

  test('the vocabularies match the database check constraints', () {
    expect(kKpiValueTypes, [
      'COUNT',
      'RATIO',
      'CURRENCY',
      'PERCENT',
      'DURATION',
    ]);
    expect(kKpiCadences, ['WEEKLY', 'MONTHLY', 'QUARTERLY']);
    expect(kKpiProofTypes, ['REPORT_EXPORT', 'SCREENSHOT', 'SYSTEM_LINK']);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/kpi_library/kpi_measurable_test.dart
```

Expected: compile failure — `kpi_measurable.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/features/kpi_library/kpi_measurable.dart`:

```dart
import '../../data/models/kpi_goal.dart';

/// EOS vocabulary for a measurable. These lists MUST match the check
/// constraints in `20260811000001_kpi_measurables.sql` — a value here that the
/// database rejects surfaces as a save failure with a Postgres error string.
const kKpiValueTypes = ['COUNT', 'RATIO', 'CURRENCY', 'PERCENT', 'DURATION'];
const kKpiCadences = ['WEEKLY', 'MONTHLY', 'QUARTERLY'];
const kKpiProofTypes = ['REPORT_EXPORT', 'SCREENSHOT', 'SYSTEM_LINK'];

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// What this KPI still needs before a number can be produced for it, in the
/// order a person would fill them in. Empty means the definition is complete.
///
/// Returned as labels rather than codes because the only consumers are a
/// tooltip and a Needs-attention chip; nothing branches on the values.
List<String> kpiDefinitionGaps({
  required String? valueType,
  required String? unit,
  required String? numeratorLabel,
  required String? numeratorSource,
  required String? denominatorLabel,
  required String? denominatorSource,
}) {
  final gaps = <String>[];
  if (_blank(unit)) gaps.add('unit');
  if (_blank(numeratorLabel)) gaps.add('what is counted');
  if (_blank(numeratorSource)) gaps.add('source');
  if (valueType == 'RATIO') {
    if (_blank(denominatorLabel)) gaps.add('denominator');
    if (_blank(denominatorSource)) gaps.add('denominator source');
  }
  return gaps;
}

/// Library-level completeness: this KPI describes a number somebody could go
/// and count. Says nothing about whether a role has set a bar for it.
bool isKpiDefined({
  required String? valueType,
  required String? unit,
  required String? numeratorLabel,
  required String? numeratorSource,
  required String? denominatorLabel,
  required String? denominatorSource,
}) => kpiDefinitionGaps(
  valueType: valueType,
  unit: unit,
  numeratorLabel: numeratorLabel,
  numeratorSource: numeratorSource,
  denominatorLabel: denominatorLabel,
  denominatorSource: denominatorSource,
).isEmpty;

/// Link-level completeness: defined AND this role has set a goal. Only a
/// measurable KPI may join an employee's tracked set.
bool isMeasurableForRole({required bool defined, required KpiGoal? goal}) =>
    defined && goal != null;
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/kpi_library/kpi_measurable_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/kpi_library/kpi_measurable.dart test/features/kpi_library/kpi_measurable_test.dart
git commit -m "feat(kpi): definition completeness for EOS measurables"
```

---

### Task 3: Reading evaluation — raw counts to on-track

**Files:**
- Create: `lib/features/kpi_library/kpi_reading.dart`
- Test: `test/features/kpi_library/kpi_reading_test.dart`

**Interfaces:**
- Consumes: `KpiGoal`, `GoalDirection` from Task 1.
- Produces: `double? computeReadingValue({required String? valueType, required String? unit, required double? numerator, double? denominator})`; `bool? isOnTrack(double? value, KpiGoal? goal)`.

Note: only the binary on-track verdict is built here. EOS judges a measurable as hit or missed; any finer attainment curve belongs to Spec B's scoring, and is not built until B needs it.

- [ ] **Step 1: Write the failing test**

Create `test/features/kpi_library/kpi_reading_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_reading.dart';

void main() {
  group('computeReadingValue', () {
    test('a percent ratio scales to 100 — 3 of 100 orders is 3%', () {
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: '%',
          numerator: 3,
          denominator: 100,
        ),
        3.0,
      );
    });

    test('a non-percent ratio is the plain quotient', () {
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: 'orders/day',
          numerator: 90,
          denominator: 30,
        ),
        3.0,
      );
    });

    test('a count is the numerator, denominator ignored', () {
      expect(
        computeReadingValue(
          valueType: 'COUNT',
          unit: 'orders',
          numerator: 42,
          denominator: 7,
        ),
        42.0,
      );
    });

    test('a zero denominator yields no reading rather than infinity', () {
      // A week with no orders shipped cannot have a return RATE. Reporting 0%
      // would read as a perfect week.
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: '%',
          numerator: 0,
          denominator: 0,
        ),
        isNull,
      );
    });

    test('a missing numerator or denominator yields no reading', () {
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: '%',
          numerator: null,
          denominator: 100,
        ),
        isNull,
      );
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: '%',
          numerator: 3,
          denominator: null,
        ),
        isNull,
      );
    });
  });

  group('isOnTrack', () {
    test('GTE is met at or above the bar', () {
      const g = KpiGoal(direction: GoalDirection.gte, value: 98);
      expect(isOnTrack(98, g), isTrue);
      expect(isOnTrack(99.5, g), isTrue);
      expect(isOnTrack(97.9, g), isFalse);
    });

    test('LTE is met at or below the bar', () {
      const g = KpiGoal(direction: GoalDirection.lte, value: 3);
      expect(isOnTrack(3, g), isTrue);
      expect(isOnTrack(0, g), isTrue);
      expect(isOnTrack(7.8, g), isFalse);
    });

    test('EQ tolerates floating-point dust', () {
      const g = KpiGoal(direction: GoalDirection.eq, value: 0.3);
      expect(isOnTrack(0.1 + 0.2, g), isTrue);
      expect(isOnTrack(0.31, g), isFalse);
    });

    test('BETWEEN is inclusive of both bounds', () {
      const g = KpiGoal(
        direction: GoalDirection.between,
        value: 5,
        valueMax: 10,
      );
      expect(isOnTrack(5, g), isTrue);
      expect(isOnTrack(10, g), isTrue);
      expect(isOnTrack(4.9, g), isFalse);
      expect(isOnTrack(10.1, g), isFalse);
    });

    test('no reading or no goal is unknown, not off-track', () {
      // An un-submitted week must never read as a miss.
      expect(isOnTrack(null, const KpiGoal(direction: GoalDirection.gte, value: 1)), isNull);
      expect(isOnTrack(5, null), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/kpi_library/kpi_reading_test.dart
```

Expected: compile failure — `kpi_reading.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/features/kpi_library/kpi_reading.dart`:

```dart
import '../../data/models/kpi_goal.dart';

/// The value a period's raw counts produce, or null when it cannot be computed.
///
/// Null is a first-class answer: a week with nothing shipped has no return
/// RATE, and reporting 0% would read as a perfect week rather than as missing
/// data. Every caller must render null as "—", never as zero.
double? computeReadingValue({
  required String? valueType,
  required String? unit,
  required double? numerator,
  double? denominator,
}) {
  if (numerator == null) return null;
  if (valueType != 'RATIO') return numerator;
  if (denominator == null || denominator == 0) return null;
  final quotient = numerator / denominator;
  return (unit ?? '').trim() == '%' ? quotient * 100 : quotient;
}

/// Floating-point readings never land exactly on a goal; 1e-9 is far below any
/// unit this app measures in (whole orders, days, pesos, one-decimal percents).
const _epsilon = 1e-9;

/// EOS's binary verdict. Null means unknown — no reading yet, or no goal set —
/// and must never be collapsed into "off-track".
bool? isOnTrack(double? value, KpiGoal? goal) {
  if (value == null || goal == null) return null;
  return switch (goal.direction) {
    GoalDirection.gte => value >= goal.value - _epsilon,
    GoalDirection.lte => value <= goal.value + _epsilon,
    GoalDirection.eq => (value - goal.value).abs() <= _epsilon,
    GoalDirection.between =>
      value >= goal.value - _epsilon &&
          value <= (goal.valueMax ?? goal.value) + _epsilon,
  };
}
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/kpi_library/kpi_reading_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/kpi_library/kpi_reading.dart test/features/kpi_library/kpi_reading_test.dart
git commit -m "feat(kpi): compute a reading from raw counts and judge it on-track"
```

---

### Task 4: Per-employee KPI set rules

**Files:**
- Create: `lib/features/kpi_library/kpi_set_rules.dart`
- Test: `test/features/kpi_library/kpi_set_rules_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class KpiSetVerdict { final bool blocked; final List<String> problems; final List<String> warnings; }`; `KpiSetVerdict validateKpiSet({required Set<String> selectedKpiIds, required Set<String> roleKpiIds, required Set<String> measurableKpiIds})`; `bool employeeNeedsKpiSet(Set<String> selectedKpiIds)`.

Spec rules: an explicit set is required (empty no longer means "all"); 3-5 is advised, not enforced; only measurable KPIs may be selected; a selection must be on the employee's role.

- [ ] **Step 1: Write the failing test**

Create `test/features/kpi_library/kpi_set_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_set_rules.dart';

void main() {
  KpiSetVerdict verdict(
    Set<String> selected, {
    Set<String> role = const {'a', 'b', 'c', 'd', 'e', 'f'},
    Set<String> measurable = const {'a', 'b', 'c', 'd', 'e', 'f'},
  }) => validateKpiSet(
    selectedKpiIds: selected,
    roleKpiIds: role,
    measurableKpiIds: measurable,
  );

  test('a set of 3 to 5 measurable role KPIs is clean', () {
    for (final s in [
      {'a', 'b', 'c'},
      {'a', 'b', 'c', 'd'},
      {'a', 'b', 'c', 'd', 'e'},
    ]) {
      final v = verdict(s);
      expect(v.blocked, isFalse, reason: '$s');
      expect(v.problems, isEmpty, reason: '$s');
      expect(v.warnings, isEmpty, reason: '$s');
    }
  });

  test('fewer than 3 or more than 5 warns but saves', () {
    final few = verdict({'a', 'b'});
    expect(few.blocked, isFalse);
    expect(few.warnings.single, contains('3'));

    final many = verdict({'a', 'b', 'c', 'd', 'e', 'f'});
    expect(many.blocked, isFalse);
    expect(many.warnings.single, contains('5'));
  });

  test('an empty set is blocked — it no longer means "all of them"', () {
    final v = verdict(const {});
    expect(v.blocked, isTrue);
    expect(v.problems.single, contains('at least one'));
  });

  test('an unmeasurable KPI is blocked from the set', () {
    final v = verdict({'a', 'b', 'c'}, measurable: {'a', 'b'});
    expect(v.blocked, isTrue);
    expect(v.problems.single, contains('not measurable'));
  });

  test('a KPI that is not on the role is blocked', () {
    // Can happen after the employee is moved to a different role card.
    final v = verdict({'a', 'z'}, role: {'a', 'b'}, measurable: {'a', 'z'});
    expect(v.blocked, isTrue);
    expect(v.problems.single, contains('not on this role'));
  });

  test('reports every problem at once rather than one per save', () {
    final v = verdict({'z'}, role: {'a'}, measurable: const {});
    expect(v.problems.length, 2);
    expect(v.blocked, isTrue);
  });

  test('employeeNeedsKpiSet flags only an empty set', () {
    expect(employeeNeedsKpiSet(const {}), isTrue);
    expect(employeeNeedsKpiSet({'a'}), isFalse);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/kpi_library/kpi_set_rules_test.dart
```

Expected: compile failure — `kpi_set_rules.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/features/kpi_library/kpi_set_rules.dart`:

```dart
/// EOS keeps a person to a handful of numbers they own. The app advises 3-5 and
/// enforces only what would corrupt scoring: an empty set, an unmeasurable KPI,
/// or one that is not on the person's role.
class KpiSetVerdict {
  /// Save must be refused.
  final bool blocked;

  /// Why it is refused. Empty when [blocked] is false.
  final List<String> problems;

  /// Worth saying, but never a reason to refuse — a new hire mid-setup may
  /// legitimately have two.
  final List<String> warnings;

  const KpiSetVerdict({
    required this.blocked,
    required this.problems,
    required this.warnings,
  });
}

/// Advisory band, per the spec. Not a constraint.
const kKpiSetMin = 3;
const kKpiSetMax = 5;

KpiSetVerdict validateKpiSet({
  required Set<String> selectedKpiIds,
  required Set<String> roleKpiIds,
  required Set<String> measurableKpiIds,
}) {
  final problems = <String>[];
  final warnings = <String>[];

  if (selectedKpiIds.isEmpty) {
    // "No rows means the full role set" was the old rule. Under scoring it
    // would compare someone measured on 3 things against someone measured on
    // 10, so an empty set is now a gap to close, not a default.
    problems.add('Pick at least one KPI — an empty set is no longer tracked.');
  } else {
    final offRole = selectedKpiIds.difference(roleKpiIds);
    if (offRole.isNotEmpty) {
      problems.add(
        '${offRole.length} selected KPI(s) are not on this role — remove them '
        'or add them to the role first.',
      );
    }
    final unmeasurable = selectedKpiIds
        .intersection(roleKpiIds)
        .difference(measurableKpiIds);
    if (unmeasurable.isNotEmpty) {
      problems.add(
        '${unmeasurable.length} selected KPI(s) are not measurable yet — give '
        'them a formula, a source and a goal first.',
      );
    }
    if (selectedKpiIds.length < kKpiSetMin) {
      warnings.add('Fewer than $kKpiSetMin KPIs — most roles need $kKpiSetMin to $kKpiSetMax.');
    } else if (selectedKpiIds.length > kKpiSetMax) {
      warnings.add('More than $kKpiSetMax KPIs — consider trimming to the vital few.');
    }
  }

  return KpiSetVerdict(
    blocked: problems.isNotEmpty,
    problems: problems,
    warnings: warnings,
  );
}

/// Drives the "N people with no KPI set" Needs-attention chip.
bool employeeNeedsKpiSet(Set<String> selectedKpiIds) => selectedKpiIds.isEmpty;
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/kpi_library/kpi_set_rules_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/kpi_library/kpi_set_rules.dart test/features/kpi_library/kpi_set_rules_test.dart
git commit -m "feat(kpi): explicit 3-5 per-employee KPI set rules"
```

---

### Task 5: Removal lifecycle — archive versus delete

**Files:**
- Create: `lib/features/workforce_planning/removal_lifecycle.dart`
- Test: `test/features/workforce_planning/removal_lifecycle_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum RemovalAction { delete, archive, blocked }`; `RemovalAction removalActionForTask({required int assignmentCount})`; `RemovalAction removalActionForKpiLink({required bool hasLogs})`; `RemovalAction removalActionForLibraryKpi({required int roleLinkCount, required bool hasLogs})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/workforce_planning/removal_lifecycle_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/removal_lifecycle.dart';

void main() {
  group('task', () {
    test('an unassigned task can be deleted outright', () {
      expect(removalActionForTask(assignmentCount: 0), RemovalAction.delete);
    });

    test('an assigned task archives instead, keeping the row addressable', () {
      expect(removalActionForTask(assignmentCount: 1), RemovalAction.archive);
      expect(removalActionForTask(assignmentCount: 4), RemovalAction.archive);
    });
  });

  group('role to KPI link', () {
    test('deletes while no logs exist', () {
      // True throughout Spec A — kpi_logs arrives with Spec B.
      expect(removalActionForKpiLink(hasLogs: false), RemovalAction.delete);
    });

    test('archives once a period has been logged against it', () {
      expect(removalActionForKpiLink(hasLogs: true), RemovalAction.archive);
    });
  });

  group('library KPI', () {
    test('deletes only when it is on no role and has no logs', () {
      expect(
        removalActionForLibraryKpi(roleLinkCount: 0, hasLogs: false),
        RemovalAction.delete,
      );
    });

    test('deactivates when a role still links it', () {
      // Includes the vacant-role case: nobody tracks it, but a card shows it.
      expect(
        removalActionForLibraryKpi(roleLinkCount: 1, hasLogs: false),
        RemovalAction.archive,
      );
    });

    test('deactivates when logs exist, even with no role links left', () {
      expect(
        removalActionForLibraryKpi(roleLinkCount: 0, hasLogs: true),
        RemovalAction.archive,
      );
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/removal_lifecycle_test.dart
```

Expected: compile failure — `removal_lifecycle.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/features/workforce_planning/removal_lifecycle.dart`:

```dart
/// What "remove" means for a given row. Archive buys reversibility and an audit
/// trail; it does NOT protect an already-issued document, because saved
/// documents re-render live from these same rows (see the spec's known
/// limitation). Deleting a row that something else references is the case this
/// exists to prevent.
enum RemovalAction { delete, archive, blocked }

/// A `wp_tasks` row. Assignments (`wp_task_assignments`) are the history that
/// makes a task worth keeping — costing and load attribution both hang off
/// them.
RemovalAction removalActionForTask({required int assignmentCount}) =>
    assignmentCount > 0 ? RemovalAction.archive : RemovalAction.delete;

/// A `role_scorecard_kpis` row. [hasLogs] is always false until Spec B creates
/// `kpi_logs`; the rule is encoded now so B only has to supply the fact.
RemovalAction removalActionForKpiLink({required bool hasLogs}) =>
    hasLogs ? RemovalAction.archive : RemovalAction.delete;

/// A `kpis` row. Archive here means `is_active = false`.
RemovalAction removalActionForLibraryKpi({
  required int roleLinkCount,
  required bool hasLogs,
}) => (roleLinkCount > 0 || hasLogs)
    ? RemovalAction.archive
    : RemovalAction.delete;
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/workforce_planning/removal_lifecycle_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/removal_lifecycle.dart test/features/workforce_planning/removal_lifecycle_test.dart
git commit -m "feat(wp): archive-versus-delete decision for tasks and KPIs"
```

---

### Task 6: Migration — measurable columns, structured goal, legacy cleanup

**Files:**
- Create: `supabase/migrations/20260811000001_kpi_measurables.sql`

**Interfaces:**
- Consumes: the vocabularies fixed in Task 2 (`kKpiValueTypes`, `kKpiCadences`, `kKpiProofTypes`) and the direction codes from Task 1 (`GTE`/`LTE`/`EQ`/`BETWEEN`). The check constraints here and those Dart lists must agree exactly.
- Produces: columns `kpis.value_type`, `.numerator_label`, `.numerator_source`, `.denominator_label`, `.denominator_source`, `.unit`, `.cadence`, `.proof_type`; `role_scorecard_kpis.goal_direction`, `.goal_value`, `.goal_value_max`.

**Do not apply this migration.** The user runs `supabase db push`. An implementer's job ends at a reviewed file.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260811000001_kpi_measurables.sql`:

```sql
-- KPIs become EOS measurables: every number declares how it is counted, from
-- which source, at what rhythm, and against a structured goal.
-- Spec: docs/superpowers/specs/2026-08-11-role-workbench-design.md
--
-- The legacy free-text role_scorecard_kpis.target and .frequency columns are
-- DELIBERATELY kept. They are now derived (written from the goal and the
-- cadence by the Dart repository) and are still read by the role-card PDF, the
-- employment-contract templates and review_kpi_results snapshots.

-- 1. How the number is produced. Sources stay free text with autocomplete in
--    the UI: BigSeller and Lark today, Shopee or Shopify tomorrow, no
--    migration to add one.
alter table kpis
  add column if not exists value_type text not null default 'COUNT'
    check (value_type in ('COUNT','RATIO','CURRENCY','PERCENT','DURATION')),
  add column if not exists numerator_label text,
  add column if not exists numerator_source text,
  add column if not exists denominator_label text,
  add column if not exists denominator_source text,
  add column if not exists unit text,
  add column if not exists cadence text not null default 'WEEKLY'
    check (cadence in ('WEEKLY','MONTHLY','QUARTERLY')),
  add column if not exists proof_type text
    check (proof_type is null or proof_type in ('REPORT_EXPORT','SCREENSHOT','SYSTEM_LINK'));

comment on column kpis.value_type is
  'COUNT | RATIO | CURRENCY | PERCENT | DURATION. RATIO requires both denominator columns.';
comment on column kpis.numerator_source is
  'Free text naming the system the count is read from (BigSeller, Lark, ...). '
  'Autocompleted in the UI from values already in use; deliberately unconstrained '
  'so a new channel needs no migration.';
comment on column kpis.cadence is
  'The measurable rhythm. Lives here, not on role_scorecard_kpis: an EOS '
  'measurable has ONE cadence regardless of which role carries it.';

-- 2. The goal lives on the LINK — the same measurable can carry a different bar
--    on a different role.
alter table role_scorecard_kpis
  add column if not exists goal_direction text
    check (goal_direction is null or goal_direction in ('GTE','LTE','EQ','BETWEEN')),
  add column if not exists goal_value numeric,
  add column if not exists goal_value_max numeric;

-- add constraint has no IF NOT EXISTS; guard so a re-run is a no-op.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'role_scorecard_kpis_goal_complete'
  ) then
    alter table role_scorecard_kpis
      add constraint role_scorecard_kpis_goal_complete check (
        goal_direction is null
        or (goal_value is not null
            and (goal_direction <> 'BETWEEN' or goal_value_max is not null))
      );
  end if;
end $$;

comment on column role_scorecard_kpis.target is
  'DERIVED display text, written from the goal columns by the Dart repository '
  '(see lib/data/models/kpi_goal.dart, formatGoal). Kept because the card PDF, '
  'contract templates and review_kpi_results snapshots read it. Do not hand-edit.';

-- 3. Legacy cleanup. Existing targets are NOT parsed into goals: "98%" carries
--    no direction and guessing would silently invert a bar. Old KPIs simply
--    read as "not yet measurable" until a manager upgrades them.
--
--    Of the KPIs that measure nobody, only those on NO role card are deleted.
--    One on a card with no current holder also measures nobody, but deleting it
--    would silently strip a role that is merely unfilled — those deactivate.
--    "Reaches nobody" mirrors employeesByKpi in role_scorecard_repository.dart:
--    an employee reaches a KPI through their role card's links (deleted
--    employees excluded), or through a direct employee_kpis row.
do $$
declare
  r record;
  v_deleted int := 0;
  v_deactivated int := 0;
begin
  for r in
    select k.id,
           k.name,
           exists (
             select 1 from role_scorecard_kpis l where l.kpi_id = k.id
           ) as on_a_card
    from kpis k
    where k.is_active
      and not exists (
        select 1
        from role_scorecard_kpis l
        join employees e on e.role_scorecard_id = l.role_scorecard_id
        where l.kpi_id = k.id
          and e.deleted_at is null
      )
      and not exists (
        select 1 from employee_kpis ek where ek.kpi_id = k.id
      )
  loop
    if r.on_a_card then
      update kpis set is_active = false where id = r.id;
      raise notice 'DEACTIVATED (on a role card with no holder): %', r.name;
      v_deactivated := v_deactivated + 1;
    else
      -- No links exist (on_a_card is false), so the FK from
      -- role_scorecard_kpis (on delete restrict) cannot block this.
      delete from kpis where id = r.id;
      raise notice 'DELETED (on no role card at all): %', r.name;
      v_deleted := v_deleted + 1;
    end if;
  end loop;
  raise notice 'legacy KPI cleanup: % deleted, % deactivated', v_deleted, v_deactivated;
end $$;
```

- [ ] **Step 2: Check the SQL parses**

The repo has no local Supabase (ports 54321/54322 belong to another project). Confirm the file is at least syntactically well-formed and that the constraint vocabularies match the Dart constants:

```
grep -c "add column if not exists" supabase/migrations/20260811000001_kpi_measurables.sql
grep -o "'COUNT','RATIO','CURRENCY','PERCENT','DURATION'" supabase/migrations/20260811000001_kpi_measurables.sql
grep -o "'WEEKLY','MONTHLY','QUARTERLY'" supabase/migrations/20260811000001_kpi_measurables.sql
grep -o "'GTE','LTE','EQ','BETWEEN'" supabase/migrations/20260811000001_kpi_measurables.sql
```

Expected: `11`, then one match on each of the three vocabulary lines. If a vocabulary differs from `kKpiValueTypes` / `kKpiCadences` / `goalDirectionCode` in Dart, fix the mismatch now — it would only surface later as a Postgres error string in a save dialog.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260811000001_kpi_measurables.sql
git commit -m "feat(db): KPI measurable definition, structured goal, legacy orphan cleanup"
```

- [ ] **Step 4: Hand the migration to the user**

Report, do not run:

> Migration `20260811000001_kpi_measurables.sql` is ready. Apply with `supabase db push`. It prints a `NOTICE` line naming each KPI it deletes or deactivates — capture that output, it is the only record of which of the orphans went which way.

---

### Task 7: Models and repository carry the measurable

**Files:**
- Modify: `lib/data/models/kpi.dart`
- Modify: `lib/data/models/role_kpi.dart`
- Modify: `lib/data/repositories/role_scorecard_repository.dart` (`saveLibraryKpi` ~line 288, `saveRoleScorecardKpis` ~line 343)
- Test: `test/data/models/kpi_model_test.dart`

**Interfaces:**
- Consumes: `KpiGoal`, `goalColumns`, `frequencyLabelFromCadence` (Task 1).
- Produces: `Kpi` gains `valueType`, `numeratorLabel`, `numeratorSource`, `denominatorLabel`, `denominatorSource`, `unit`, `cadence`, `proofType`; `RoleKpi` gains `goal` (`KpiGoal?`), `unit`, `cadence`; `KpiLinkInput` gains `goal` (`KpiGoal?`) and `unit`; `RoleScorecardRepository.saveLibraryKpi` gains the same named parameters as `Kpi`'s new fields.

- [ ] **Step 1: Write the failing test**

Create `test/data/models/kpi_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';

void main() {
  test('Kpi.fromRow reads the measurable definition', () {
    final k = Kpi.fromRow({
      'id': 'k1',
      'company_id': 'c1',
      'name': 'Return Rate',
      'value_type': 'RATIO',
      'numerator_label': 'Returns received',
      'numerator_source': 'BigSeller',
      'denominator_label': 'Orders shipped',
      'denominator_source': 'BigSeller',
      'unit': '%',
      'cadence': 'WEEKLY',
      'proof_type': 'REPORT_EXPORT',
    });
    expect(k.valueType, 'RATIO');
    expect(k.numeratorLabel, 'Returns received');
    expect(k.denominatorSource, 'BigSeller');
    expect(k.unit, '%');
    expect(k.cadence, 'WEEKLY');
    expect(k.proofType, 'REPORT_EXPORT');
  });

  test('Kpi.fromRow defaults a legacy row rather than throwing', () {
    // Rows written before 20260811000001 have no definition at all.
    final k = Kpi.fromRow({
      'id': 'k1',
      'company_id': 'c1',
      'name': 'Documentation Accuracy',
    });
    expect(k.valueType, 'COUNT');
    expect(k.cadence, 'WEEKLY');
    expect(k.unit, isNull);
    expect(k.numeratorLabel, isNull);
  });

  test('Kpi.toInsert round-trips every definition column', () {
    const k = Kpi(
      id: '',
      companyId: 'c1',
      name: 'Return Rate',
      valueType: 'RATIO',
      numeratorLabel: 'Returns received',
      numeratorSource: 'BigSeller',
      denominatorLabel: 'Orders shipped',
      denominatorSource: 'BigSeller',
      unit: '%',
      cadence: 'WEEKLY',
      proofType: 'REPORT_EXPORT',
    );
    final row = k.toInsert('c1');
    expect(row['value_type'], 'RATIO');
    expect(row['numerator_label'], 'Returns received');
    expect(row['denominator_source'], 'BigSeller');
    expect(row['unit'], '%');
    expect(row['cadence'], 'WEEKLY');
    expect(row['proof_type'], 'REPORT_EXPORT');
  });

  test('Kpi.toInsert blanks empty strings to null', () {
    const k = Kpi(
      id: '',
      companyId: 'c1',
      name: 'X',
      numeratorLabel: '   ',
      unit: '',
    );
    final row = k.toInsert('c1');
    expect(row['numerator_label'], isNull);
    expect(row['unit'], isNull);
  });

  test('RoleKpi.fromRow lifts the goal and the KPI definition', () {
    final rk = RoleKpi.fromRow({
      'kpi_id': 'k1',
      'target': '≤ 3%',
      'frequency': 'Weekly',
      'goal_direction': 'LTE',
      'goal_value': 3,
      'kpis': {'name': 'Return Rate', 'unit': '%', 'cadence': 'WEEKLY'},
    });
    expect(rk.name, 'Return Rate');
    expect(rk.goal?.direction, GoalDirection.lte);
    expect(rk.goal?.value, 3);
    expect(rk.unit, '%');
    expect(rk.cadence, 'WEEKLY');
  });

  test('RoleKpi.fromRow leaves the goal null on a legacy link', () {
    final rk = RoleKpi.fromRow({
      'kpi_id': 'k1',
      'target': 'At least 98%',
      'kpis': {'name': 'Setup Accuracy'},
    });
    expect(rk.goal, isNull);
    expect(rk.target, 'At least 98%');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/data/models/kpi_model_test.dart
```

Expected: compile errors — `Kpi` has no named parameter `valueType`, `RoleKpi` has no getter `goal`.

- [ ] **Step 3: Widen `Kpi`**

In `lib/data/models/kpi.dart`, add the fields to `Kpi` (keeping the existing ones untouched), extend the constructor, `fromRow` and `toInsert`:

```dart
class Kpi {
  final String id;
  final String companyId;
  final String name;
  final String? category;
  final String? description;
  final String? measurementUnit;
  final bool isActive;

  /// The department that owns this measure. Organisational only — a role card
  /// in another department may still link it.
  final String? departmentId;

  // --- EOS measurable definition (20260811000001) ---------------------------
  /// COUNT | RATIO | CURRENCY | PERCENT | DURATION. See kKpiValueTypes.
  final String valueType;

  /// What is counted, and the system it is read from.
  final String? numeratorLabel;
  final String? numeratorSource;

  /// What it is counted against. RATIO only.
  final String? denominatorLabel;
  final String? denominatorSource;

  /// %, orders, days, ₱ — how the computed value reads.
  final String? unit;

  /// WEEKLY | MONTHLY | QUARTERLY. The measurable's own rhythm.
  final String cadence;

  /// REPORT_EXPORT | SCREENSHOT | SYSTEM_LINK, or null for no requirement.
  final String? proofType;

  const Kpi({
    required this.id,
    required this.companyId,
    required this.name,
    this.category,
    this.description,
    this.measurementUnit,
    this.isActive = true,
    this.departmentId,
    this.valueType = 'COUNT',
    this.numeratorLabel,
    this.numeratorSource,
    this.denominatorLabel,
    this.denominatorSource,
    this.unit,
    this.cadence = 'WEEKLY',
    this.proofType,
  });

  factory Kpi.fromRow(Map<String, dynamic> r) => Kpi(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    name: r['name'] as String,
    category: r['category'] as String?,
    description: r['description'] as String?,
    measurementUnit: r['measurement_unit'] as String?,
    isActive: r['is_active'] as bool? ?? true,
    departmentId: r['department_id'] as String?,
    // Defaulted rather than required: a select that predates the migration, or
    // one with a narrowed column list, must not throw here.
    valueType: r['value_type'] as String? ?? 'COUNT',
    numeratorLabel: r['numerator_label'] as String?,
    numeratorSource: r['numerator_source'] as String?,
    denominatorLabel: r['denominator_label'] as String?,
    denominatorSource: r['denominator_source'] as String?,
    unit: r['unit'] as String?,
    cadence: r['cadence'] as String? ?? 'WEEKLY',
    proofType: r['proof_type'] as String?,
  );

  Map<String, dynamic> toInsert(String companyId) => {
    'company_id': companyId,
    'name': name.trim(),
    'category': _blankToNull(category),
    'description': _blankToNull(description),
    'measurement_unit': _blankToNull(measurementUnit),
    'is_active': isActive,
    'department_id': departmentId,
    'value_type': valueType,
    'numerator_label': _blankToNull(numeratorLabel),
    'numerator_source': _blankToNull(numeratorSource),
    'denominator_label': _blankToNull(denominatorLabel),
    'denominator_source': _blankToNull(denominatorSource),
    'unit': _blankToNull(unit),
    'cadence': cadence,
    'proof_type': _blankToNull(proofType),
  };
}

String? _blankToNull(String? v) =>
    (v == null || v.trim().isEmpty) ? null : v.trim();
```

Then widen `KpiLinkInput` in the same file — it keeps `target`/`frequency` for callers that still pass text, and gains the structured goal plus the unit needed to render it:

```dart
/// One KPI attached to a role card, as edited in the workbench.
class KpiLinkInput {
  final String? kpiId; // null → create the library KPI on save
  final String name;
  final String? measurementUnit;
  final String? category;

  /// Legacy free text. Ignored when [goal] is set — the repository derives the
  /// stored `target` from the goal so the two can never disagree.
  final String target;
  final String frequency;

  /// The structured goal, plus the KPI's unit and cadence. [unit] renders the
  /// goal; [cadence] derives the stored `frequency`. Both are carried on the
  /// input because the caller already has the library row on screen — without
  /// [cadence] here, a link to an EXISTING library KPI would fall back to
  /// whatever free text the old link held and the measurable's rhythm would
  /// never reach the column.
  final KpiGoal? goal;
  final String? unit;
  final String? cadence;

  const KpiLinkInput({
    this.kpiId,
    required this.name,
    this.measurementUnit,
    this.category,
    required this.target,
    required this.frequency,
    this.goal,
    this.unit,
    this.cadence,
  });
}
```

Add `import 'kpi_goal.dart';` at the top of `lib/data/models/kpi.dart`.

- [ ] **Step 4: Widen `RoleKpi`**

Replace `lib/data/models/role_kpi.dart` with:

```dart
import 'kpi_goal.dart';

/// One KPI on a role card, with its stable library id — used by the per-employee
/// assignment UI (which keys on kpi_id) rather than the display-only KpiItem.
class RoleKpi {
  final String kpiId;
  final String name;

  /// Legacy display text, derived from [goal] on save. Still populated for
  /// links whose goal has not been set yet.
  final String? target;
  final String? frequency;

  /// The structured goal for this role. Null until the link is upgraded.
  final KpiGoal? goal;

  /// Lifted from the embedded library row so a caller can render the goal and
  /// judge a reading without a second query.
  final String? unit;
  final String? cadence;

  const RoleKpi({
    required this.kpiId,
    required this.name,
    this.target,
    this.frequency,
    this.goal,
    this.unit,
    this.cadence,
  });

  factory RoleKpi.fromRow(Map<String, dynamic> r) {
    final kpi = r['kpis'] as Map?;
    return RoleKpi(
      kpiId: r['kpi_id'] as String,
      name: kpi?['name'] as String? ?? '',
      target: r['target'] as String?,
      frequency: r['frequency'] as String?,
      goal: KpiGoal.fromRow(r),
      unit: kpi?['unit'] as String?,
      cadence: kpi?['cadence'] as String?,
    );
  }
}
```

- [ ] **Step 5: Run the model test**

```
flutter test test/data/models/kpi_model_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Widen the repository**

Three edits in `lib/data/repositories/role_scorecard_repository.dart`:

**a.** `saveLibraryKpi` — add the definition parameters and write them. Replace its signature and the `fields` map:

```dart
  Future<Kpi> saveLibraryKpi({
    String? id,
    required String companyId,
    required String name,
    String? category,
    String? description,
    String? measurementUnit,
    String valueType = 'COUNT',
    String? numeratorLabel,
    String? numeratorSource,
    String? denominatorLabel,
    String? denominatorSource,
    String? unit,
    String cadence = 'WEEKLY',
    String? proofType,
  }) async {
    String? blank(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    final fields = <String, dynamic>{
      'name': name.trim(),
      'category': blank(category),
      'description': blank(description),
      'measurement_unit': blank(measurementUnit),
      'is_active': true,
      'value_type': valueType,
      'numerator_label': blank(numeratorLabel),
      'numerator_source': blank(numeratorSource),
      'denominator_label': blank(denominatorLabel),
      'denominator_source': blank(denominatorSource),
      'unit': blank(unit),
      'cadence': cadence,
      'proof_type': blank(proofType),
    };
```

Leave the rest of the method (the id-update branch, the find-by-name branch, the insert) exactly as it is.

**b.** `saveRoleScorecardKpis` — derive `target` and `frequency`. Change the `resolved` record to carry the link input, and build the upsert rows through `goalColumns`:

```dart
    // 1. Resolve every link to a kpi_id (create library rows for new names).
    final resolved = <({String kpiId, KpiLinkInput link, String? cadence})>[];
    for (final link in links) {
      var kpiId = link.kpiId;
      // The caller supplies the cadence for an existing library KPI; only a
      // brand-new one has to be read back off the row we just created.
      var cadence = link.cadence;
      if (kpiId == null) {
        final kpi = await upsertKpi(
          companyId,
          Kpi(
            id: '',
            companyId: companyId,
            name: link.name,
            category: link.category,
            measurementUnit: link.measurementUnit,
            unit: link.unit,
            cadence: link.cadence ?? 'WEEKLY',
          ),
        );
        kpiId = kpi.id;
        cadence ??= kpi.cadence;
      }
      resolved.add((kpiId: kpiId, link: link, cadence: cadence));
    }
```

and replace the upsert block:

```dart
    // 3. Upsert the current links with their order. target and frequency are
    //    DERIVED — from the goal and the KPI's cadence — so the free-text
    //    columns the PDF and contract templates read can never drift from the
    //    structured values. A link with no goal keeps whatever text it had.
    if (deduped.isNotEmpty) {
      await _client.from('role_scorecard_kpis').upsert([
        for (var i = 0; i < deduped.length; i++)
          {
            'role_scorecard_id': roleScorecardId,
            'kpi_id': deduped[i].kpiId,
            'sort_order': i,
            'frequency':
                frequencyLabelFromCadence(deduped[i].cadence) ??
                (deduped[i].link.frequency.trim().isEmpty
                    ? null
                    : deduped[i].link.frequency.trim()),
            ...deduped[i].link.goal == null
                ? {
                    'target': deduped[i].link.target.trim().isEmpty
                        ? null
                        : deduped[i].link.target.trim(),
                    'goal_direction': null,
                    'goal_value': null,
                    'goal_value_max': null,
                  }
                : goalColumns(deduped[i].link.goal, deduped[i].link.unit),
          },
      ], onConflict: 'role_scorecard_id,kpi_id');
    }
```

Keep the existing dedupe (`seen.add(r.kpiId)`) and the delete-missing-links step unchanged; the dedupe now reads `r.kpiId` off the widened record, which needs no edit.

Add `import '../models/kpi_goal.dart';` to the repository's imports.

**c.** `roleKpisProvider`'s query — the embed must fetch the new columns. Find the `role_scorecard_kpis` select feeding `RoleKpi.fromRow` (around line 578) and widen its column list to:

```dart
'kpi_id, target, frequency, goal_direction, goal_value, goal_value_max, kpis(name, unit, cadence)'
```

- [ ] **Step 7: Run the full suite**

```
flutter test
```

Expected: `All tests passed!` — 1215 tests passed before this plan started; the count rises with the new files and nothing that passed may now fail. If `role_card_pdf_test` or an employment-contract test breaks, the derived `target` is wrong: fix `goalColumns`, not the test.

- [ ] **Step 8: Analyze**

```
flutter analyze lib test
```

Expected: no `error` or `warning` lines.

- [ ] **Step 9: Commit**

```bash
git add lib/data/models/kpi.dart lib/data/models/kpi_goal.dart lib/data/models/role_kpi.dart lib/data/repositories/role_scorecard_repository.dart test/data/models/kpi_model_test.dart
git commit -m "feat(kpi): persist measurable definition and derive target from the goal"
```

---

### Task 8: Reusable Supabase widget-test harness

**Files:**
- Create: `test/support/supabase_stub.dart`
- Modify: `test/features/responsibility_cards/scorecard_row_delete_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `Future<void> initSupabaseStub()` — call once from `setUpAll`. Plan 2's pane tests depend on it.

The workbench panes in Plan 2 all call `Supabase.instance.client`. This harness is what makes them testable; it exists today inline in one test file and is lifted here before it gets copy-pasted.

- [ ] **Step 1: Create the shared harness**

Create `test/support/supabase_stub.dart`:

```dart
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-in for the PKCE store, which otherwise reaches for the
/// shared_preferences platform channel that no test binding provides.
class _MemoryStorage extends GotrueAsyncStorage {
  final _items = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _items[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

/// Initialises Supabase so a screen that calls `Supabase.instance.client`
/// directly can be pumped in a widget test. Call once from `setUpAll`.
///
/// Every query answers with an empty result set: these tests exercise widget
/// behaviour, not data. Override the Riverpod providers for anything the test
/// needs populated.
///
/// Each argument here fixes a specific failure, so do not trim them:
///  * `request: request` — postgrest's _parseResponse dereferences
///    `response.request!`, so a response built without it throws a null-check
///    error on the first query.
///  * `autoRefreshToken: false` — the GoTrue refresh timer outlives the widget
///    and trips flutter_test's "Timer still pending" invariant.
///  * `pkceAsyncStorage` — the default reaches shared_preferences and throws
///    MissingPluginException.
///  * `detectSessionInUri: false` — the deep-link observer needs the app_links
///    platform channel.
Future<void> initSupabaseStub() async {
  await Supabase.initialize(
    url: 'https://stub.supabase.co',
    anonKey: 'stub-anon-key',
    httpClient: MockClient(
      (request) async => http.Response('[]', 200, request: request),
    ),
    authOptions: FlutterAuthClientOptions(
      autoRefreshToken: false,
      localStorage: const EmptyLocalStorage(),
      pkceAsyncStorage: _MemoryStorage(),
      detectSessionInUri: false,
    ),
  );
}
```

- [ ] **Step 2: Point the existing test at it**

In `test/features/responsibility_cards/scorecard_row_delete_test.dart`, delete the local `_MemoryStorage` class and the whole body of `setUpAll`, replacing it with:

```dart
import '../../support/supabase_stub.dart';

// ... in main():
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });
```

Remove the now-unused `http`, `http/testing` and `supabase_flutter` imports from that file.

- [ ] **Step 3: Run the test that already covers this**

```
flutter test test/features/responsibility_cards/scorecard_row_delete_test.dart
```

Expected: `+4: All tests passed!` — the same four cases as before the extraction. A `MissingPluginException` or a null-check error from postgrest means an argument was dropped from `initSupabaseStub`.

- [ ] **Step 4: Analyze**

```
flutter analyze lib test
```

Expected: no `error` or `warning` lines. An `unused_import` info in the edited test means step 2 left an import behind — remove it.

- [ ] **Step 5: Commit**

```bash
git add test/support/supabase_stub.dart test/features/responsibility_cards/scorecard_row_delete_test.dart
git commit -m "test: extract the Supabase widget-test harness for reuse"
```

---

## Done when

- `flutter test` is green with the ~40 new cases across seven new test files.
- `flutter analyze lib test` reports no errors or warnings.
- `supabase/migrations/20260811000001_kpi_measurables.sql` exists, is committed, and has been handed to the user to apply — **not applied by an implementer**.
- No UI has changed. The card editor, KPI Library and Workforce Planning all behave exactly as they did.

## Next plans

- **Plan 2 — the workbench.** `/workforce-planning/roles/:id` with the four panes; Roles tab drill-in. Depends on every module here.
- **Plan 3 — retire the card editor.** Delete `role_scorecard_form_screen.dart` and its two routes; "New role" moves to the Roles tab.
- **Plan 4 — Needs attention.** The two new chips and click-through on the existing ones.
