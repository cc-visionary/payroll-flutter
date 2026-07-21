import 'package:decimal/decimal.dart';

import '../../data/models/employee.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import 'capacity_math.dart';

/// Working days per month used to express a DAILY/HOURLY role rate as a monthly
/// figure. Mirrors `kStandardWorkDaysPerMonth` in the documents layer and the
/// value `compute_service` passes to the payroll engine — a different number
/// here would make workforce planning quietly disagree with payroll.
const int kRoleCostWorkDaysPerMonth = 26;

/// One role card's rolled-up effort and money.
///
/// This is the ROLE lens on the same data the person lens shows: the per-person
/// view asks "is Jeremy overloaded?", this asks "is the Operations Manager ROLE
/// overloaded, whoever holds it?".
class RoleRollupRow {
  const RoleRollupRow({
    required this.cardId,
    required this.jobTitle,
    required this.holders,
    required this.responsibilities,
    required this.costedResponsibilities,
    required this.hoursPerMonth,
    required this.capacityHours,
    required this.monthlyCost,
  });

  final String cardId;
  final String jobTitle;

  /// ACTIVE, non-deleted employees holding this card.
  final int holders;
  final int responsibilities;
  final int costedResponsibilities;

  /// Total hours/month for the role's whole responsibility set — NOT divided
  /// among holders. The role's workload is what it is regardless of headcount;
  /// dividing is what [loadFraction] does via [capacityHours].
  final double hoursPerMonth;

  /// Combined capacity of everyone holding the role (0 when nobody does).
  final double capacityHours;

  /// Monthly peso cost of the people holding this role, or null when the card
  /// has no base salary.
  final Decimal? monthlyCost;

  bool get fullyCosted =>
      responsibilities > 0 && costedResponsibilities == responsibilities;

  /// Null when nothing is costed yet — an uncosted role must read as "unknown",
  /// never as a confident 0%.
  double? get loadFraction =>
      costedResponsibilities == 0 || capacityHours <= 0
          ? null
          : hoursPerMonth / capacityHours;

  LoadStatus? get status {
    final f = loadFraction;
    return f == null ? null : loadStatus(f);
  }

  /// Peso per costed hour — what an hour of this role's modelled work costs.
  /// Null while hours are unknown, so a partially-costed role can't advertise a
  /// misleadingly high rate.
  Decimal? get costPerHour {
    final c = monthlyCost;
    if (c == null || hoursPerMonth <= 0 || costedResponsibilities == 0) return null;
    return (c / Decimal.parse(hoursPerMonth.toString()))
        .toDecimal(scaleOnInfinitePrecision: 4);
  }
}

/// Monthly cost of ONE holder of a role, from the card's base salary.
/// Mirrors `dailyRateFrom` in the payroll engine, inverted to a month.
Decimal? monthlyCostPerHolder(RoleScorecard card) {
  final base = card.baseSalary;
  if (base == null) return null;
  switch (card.wageType) {
    case 'DAILY':
      return base * Decimal.fromInt(kRoleCostWorkDaysPerMonth);
    case 'HOURLY':
      return base *
          Decimal.fromInt(card.workHoursPerDay) *
          Decimal.fromInt(kRoleCostWorkDaysPerMonth);
    case 'MONTHLY':
    default:
      return base;
  }
}

/// Rolls tasks, holders and pay up to one row per role card.
///
/// [capacityHoursFor] resolves a holder's capacity (override, else the company
/// default) so this matches what `wp_person_load` would say for the same people.
List<RoleRollupRow> buildRoleRollup({
  required List<RoleScorecard> cards,
  required List<Employee> employees,
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computedByTaskId,
  required double multiplier,
  required double Function(String employeeId) capacityHoursFor,
}) {
  final holdersByCard = <String, List<Employee>>{};
  for (final e in employees) {
    // "Active" in this app means ACTIVE *and* not soft-deleted — the same pair
    // wp_person_load filters on. Counting either alone inflates the role.
    if (e.employmentStatus != 'ACTIVE' || e.deletedAt != null) continue;
    final cardId = e.roleScorecardId;
    if (cardId == null) continue;
    (holdersByCard[cardId] ??= []).add(e);
  }

  final tasksByCard = <String, List<WpTask>>{};
  for (final t in tasks) {
    final cardId = t.roleScorecardId;
    if (cardId == null) continue;
    (tasksByCard[cardId] ??= []).add(t);
  }

  final rows = <RoleRollupRow>[];
  for (final card in cards) {
    final holders = holdersByCard[card.id] ?? const <Employee>[];
    final cardTasks = tasksByCard[card.id] ?? const <WpTask>[];

    var hours = 0.0;
    var costed = 0;
    for (final t in cardTasks) {
      final c = computedByTaskId[t.id];
      if (c == null || c.hoursPerMonthBase <= 0) continue;
      costed++;
      hours += c.isGrowing
          ? c.hoursPerMonthBase * multiplier
          : c.hoursPerMonthBase;
    }

    final perHolder = monthlyCostPerHolder(card);
    rows.add(RoleRollupRow(
      cardId: card.id,
      jobTitle: card.jobTitle,
      holders: holders.length,
      responsibilities: cardTasks.length,
      costedResponsibilities: costed,
      hoursPerMonth: hours,
      capacityHours:
          holders.fold(0.0, (sum, e) => sum + capacityHoursFor(e.id)),
      monthlyCost:
          perHolder == null ? null : perHolder * Decimal.fromInt(holders.length),
    ));
  }

  rows.sort((a, b) => a.jobTitle.toLowerCase().compareTo(b.jobTitle.toLowerCase()));
  return rows;
}

/// Column totals. Load is deliberately absent: summing percentages across roles
/// is meaningless, and a total load% would be read as "the company is N% busy"
/// while most responsibilities are still uncosted.
class RoleRollupTotals {
  const RoleRollupTotals({
    required this.holders,
    required this.responsibilities,
    required this.costedResponsibilities,
    required this.hoursPerMonth,
    required this.monthlyCost,
  });

  final int holders;
  final int responsibilities;
  final int costedResponsibilities;
  final double hoursPerMonth;
  final Decimal monthlyCost;

  int get uncosted => responsibilities - costedResponsibilities;
}

RoleRollupTotals totalRoleRollup(List<RoleRollupRow> rows) => RoleRollupTotals(
      holders: rows.fold(0, (s, r) => s + r.holders),
      responsibilities: rows.fold(0, (s, r) => s + r.responsibilities),
      costedResponsibilities: rows.fold(0, (s, r) => s + r.costedResponsibilities),
      hoursPerMonth: rows.fold(0.0, (s, r) => s + r.hoursPerMonth),
      monthlyCost: rows.fold(
          Decimal.zero, (s, r) => s + (r.monthlyCost ?? Decimal.zero)),
    );
