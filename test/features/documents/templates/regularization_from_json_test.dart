import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_template.dart';

void main() {
  final fullSample = RegularizationInputs(
    employeeId: 'EMP-001',
    employeeFullName: 'Juan Dela Cruz',
    employeePosition: 'Software Engineer',
    employeeGender: 'MALE',
    companyId: 'CO-01',
    companyName: 'Luxium HQ',
    companyAddress: '123 Makati Ave, Manila',
    hrManagerName: 'Brixter Santos',
    hireDate: DateTime(2024, 1, 15, 9, 30),
    regularizationDate: DateTime(2024, 7, 15),
    baseSalary: Decimal.parse('35000.50'),
    salaryPeriod: 'MONTHLY',
    issueDate: DateTime(2024, 7, 10, 14, 0),
    performanceSummary: 'Consistently exceeded expectations during probation.',
  );

  final minimalSample = RegularizationInputs(
    employeeId: 'EMP-002',
    employeeFullName: 'Maria Clara',
    companyId: 'CO-02',
    companyName: 'GameCove',
    hireDate: null,
    regularizationDate: DateTime(2025, 3, 1),
    issueDate: DateTime(2025, 2, 25),
  );

  test('round-trips toJson', () {
    expect(
      RegularizationInputs.fromJson(fullSample.toJson()).toJson(),
      fullSample.toJson(),
    );
  });

  test('round-trips toJson with null/empty fields', () {
    expect(
      RegularizationInputs.fromJson(minimalSample.toJson()).toJson(),
      minimalSample.toJson(),
    );
  });

  test('rebuilds blocks', () {
    expect(
      const RegularizationTemplate().build(
        RegularizationInputs.fromJson(fullSample.toJson()),
      ),
      isNotEmpty,
    );
  });
}
