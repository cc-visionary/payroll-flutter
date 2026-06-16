import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/nda_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nda_template.dart';

void main() {
  // Fully-populated sample: every field set, effectiveDate non-null.
  final fullSample = NdaInputs(
    employeeId: 'EMP-001',
    employeeFullName: 'Juan Dela Cruz',
    employeePosition: 'Sales Associate',
    employeeHomeAddress: '45 Mabini St, Makati, Metro Manila, 1200',
    companyId: 'CO-09',
    companyName: 'OgKilz',
    companyAddress: '123 Badminton St, Quezon City, Metro Manila, 1100',
    effectiveDate: DateTime(2026, 6, 16, 8, 0, 0),
    authorizedSignatoryName: 'Albert Tan',
    authorizedSignatoryRole: 'Brand Director',
  );

  // Nullable/empty sample: effectiveDate null, optional strings at defaults.
  final emptySample = NdaInputs(
    employeeId: 'EMP-002',
    employeeFullName: 'Pedro Penduko',
    companyId: 'CO-02',
    companyName: 'HAVIT',
    effectiveDate: null,
  );

  test('round-trips toJson', () {
    expect(
      NdaInputs.fromJson(fullSample.toJson()).toJson(),
      fullSample.toJson(),
    );
  });

  test('round-trips toJson with nullable/empty fields', () {
    expect(
      NdaInputs.fromJson(emptySample.toJson()).toJson(),
      emptySample.toJson(),
    );
  });

  test('rebuilds blocks', () {
    expect(
      const NdaTemplate().build(NdaInputs.fromJson(fullSample.toJson())),
      isNotEmpty,
    );
  });
}
