import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/coe_gates.dart';

void main() {
  test('blocks when status is ACTIVE and no separation event', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'ACTIVE',
    );
    expect(gates.length, 1);
    expect(gates.first.reason, contains('separation'));
  });

  test('allows when ACTIVE but a SEPARATION event exists', () {
    final gates = computeCoeGates(
      hasSeparationEvent: true,
      employmentStatus: 'ACTIVE',
    );
    expect(gates, isEmpty);
  });

  test('allows when status is RESIGNED', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'RESIGNED',
    );
    expect(gates, isEmpty);
  });

  test('allows when status is TERMINATED', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'TERMINATED',
    );
    expect(gates, isEmpty);
  });

  test('allows when status is END_OF_CONTRACT', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'END_OF_CONTRACT',
    );
    expect(gates, isEmpty);
  });

  test('allows when status is RETIRED', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'RETIRED',
    );
    expect(gates, isEmpty);
  });

  test('allows when status is AWOL', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'AWOL',
    );
    expect(gates, isEmpty);
  });

  test('allows when status is DECEASED', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'DECEASED',
    );
    expect(gates, isEmpty);
  });

  test('allows when both signals present (RESIGNED + event)', () {
    final gates = computeCoeGates(
      hasSeparationEvent: true,
      employmentStatus: 'RESIGNED',
    );
    expect(gates, isEmpty);
  });

  test('case-insensitive: lowercase active is still blocked', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'active',
    );
    expect(gates.length, 1);
  });
}
