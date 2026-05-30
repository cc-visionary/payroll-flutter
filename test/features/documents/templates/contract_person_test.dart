import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/applicant.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/features/documents/templates/contract_person.dart';

void main() {
  test('ContractPerson.fromApplicant pulls identity from the applicant', () {
    final a = Applicant(
      id: 'a1',
      companyId: 'c1',
      firstName: 'Maria',
      lastName: 'Santos',
      email: 'maria@example.com',
      expectedSalaryMax: Decimal.parse('45000.00'),
      status: 'OFFER',
      statusChangedAt: DateTime.utc(2026, 5, 30),
      appliedAt: DateTime.utc(2026, 5, 25),
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 30),
    );
    final p = ContractPerson.fromApplicant(a);
    expect(p.fullName, 'Maria Santos');
    expect(p.salaryHint, Decimal.parse('45000.00'));
    expect(p.isApplicant, isTrue);
  });

  test('ContractPerson.fromEmployee pulls identity from the employee', () {
    final e = Employee(
      id: 'e1',
      companyId: 'c1',
      employeeNumber: 'EMP-001',
      firstName: 'Maria',
      lastName: 'Santos',
      employmentType: 'REGULAR',
      employmentStatus: 'ACTIVE',
      hireDate: DateTime.utc(2025, 1, 1),
      isRankAndFile: true,
      isOtEligible: true,
      isNdEligible: true,
      isHolidayPayEligible: true,
      taxOnFullEarnings: false,
    );
    final p = ContractPerson.fromEmployee(e);
    expect(p.fullName, 'Maria Santos');
    expect(p.isApplicant, isFalse);
  });
}
