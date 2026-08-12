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
  }) : assert(
         direction != GoalDirection.between ||
             (valueMax != null && valueMax > value),
         'a BETWEEN goal requires valueMax, and valueMax must be greater '
         'than value — otherwise formatGoal renders an inverted range '
         '("10 to 5 days") and isOnTrack evaluates an empty one',
       );

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

/// A BETWEEN goal's rendering: a symbol unit (`₱`, `$`) hugs both bounds
/// (`₱5 to ₱10`) since neither reads as a bare number in a currency range; a
/// word unit (`days`) reads naturally on the upper bound alone (`5 to 10
/// days`, not `5 days to 10 days`).
String _formatBetween(KpiGoal goal, String? unit) {
  final upper = _withUnit(goal.valueMax ?? goal.value, unit);
  final symbolUnit =
      unit != null && unit.trim().isNotEmpty && !_unitIsWord(unit.trim());
  final lower = symbolUnit ? _withUnit(goal.value, unit) : _trimNumber(goal.value);
  return '$lower to $upper';
}

/// The human rendering of a goal, and the value written to the legacy
/// `target` column.
String formatGoal(KpiGoal goal, String? unit) => switch (goal.direction) {
  GoalDirection.gte => '≥ ${_withUnit(goal.value, unit)}',
  GoalDirection.lte => '≤ ${_withUnit(goal.value, unit)}',
  GoalDirection.eq => '= ${_withUnit(goal.value, unit)}',
  GoalDirection.between => _formatBetween(goal, unit),
};

final _gte = RegExp(r'(at\s*least|\bminimum\b|\bmin\.?\b|(no|not)\s*less\s*than|≥|>=)', caseSensitive: false);
final _lte = RegExp(
  r'(at\s*most|\bmaximum\b|\bmax\.?\b|no\s*more\s*than|less\s*than|\bunder\b|\bbelow\b|\bwithin\b|≤|<=)',
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
  if (_gte.hasMatch(s) && value != null) {
    return KpiGoal(direction: GoalDirection.gte, value: value);
  }
  if (_lte.hasMatch(s) && value != null) {
    return KpiGoal(direction: GoalDirection.lte, value: value);
  }
  // "Zero defects", "No preventable errors" — a ceiling of nothing.
  if (value == null && _zero.hasMatch(s)) {
    return const KpiGoal(direction: GoalDirection.lte, value: 0);
  }
  return null;
}

/// The columns a role→KPI link writes for its goal, including the legacy
/// `target` text. One place, so `target` can never drift from the goal.
///
/// With a [goal], `target` is DERIVED from it and [legacyTarget] is ignored —
/// the structured value always wins over free text.
///
/// Without one, `target` falls back to [legacyTarget]. That column predates
/// goals and, on a link that never had one, holds prose nobody can regenerate
/// ("Consistently high quality") which `role_card_pdf.dart` and the
/// employment contract's Annex A print. So the caller decides: supply the
/// stored prose for a link that arrived with no goal, and supply nothing for
/// a link whose goal the caller itself authored and has now cleared — in the
/// latter case the stored text was derived FROM that goal, and echoing it
/// back would leave the card printing a bar nobody holds.
Map<String, dynamic> goalColumns(
  KpiGoal? goal,
  String? unit, {
  String? legacyTarget,
}) {
  final legacy = (legacyTarget ?? '').trim();
  return {
    'goal_direction': goal == null ? null : goalDirectionCode(goal.direction),
    'goal_value': goal?.value,
    'goal_value_max': goal?.valueMax,
    'target': goal != null
        ? formatGoal(goal, unit)
        : (legacy.isEmpty ? null : legacy),
  };
}

/// The legacy `frequency` text, derived from the KPI's cadence — an EOS
/// measurable has one rhythm, so the link no longer carries its own.
String? frequencyLabelFromCadence(String? cadence) => switch (cadence) {
  'WEEKLY' => 'Weekly',
  'MONTHLY' => 'Monthly',
  'QUARTERLY' => 'Quarterly',
  _ => null,
};
