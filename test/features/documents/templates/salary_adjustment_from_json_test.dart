import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_template.dart';

void main() {
  final fullSample = SalaryAdjustmentInputs(
    type: SalaryAdjustmentType.promotion,
    employeeId: 'EMP-001',
    employeeFullName: 'Juan Dela Cruz',
    employeePosition: 'Software Engineer',
    employeeGender: 'MALE',
    companyId: 'CO-01',
    companyName: 'Luxium HQ',
    companyAddress: '123 Makati Ave, Manila',
    hrManagerName: 'Brixter Santos',
    oldRoleScorecardId: 'SC-OLD-1',
    newRoleScorecardId: 'SC-NEW-2',
    oldPosition: 'Junior Engineer',
    newPosition: 'Senior Engineer',
    oldSalary: Decimal.parse('30000.00'),
    newSalary: Decimal.parse('45000.75'),
    salaryPeriod: 'MONTHLY',
    effectiveDate: DateTime(2025, 6, 1, 9, 0),
    issueDate: DateTime(2025, 5, 20, 12, 30),
    reason: 'Outstanding performance and increased responsibilities.',
  );

  final minimalSample = SalaryAdjustmentInputs(
    employeeId: 'EMP-002',
    employeeFullName: 'Maria Clara',
    companyId: 'CO-02',
    companyName: 'GameCove',
    oldRoleScorecardId: null,
    newRoleScorecardId: null,
    effectiveDate: DateTime(2025, 7, 1),
    issueDate: DateTime(2025, 6, 25),
  );

  test('round-trips toJson', () {
    expect(
      SalaryAdjustmentInputs.fromJson(fullSample.toJson()).toJson(),
      fullSample.toJson(),
    );
  });

  test('round-trips toJson with null/empty fields', () {
    expect(
      SalaryAdjustmentInputs.fromJson(minimalSample.toJson()).toJson(),
      minimalSample.toJson(),
    );
  });

  test('rebuilds blocks', () {
    expect(
      const SalaryAdjustmentTemplate().build(
        SalaryAdjustmentInputs.fromJson(fullSample.toJson()),
      ),
      isNotEmpty,
    );
  });
}
