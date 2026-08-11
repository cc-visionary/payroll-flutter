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
    final unmeasurable = selectedKpiIds.difference(measurableKpiIds);
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
