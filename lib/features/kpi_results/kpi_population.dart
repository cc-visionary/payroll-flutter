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
///
/// [employeeId] only matters at Personal scope. Same fail-safe principle as
/// Department scope's missing [departmentId]: an unconfigured scope resolves
/// to nobody, never to everybody — so a missing [employeeId] (or one that
/// isn't an active, non-deleted holder) returns empty rather than falling
/// back to the whole employee list.
List<String> populationFor({
  required KpiScope scope,
  String? departmentId,
  String? employeeId,
  required List<Employee> employees,
  required List<RoleScorecard> roles,
}) {
  // Duplicate ids in [employees] are not de-duplicated here — harmless while
  // every caller passes one non-overlapping list, but would double-count an
  // id if a future caller ever merges overlapping employee lists.
  final deptByRole = {
    // If two roles ever shared an id this would silently keep the last one —
    // relying on `role_scorecards.id` being unique, as the schema guarantees.
    for (final r in roles) r.id: r.departmentId,
  };

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
        // A department id that matches no role at all lands here the same as
        // an unconfigured one — both resolve to empty, indistinguishably.
        if (deptByRole[roleId] != departmentId) continue;
        ids.add(e.id);
      case KpiScope.personal:
        // No employee id asked for means no population — same fail-safe as
        // Department scope, never fall back to "everyone".
        if (employeeId == null) continue;
        if (e.id != employeeId) continue;
        ids.add(e.id);
    }
  }
  ids.sort();
  return ids;
}
