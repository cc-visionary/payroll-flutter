import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/features/performance/review_eligibility.dart';

Employee employee({
  String status = 'ACTIVE',
  String? roleCard = 'card-1',
  String? manager = 'manager-1',
}) => Employee(
  id: 'employee-1',
  companyId: 'company-1',
  employeeNumber: 'E001',
  firstName: 'Maria',
  lastName: 'Santos',
  roleScorecardId: roleCard,
  reportsToId: manager,
  employmentType: 'REGULAR',
  employmentStatus: status,
  hireDate: DateTime(2025),
  isRankAndFile: true,
  isOtEligible: true,
  isNdEligible: true,
  isHolidayPayEligible: true,
  taxOnFullEarnings: false,
);

void main() {
  test('active employee with card and manager is eligible', () {
    expect(reviewEligibilityIssue(employee()), isNull);
  });

  test('missing Responsibility Card is explained', () {
    expect(
      reviewEligibilityIssue(employee(roleCard: null)),
      'No Responsibility Card assigned',
    );
  });

  test('missing manager is explained', () {
    expect(
      reviewEligibilityIssue(employee(manager: null)),
      'No direct manager assigned',
    );
  });
}
