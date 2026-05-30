import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/hiring/applicant_status.dart';

void main() {
  test('validateTransition throws IllegalTransition on disallowed jump', () {
    expect(
      () => validateTransition(from: 'NEW', to: 'HIRED', reason: null),
      throwsA(isA<IllegalTransition>()),
    );
  });

  test('validateTransition throws when REJECTED move lacks rejection_reason', () {
    expect(
      () => validateTransition(from: 'NEW', to: 'REJECTED', reason: null),
      throwsA(isA<MissingReason>()),
    );
    expect(
      () => validateTransition(from: 'NEW', to: 'REJECTED', reason: '   '),
      throwsA(isA<MissingReason>()),
    );
  });

  test('validateTransition passes when REJECTED move has reason', () {
    expect(
      () => validateTransition(from: 'NEW', to: 'REJECTED', reason: 'Mismatched experience'),
      returnsNormally,
    );
  });

  test('validateTransition no-op when status unchanged', () {
    expect(() => validateTransition(from: 'OFFER', to: 'OFFER', reason: null), returnsNormally);
  });
}
