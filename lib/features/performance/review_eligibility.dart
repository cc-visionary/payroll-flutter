import '../../data/models/employee.dart';

String? reviewEligibilityIssue(Employee employee) {
  if (employee.deletedAt != null || employee.employmentStatus != 'ACTIVE') {
    return 'Employee is not active';
  }
  if (employee.roleScorecardId == null) {
    return 'No Responsibility Card assigned';
  }
  if (employee.reportsToId == null) {
    return 'No direct manager assigned';
  }
  return null;
}
