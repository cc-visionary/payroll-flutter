import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/coe_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/coe_template.dart';

void main() {
  // Sample with every nullable/optional field set to a non-null value.
  final fullSample = CoeInputs(
    employeeId: 'EMP-001',
    employeeFullName: 'Juan Dela Cruz',
    employeeLastName: 'Dela Cruz',
    employeeHonorific: 'Mr.',
    companyId: 'CO-100',
    companyName: 'Luxium HQ',
    companyAddress: '123 Makati Ave, Makati City',
    hrManagerName: 'Maria Santos',
    position: 'Software Engineer',
    place: 'Makati City',
    dateStart: DateTime.parse('2022-01-15T00:00:00.000'),
    dateEnd: DateTime.parse('2024-06-30T00:00:00.000'),
    dateIssued: DateTime.parse('2024-07-01T09:30:00.000'),
  );

  // Sample exercising defaults / null values for nullable + defaulted fields.
  final minimalSample = CoeInputs(
    employeeId: 'EMP-002',
    employeeFullName: 'Anna Reyes',
    companyId: 'CO-200',
    companyName: 'GameCove',
    position: 'Brand Handler',
    dateIssued: DateTime.parse('2025-03-10T08:00:00.000'),
    // employeeLastName, employeeHonorific, place => default ''
    // companyAddress, hrManagerName, dateStart, dateEnd => null
  );

  test('round-trips toJson (all fields populated)', () {
    expect(
      CoeInputs.fromJson(fullSample.toJson()).toJson(),
      fullSample.toJson(),
    );
  });

  test('round-trips toJson (nullable/empty fields)', () {
    expect(
      CoeInputs.fromJson(minimalSample.toJson()).toJson(),
      minimalSample.toJson(),
    );
  });

  test('rebuilds blocks', () {
    expect(
      const CoeTemplate().build(CoeInputs.fromJson(fullSample.toJson())),
      isNotEmpty,
    );
    expect(
      const CoeTemplate().build(CoeInputs.fromJson(minimalSample.toJson())),
      isNotEmpty,
    );
  });
}
