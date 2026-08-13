import '../../data/models/employee.dart';
import '../../data/models/kpi.dart';
import '../../data/models/kpi_goal.dart';
import '../../data/models/kpi_input.dart';
import '../../data/models/kpi_result.dart';
import '../../data/models/role_scorecard.dart';
import 'automatic_sources.dart';
import 'exception_aggregation.dart';
import 'kpi_population.dart';
import 'kpi_rollup.dart';
import 'kpi_status.dart';

/// Turns [kpis] plus every raw input Tasks 1-6 built into [period]'s
/// `kpi_results` rows.
///
/// ASSEMBLY ONLY. Every rule this file applies already has its own tested
/// module, and this function calls each of them rather than re-deriving what
/// they already decide:
/// - [scopesFor] (kpi_rollup.dart) — which scopes a KPI produces.
/// - [populationFor] (kpi_population.dart) — whose data counts at a scope.
/// - [confirmedCountFor] (exception_aggregation.dart) — the exception sum.
/// - [evaluateKpi] (kpi_status.dart) — value and status from raw inputs.
///
/// Two binding decisions this file DOES make, because nothing built so far
/// makes them and a migration is out of scope for this task:
///
/// 1. **The registry key.** `kpis.numerator_source` is reused to name a
///    [KpiSource] (`registry[kpi.numeratorSource]`) for `AUTOMATIC`/`HYBRID`
///    KPIs. `automatic_sources.dart`'s own comment says the registry key "is
///    what a KPI's data method will eventually name (a Task 7 concern, not
///    this file's)" and leaves the binding open; `numeratorSource`'s own doc
///    comment — "what is counted, and the SYSTEM IT IS READ FROM" — is the
///    one column already shaped like a source name. A manually-sourced KPI
///    keeps using it as free text ("BigSeller", "Temu"); an automatic one
///    repurposes the same column to hold a registry key instead. No new
///    column, no migration.
/// 2. **A DEPARTMENT scope needs exactly one department, from
///    `kpi.departmentId`.** A KPI whose own level is DEPARTMENT, or a
///    PERSONAL KPI rolling up to DEPARTMENT, has no per-employee assignment
///    list to consult here (`role_scorecard_kpis` is not one of this
///    function's inputs — see the task-6 carry-forward note this task
///    inherits, which is about a different gap in the same shape). Rather
///    than guess by iterating every department in [roles] — the wide,
///    plausible-looking answer this whole plan has repeatedly rejected — a
///    KPI with no `departmentId` produces NO department row. This also
///    fixes who is eligible for a PERSONAL row: a KPI with a `departmentId`
///    is personal-scoped to that department's roster; one without is
///    personal-scoped to the whole company. `scopesFor` still decides
///    WHETHER a department row exists; this only decides WHICH department.
Future<List<KpiResult>> computeResults({
  required String period,
  required List<Kpi> kpis,
  required List<Employee> employees,
  required List<RoleScorecard> roles,
  required Map<String, KpiSource> registry,
  required List<KpiException> exceptions,
  required List<KpiReading> readings,
}) async {
  final rows = <KpiResult>[];

  for (final kpi in kpis) {
    final scopes = scopesFor(level: kpi.level, rollupType: kpi.rollupType);
    if (scopes.isEmpty) continue; // unrecognised level: compute nothing.

    final direction = _direction(kpi.targetDirection);
    final kpiExceptions = exceptions.where((e) => e.kpiId == kpi.id).toList();
    final kpiReadings = readings.where((r) => r.kpiId == kpi.id).toList();

    if (scopes.contains(KpiScope.company)) {
      final population = populationFor(
        scope: KpiScope.company,
        employees: employees,
        roles: roles,
      );
      rows.add(
        await _row(
          kpi: kpi,
          period: period,
          scope: KpiScope.company,
          population: population,
          direction: direction,
          registry: registry,
          kpiExceptions: kpiExceptions,
          kpiReadings: kpiReadings,
        ),
      );
    }

    String? deptRow; // the one department this KPI's department row covers.
    if (scopes.contains(KpiScope.department) && kpi.departmentId != null) {
      deptRow = kpi.departmentId;
      final population = populationFor(
        scope: KpiScope.department,
        departmentId: deptRow,
        employees: employees,
        roles: roles,
      );
      rows.add(
        await _row(
          kpi: kpi,
          period: period,
          scope: KpiScope.department,
          population: population,
          departmentId: deptRow,
          direction: direction,
          registry: registry,
          kpiExceptions: kpiExceptions,
          kpiReadings: kpiReadings,
        ),
      );
    }

    if (scopes.contains(KpiScope.personal)) {
      // See decision 2 above: a department-homed KPI is personal-scoped to
      // that department's roster; an unhomed one is personal-scoped to
      // everybody. Either way this is populationFor doing the resolving,
      // not a hand-rolled filter.
      final roster = kpi.departmentId != null
          ? populationFor(
              scope: KpiScope.department,
              departmentId: kpi.departmentId,
              employees: employees,
              roles: roles,
            )
          : populationFor(scope: KpiScope.company, employees: employees, roles: roles);

      for (final employeeId in roster) {
        final population = populationFor(
          scope: KpiScope.personal,
          employeeId: employeeId,
          employees: employees,
          roles: roles,
        );
        if (population.isEmpty) continue; // defensive; roster is already active-only.
        rows.add(
          await _row(
            kpi: kpi,
            period: period,
            scope: KpiScope.personal,
            population: population,
            employeeId: employeeId,
            direction: direction,
            registry: registry,
            kpiExceptions: kpiExceptions,
            kpiReadings: kpiReadings,
          ),
        );
      }
    }
  }

  return rows;
}

