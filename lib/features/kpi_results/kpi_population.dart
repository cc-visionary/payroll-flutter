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
List<String> populationFor({
  required KpiScope scope,
  String? departmentId,
  required List<Employee> employees,
  required List<RoleScorecard> roles,
}) {
  final deptByRole = {for (final r in roles) r.id: r.departmentId};

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
        if (deptByRole[roleId] != departmentId) continue;
        ids.add(e.id);
      case KpiScope.personal:
        ids.add(e.id);
    }
  }
  ids.sort();
  return ids;
}
