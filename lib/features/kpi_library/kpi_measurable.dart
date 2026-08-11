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
