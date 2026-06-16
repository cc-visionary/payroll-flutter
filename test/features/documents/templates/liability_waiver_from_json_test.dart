import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_template.dart';

void main() {
  final fullSample = LiabilityWaiverInputs(
    employeeId: 'EMP-001',
    employeeFullName: 'Juan Dela Cruz',
    employeeAddress: '456 Quezon City, Manila',
    companyId: 'CO-01',
    companyName: 'Luxium HQ',
    dateOfEmployment: DateTime(2023, 2, 1, 8, 0),
    outingDate: DateTime(2025, 8, 15),
    outingLocation: 'Tagaytay Highlands',
    dateSigned: DateTime(2025, 8, 1, 10, 30),
    signingPlace: 'Makati City',
  );

  final minimalSample = LiabilityWaiverInputs(
    employeeId: 'EMP-002',
    employeeFullName: 'Maria Clara',
    companyId: 'CO-02',
    companyName: 'GameCove',
    dateOfEmployment: null,
    outingDate: null,
    dateSigned: DateTime(2025, 9, 1),
  );

  test('round-trips toJson', () {
    expect(
      LiabilityWaiverInputs.fromJson(fullSample.toJson()).toJson(),
      fullSample.toJson(),
    );
  });

  test('round-trips toJson with null/empty fields', () {
    expect(
      LiabilityWaiverInputs.fromJson(minimalSample.toJson()).toJson(),
      minimalSample.toJson(),
    );
  });

  test('rebuilds blocks', () {
    expect(
      const LiabilityWaiverTemplate().build(
        LiabilityWaiverInputs.fromJson(fullSample.toJson()),
      ),
      isNotEmpty,
    );
  });
}
