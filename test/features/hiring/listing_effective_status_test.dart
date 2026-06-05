import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/job_listing_repository.dart';

void main() {
  test('PAUSED status always wins regardless of filled count', () {
    expect(
      deriveEffectiveStatus(status: 'PAUSED', filled: 0, target: 3),
      ListingEffectiveStatus.paused,
    );
    expect(
      deriveEffectiveStatus(status: 'PAUSED', filled: 5, target: 3),
      ListingEffectiveStatus.paused,
    );
  });

  test('CLOSED status always wins regardless of filled count', () {
    expect(
      deriveEffectiveStatus(status: 'CLOSED', filled: 0, target: 3),
      ListingEffectiveStatus.closed,
    );
    expect(
      deriveEffectiveStatus(status: 'CLOSED', filled: 5, target: 3),
      ListingEffectiveStatus.closed,
    );
  });

  test('OPEN + filled >= target → FILLED', () {
    expect(
      deriveEffectiveStatus(status: 'OPEN', filled: 3, target: 3),
      ListingEffectiveStatus.filled,
    );
    expect(
      deriveEffectiveStatus(status: 'OPEN', filled: 5, target: 3),
      ListingEffectiveStatus.filled,
    );
  });

  test('OPEN + filled < target → OPEN', () {
    expect(
      deriveEffectiveStatus(status: 'OPEN', filled: 0, target: 3),
      ListingEffectiveStatus.open,
    );
    expect(
      deriveEffectiveStatus(status: 'OPEN', filled: 2, target: 3),
      ListingEffectiveStatus.open,
    );
  });
}
