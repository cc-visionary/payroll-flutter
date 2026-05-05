import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/coe_gates.dart';

void main() {
  test('blocks when no SEPARATION event AND status != SEPARATED', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'ACTIVE',
    );
    expect(gates.length, 1);
    expect(gates.first.reason, contains('separation'));
  });

  test('allows when SEPARATION event exists', () {
    final gates = computeCoeGates(
      hasSeparationEvent: true,
      employmentStatus: 'ACTIVE',
    );
    expect(gates, isEmpty);
  });

  test('allows when status is SEPARATED even without event', () {
    final gates = computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: 'SEPARATED',
    );
    expect(gates, isEmpty);
  });

  test('allows when both', () {
    final gates = computeCoeGates(
      hasSeparationEvent: true,
      employmentStatus: 'SEPARATED',
    );
    expect(gates, isEmpty);
  });
}
