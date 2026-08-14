import '../../data/models/kpi_result.dart';
import '../../data/models/kpi_source_config.dart';

// SubjectKind lives in the model layer (see kpi_source_config.dart's doc
// comment) but every caller of this file reaches it through here — the same
// export shape the brief's Interfaces block describes — so this re-export
// keeps that surface intact without duplicating the enum.
export '../../data/models/kpi_source_config.dart' show SubjectKind;

/// One row as returned by an external source: whatever `subjectKey` names
/// (an employee, a department, or nothing at all — see [SubjectKind]) and
/// this period's numerator/denominator for it.
///
/// [numerator] and [denominator] are independently nullable: a COUNT KPI has
/// no denominator at all (never coerce that to zero — see
/// [aggregateSourceRows]'s doc comment), and a source that could not answer
/// for this subject reports both null rather than a false zero.
class SourceRow {
  final String subjectKey;
  final num? numerator;
  final num? denominator;

  const SourceRow({
    required this.subjectKey,
    this.numerator,
    this.denominator,
  });
}

/// Sums the non-null numerators (respectively denominators) across [rows].
/// A field with no non-null contributor anywhere in [rows] comes back null,
/// never zero — this is what turns "nothing matched" and "every row's value
/// was null" into an honest NO_DATA instead of a false 0, and it is the one
/// place [aggregateSourceRows] actually adds numbers together.
({num? numerator, num? denominator}) _sum(Iterable<SourceRow> rows) {
  num? numerator;
  num? denominator;
  for (final row in rows) {
    final n = row.numerator;
    if (n != null) numerator = (numerator ?? 0) + n;
    final d = row.denominator;
    if (d != null) denominator = (denominator ?? 0) + d;
  }
  return (numerator: numerator, denominator: denominator);
}

/// Turns one external source's raw rows into the numerator/denominator pair
/// for a single KPI scope — the same `(numerator, denominator)` shape
/// `KpiSourceInput` uses in `automatic_sources.dart`, so both feed
/// `evaluateKpi` (`kpi_status.dart`) identically.
///
/// **Department and company are SUMS of numerators and denominators, never
/// averages of ratios.** Alice 30/30 and Bob 10/50 is 40/80 = 0.5, not the
/// 0.6 averaging their two ratios would give — rows carry numerator and
/// denominator separately precisely so this function can add them instead
/// of averaging a percentage that already lost the volume behind it.
///
/// [subjectKind] decides how [rows] identify who a figure belongs to:
/// - [SubjectKind.employee] — `subjectKey` resolves through
///   [subjectToEmployee] to an employee id, which resolves through
///   [employeeToDepartment] to a department. A `subjectKey` absent from
///   [subjectToEmployee] is unresolved: it still counts toward COMPANY (it
///   happened; dropping it would silently undercount the one figure it can
///   still contribute to) but is excluded from every DEPARTMENT figure —
///   there is no identity behind it to attribute to one — and sets
///   [unresolvedPresent] so something upstream can surface it for a human
///   to map.
/// - [SubjectKind.department] — `subjectKey` IS the department id already;
///   there is no employee behind it, so PERSONAL always comes back with no
///   data for rows of this kind.
/// - [SubjectKind.none] — the source answers a single company-wide figure
///   and `subjectKey` is ignored; PERSONAL and DEPARTMENT both come back
///   with no data, for the same "no identity behind it" reason.
///
/// Every "nothing to report" path — no rows, no row for the requested
/// subject, a requested scope this row kind cannot answer, every value in
/// the rows that do apply being null, [KpiScope.personal] requested with no
/// [employeeId] — returns `(null, null)`. Never `(0, 0)`: zero is a claim
/// that something was measured and came out empty, and the engine turns
/// null into NO_DATA rather than a false red square.
({num? numerator, num? denominator, bool unresolvedPresent}) aggregateSourceRows({
  required List<SourceRow> rows,
  required KpiScope scope,
  required SubjectKind subjectKind,
  required Map<String, String> subjectToEmployee,
  required Map<String, String> employeeToDepartment,
  String? employeeId,
  String? departmentId,
}) {
  switch (subjectKind) {
    case SubjectKind.none:
      // No subject to resolve, so no unresolved-subject concept either.
      if (scope != KpiScope.company) {
        return (numerator: null, denominator: null, unresolvedPresent: false);
      }
      final totals = _sum(rows);
      return (
        numerator: totals.numerator,
        denominator: totals.denominator,
        unresolvedPresent: false,
      );

    case SubjectKind.department:
      // subjectKey IS the department id — no employee behind it, so a
      // personal figure is never possible from rows of this kind.
      if (scope == KpiScope.personal) {
        return (numerator: null, denominator: null, unresolvedPresent: false);
      }
      // Company sums every department's rows; department narrows to one.
      final included = scope == KpiScope.department
          ? rows.where((r) => r.subjectKey == departmentId)
          : rows;
      final totals = _sum(included);
      return (
        numerator: totals.numerator,
        denominator: totals.denominator,
        unresolvedPresent: false,
      );

    case SubjectKind.employee:
      // Resolve every row's subject once. A key absent from
      // subjectToEmployee is unresolved: it happened, so it still counts
      // toward COMPANY below, but there is no identity behind it to
      // attribute to a department or a person.
      final resolvedRows = [
        for (final row in rows)
          (row: row, employeeId: subjectToEmployee[row.subjectKey]),
      ];
      final unresolvedPresent = resolvedRows.any((r) => r.employeeId == null);

      switch (scope) {
        case KpiScope.company:
          // Unresolved subjects are included here: dropping them would
          // silently undercount the one figure they can still contribute to.
          final totals = _sum(rows);
          return (
            numerator: totals.numerator,
            denominator: totals.denominator,
            unresolvedPresent: unresolvedPresent,
          );

        case KpiScope.department:
          if (departmentId == null) {
            return (
              numerator: null,
              denominator: null,
              unresolvedPresent: unresolvedPresent,
            );
          }
          final included = resolvedRows.where((r) {
            final empId = r.employeeId;
            if (empId == null) return false; // unresolved: excluded here.
            return employeeToDepartment[empId] == departmentId;
          }).map((r) => r.row);
          final totals = _sum(included);
          return (
            numerator: totals.numerator,
            denominator: totals.denominator,
            unresolvedPresent: unresolvedPresent,
          );

        case KpiScope.personal:
          // No requested employee resolves to nobody, never everyone.
          if (employeeId == null) {
            return (
              numerator: null,
              denominator: null,
              unresolvedPresent: unresolvedPresent,
            );
          }
          final included = resolvedRows
              .where((r) => r.employeeId == employeeId)
              .map((r) => r.row);
          final totals = _sum(included);
          return (
            numerator: totals.numerator,
            denominator: totals.denominator,
            unresolvedPresent: unresolvedPresent,
          );
      }
  }
}
