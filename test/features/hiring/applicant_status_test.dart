import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/hiring/applicant_status.dart';

void main() {
  test('legal transitions are accepted', () {
    expect(canTransition(from: 'NEW', to: 'SCREENING'), isTrue);
    expect(canTransition(from: 'INTERVIEW', to: 'ASSESSMENT'), isTrue);
    expect(canTransition(from: 'INTERVIEW', to: 'OFFER'), isTrue);
    expect(canTransition(from: 'OFFER', to: 'OFFER_ACCEPTED'), isTrue);
    expect(canTransition(from: 'REJECTED', to: 'NEW'), isTrue); // re-engage
  });
  test('terminal HIRED is reachable only via OFFER_ACCEPTED', () {
    expect(canTransition(from: 'OFFER_ACCEPTED', to: 'HIRED'), isTrue);
    expect(canTransition(from: 'OFFER', to: 'HIRED'), isFalse);
    expect(canTransition(from: 'HIRED', to: 'NEW'), isFalse);
  });
  test('rejection/withdrawal are allowed from any pre-terminal state', () {
    expect(canTransition(from: 'NEW', to: 'REJECTED'), isTrue);
    expect(canTransition(from: 'OFFER_ACCEPTED', to: 'WITHDRAWN'), isTrue);
  });
  test('illegal jumps are blocked', () {
    expect(canTransition(from: 'NEW', to: 'OFFER'), isFalse);
    expect(canTransition(from: 'SCREENING', to: 'ASSESSMENT'), isFalse);
  });
  test('rejection reason is required iff target is REJECTED', () {
    expect(requiresReason(target: 'REJECTED'), 'rejection_reason');
    expect(requiresReason(target: 'WITHDRAWN'), 'withdrawal_reason');
    expect(requiresReason(target: 'OFFER'), isNull);
  });
}