/// `kpis.target_direction` speaks HIGHER/LOWER (see `kKpiTargetDirections`);
/// [KpiResult.direction] speaks [GoalDirection]'s GTE/LTE/EQ/BETWEEN, the
/// vocabulary `evaluateKpi` and a role's own per-KPI goal share. There is no
/// column for a default BETWEEN or EQ target — `kpis` only ever carries a
/// floor or a ceiling — so those two `GoalDirection` values are unreachable
/// from this function by construction, not by an omitted case.
GoalDirection? _direction(String? targetDirection) => switch (targetDirection) {
  'HIGHER' => GoalDirection.gte,
  'LOWER' => GoalDirection.lte,
  _ => null,
};

/// One row: resolve inputs by `data_method`, evaluate, snapshot the target.
Future<KpiResult> _row({
  required Kpi kpi,
  required String period,
  required KpiScope scope,
  required List<String> population,
  String? employeeId,
  String? departmentId,
  required GoalDirection? direction,
  required Map<String, KpiSource> registry,
  required List<KpiException> kpiExceptions,
  required List<KpiReading> kpiReadings,
}) async {
  final inputs = await _inputsFor(
    kpi: kpi,
    period: period,
    scope: scope,
    population: population,
    employeeId: employeeId,
    departmentId: departmentId,
    registry: registry,
    kpiExceptions: kpiExceptions,
    kpiReadings: kpiReadings,
  );

  final evaluated = evaluateKpi(
    valueType: kpi.valueType,
    numerator: inputs.numerator,
    denominator: inputs.denominator,
    target: kpi.targetValue,
    direction: direction,
  );

  return KpiResult(
    companyId: kpi.companyId,
    kpiId: kpi.id,
    period: period,
    scope: scope,
    employeeId: employeeId,
    departmentId: departmentId,
    numerator: inputs.numerator,
    denominator: inputs.denominator,
    value: evaluated.value,
    // The target AS IT IS NOW. A later edit to kpi.targetValue changes what
    // the NEXT computeResults call snapshots; it never reaches back and
    // reclassifies a row already written for a closed period, because
    // nothing here reads or mutates a prior row.
    targetSnapshot: kpi.targetValue,
    // kpis carries only a floor or a ceiling (see _direction) — there is no
    // default upper bound to snapshot here. A role's own BETWEEN goal is a
    // role_scorecard_kpis concern this function's signature does not see.
    targetMaxSnapshot: null,
    direction: direction,
    status: evaluated.status,
    sourceCompleteness: inputs.completeness,
  );
}

