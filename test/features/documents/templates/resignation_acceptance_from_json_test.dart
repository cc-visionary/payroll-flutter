import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_template.dart';

void main() {
  final fullSample = ResignationAcceptanceInputs(
    employeeId: 'EMP-001',
    employeeFullName: 'Juan Dela Cruz',
    employeePosition: 'Software Engineer',
    employeeGender: 'MALE',
    companyId: 'CO-01',
    companyName: 'Luxium HQ',
    companyAddress: '123 Makati Ave, Manila',
    hrManagerName: 'Brixter Santos',
    resignationDate: DateTime(2025, 4, 1, 8, 0),
    lastDayOfWork: DateTime(2025, 4, 30),
    issueDate: DateTime(2025, 4, 2, 16, 45),
    turnoverInstructions: 'Hand over laptop and access cards to IT.',
    includeClearanceMention: true,
    includeFinalPayMention: false,
  );

  final minimalSample = ResignationAcceptanceInputs(
    employeeId: 'EMP-002',
    employeeFullName: 'Maria Clara',
    companyId: 'CO-02',
    companyName: 'GameCove',
    resignationDate: DateTime(2025, 5, 1),
    lastDayOfWork: DateTime(2025, 5, 31),
    issueDate: DateTime(2025, 5, 2),
  );

  test('round-trips toJson', () {
    expect(
      ResignationAcceptanceInputs.fromJson(fullSample.toJson()).toJson(),
      fullSample.toJson(),
    );
  });

  test('round-trips toJson with default/empty fields', () {
    expect(
      ResignationAcceptanceInputs.fromJson(minimalSample.toJson()).toJson(),
      minimalSample.toJson(),
    );
  });

  test('rebuilds blocks', () {
    expect(
      const ResignationAcceptanceTemplate().build(
        ResignationAcceptanceInputs.fromJson(fullSample.toJson()),
      ),
      isNotEmpty,
    );
  });
}
