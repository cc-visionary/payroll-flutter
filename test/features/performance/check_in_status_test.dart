import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/performance/check_in_status.dart';

void main() {
  test('legal transitions are accepted', () {
    expect(canCheckInTransition(from: 'DRAFT', to: 'SUBMITTED'), isTrue);
    expect(canCheckInTransition(from: 'SUBMITTED', to: 'UNDER_REVIEW'), isTrue);
    expect(canCheckInTransition(from: 'UNDER_REVIEW', to: 'COMPLETED'), isTrue);
  });
  test('SKIPPED is reachable from any non-terminal state', () {
    expect(canCheckInTransition(from: 'DRAFT', to: 'SKIPPED'), isTrue);
    expect(canCheckInTransition(from: 'SUBMITTED', to: 'SKIPPED'), isTrue);
    expect(canCheckInTransition(from: 'UNDER_REVIEW', to: 'SKIPPED'), isTrue);
  });
  test('terminal states cannot transition', () {
    expect(canCheckInTransition(from: 'COMPLETED', to: 'DRAFT'), isFalse);
    expect(canCheckInTransition(from: 'SKIPPED', to: 'DRAFT'), isFalse);
  });
  test('illegal jumps are blocked', () {
    expect(canCheckInTransition(from: 'DRAFT', to: 'COMPLETED'), isFalse);
    expect(canCheckInTransition(from: 'DRAFT', to: 'UNDER_REVIEW'), isFalse);
  });
  test('validateCheckInTransition throws on illegal jump', () {
    expect(
      () => validateCheckInTransition(from: 'DRAFT', to: 'COMPLETED'),
      throwsA(isA<IllegalCheckInTransition>()),
    );
  });
}