typedef _Inputs = ({num? numerator, num? denominator, SourceCompleteness completeness});

/// Input precedence by `data_method` (see the class-level table in the
/// task brief this implements):
///
/// | data_method | numerator | denominator |
/// |---|---|---|
/// | AUTOMATIC | registry | registry |
/// | HYBRID | registry, minus confirmed exceptions | registry |
/// | MANUAL_EXCEPTION | confirmed exceptions | reading, if any |
/// | MANUAL_PERIODIC | reading | reading |
Future<_Inputs> _inputsFor({
  required Kpi kpi,
  required String period,
  required KpiScope scope,
  required List<String> population,
  String? employeeId,
  String? departmentId,
  required Map<String, KpiSource> registry,
  required List<KpiException> kpiExceptions,
  required List<KpiReading> kpiReadings,
}) async {
  switch (kpi.dataMethod) {
    case 'AUTOMATIC':
      {
        final source = registry[kpi.numeratorSource];
        if (source == null) {
          return (
            numerator: null,
            denominator: null,
            completeness: SourceCompleteness.missingSource,
          );
        }
        final input = await source.read(
          scope: scope,
          period: period,
          employeeIds: population,
        );
        return (
          numerator: input.numerator,
          denominator: input.denominator,
          completeness: input.numerator == null
              ? SourceCompleteness.missingSource
              : SourceCompleteness.complete,
        );
      }

    case 'HYBRID':
      {
        final source = registry[kpi.numeratorSource];
        if (source == null) {
          return (
            numerator: null,
            denominator: null,
            completeness: SourceCompleteness.missingSource,
          );
        }
        final input = await source.read(
          scope: scope,
          period: period,
          employeeIds: population,
        );
        // MISSING MUST NEVER BECOME ZERO: a null registry numerator stays
        // null here. Subtracting confirmed exceptions from it would turn
        // "we don't know" into a confident negative.
        if (input.numerator == null) {
          return (
            numerator: null,
            denominator: input.denominator,
            completeness: SourceCompleteness.missingSource,
          );
        }
        final confirmed = _confirmedSum(
          kpi: kpi,
          kpiExceptions: kpiExceptions,
          period: period,
          population: population,
        );
        return (
          numerator: input.numerator! - confirmed,
          denominator: input.denominator,
          completeness: SourceCompleteness.complete,
        );
      }

    case 'MANUAL_EXCEPTION':
      {
        final scoped = _scopedExceptions(
          kpi: kpi,
          kpiExceptions: kpiExceptions,
          population: population,
        );
        final forPeriod = scoped
            .where((e) => _periodOf(e.occurredOn) == period)
            .toList();
        final reading = _readingFor(
          kpiReadings,
          period: period,
          scope: scope,
          employeeId: employeeId,
          departmentId: departmentId,
        );

        // Three zeros, told apart by whether rows exist and whether any of
        // them are confirmed — never by the sum alone, which cannot tell
        // "nothing happened" from "nothing confirmed yet" from "confirmed,
        // and it was zero".
        if (forPeriod.isEmpty) {
          // No exception rows at all: nothing to report, and nothing wrong
          // with the source either.
          return (
            numerator: null,
            denominator: reading?.denominator,
            completeness: SourceCompleteness.complete,
          );
        }
        if (!forPeriod.any((e) => e.confirmedAt != null)) {
          // Rows exist, none confirmed: still no number, but the source is
          // visibly incomplete rather than silent.
          return (
            numerator: null,
            denominator: reading?.denominator,
            completeness: SourceCompleteness.missingSource,
          );
        }
        // Confirmed rows exist; their sum is a real result, even if it is 0.
        return (
          numerator: confirmedCountFor(exceptions: forPeriod, period: period),
          denominator: reading?.denominator,
          completeness: SourceCompleteness.complete,
        );
      }

    case 'MANUAL_PERIODIC':
      {
        final reading = _readingFor(
          kpiReadings,
          period: period,
          scope: scope,
          employeeId: employeeId,
          departmentId: departmentId,
        );
        return (
          numerator: reading?.numerator,
          denominator: reading?.denominator,
          completeness: SourceCompleteness.complete,
        );
      }

    default:
      // The CHECK constraint on kpis.data_method makes this unreachable
      // today; an unrecognised method computes nothing rather than guessing
      // a path, the same fail-closed rule kpi_rollup.dart and
      // kpi_population.dart already apply to their own unrecognised inputs.
      return (
        numerator: null,
        denominator: null,
        completeness: SourceCompleteness.complete,
      );
  }
}

/// Which of [kpiExceptions] (already filtered to one `kpi.id` by the caller)
/// belong to this row's population.
///
/// A PERSONAL-level KPI can be adopted by roles in more than one department
/// (`kpis.department_id` is "organisational only" — see `kpi.dart`), so its
/// exceptions are attributed per employee and must be restricted to the
/// row's own [population] or a wider-scoped row would silently absorb
/// another department's numbers. A DEPARTMENT/COMPANY-level KPI has exactly
/// one department row (decision 2 on `computeResults`), so every exception
/// filed against it already belongs there, attributed to an employee or not
/// — no population restriction is possible or needed.
List<KpiException> _scopedExceptions({
  required Kpi kpi,
  required List<KpiException> kpiExceptions,
  required List<String> population,
}) {
  if (kpi.level != 'PERSONAL') return kpiExceptions;
  final ids = population.toSet();
  return kpiExceptions
      .where((e) => e.employeeId != null && ids.contains(e.employeeId))
      .toList();
}

/// The confirmed sum for this row, restricted to [population] the same way
/// [_scopedExceptions] restricts existence — delegates the actual counting
/// rule (confirmed-only, bucketed by `occurred_on`) to [confirmedCountFor]
/// rather than re-deriving it.
num _confirmedSum({
  required Kpi kpi,
  required List<KpiException> kpiExceptions,
  required String period,
  required List<String> population,
}) => confirmedCountFor(
  exceptions: _scopedExceptions(
    kpi: kpi,
    kpiExceptions: kpiExceptions,
    population: population,
  ),
  period: period,
);

/// The one reading (if any) recorded for this exact row identity — the same
/// five-part key `kpi_results`' own unique index uses. Not an aggregate:
/// `kpi_readings` holds one number someone counted for the whole scope, so
/// there is nothing to sum.
KpiReading? _readingFor(
  List<KpiReading> kpiReadings, {
  required String period,
  required KpiScope scope,
  String? employeeId,
  String? departmentId,
}) {
  for (final r in kpiReadings) {
    if (r.period != period) continue;
    if (r.scope != scope) continue;
    if (r.employeeId != employeeId) continue;
    if (r.departmentId != departmentId) continue;
    return r;
  }
  return null;
}

/// `YYYY-MM` for a [DateTime]. Used ONLY to check whether an exception row
/// exists in this period at all — the confirmed SUM itself always goes
/// through [confirmedCountFor], which does its own bucketing internally.
/// This exact bucketing rule is already duplicated once, deliberately, in
/// `automatic_sources.dart` (`_period`) for the same reason: no exported
/// primitive answers "is this date in this period" on its own, and every
/// caller needing it independently would otherwise import a private helper.
String _periodOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';
