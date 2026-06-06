// test/features/hiring/listing_lifecycle_test.dart
//
// Narrative-style coverage of the slot-based listing model. The story:
//   1. Open a listing for 3 cashiers → status OPEN.
//   2. Hire 1, then 2, then 3 → fills up → status FILLED.
//   3. One employee resigns → filled drops to 2 → status auto-reopens to OPEN.
//   4. PAUSED / CLOSED overrides always win.
//   5. Overstaffed (filled > target) stays FILLED.
//
// All assertions go through `deriveEffectiveStatus` — the pure helper that
// powers `listingEffectiveStatusProvider`. The live provider's count query
// is exercised manually in the smoke test (Task 18).

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/job_listing_repository.dart';

void main() {
  group('listing lifecycle (slot-based)', () {
    test('opens when target > 0 and filled = 0', () {
      expect(
        deriveEffectiveStatus(status: 'OPEN', filled: 0, target: 3),
        ListingEffectiveStatus.open,
      );
    });

    test('fills as hires accumulate', () {
      expect(
        deriveEffectiveStatus(status: 'OPEN', filled: 1, target: 3),
        ListingEffectiveStatus.open,
      );
      expect(
        deriveEffectiveStatus(status: 'OPEN', filled: 2, target: 3),
        ListingEffectiveStatus.open,
      );
      expect(
        deriveEffectiveStatus(status: 'OPEN', filled: 3, target: 3),
        ListingEffectiveStatus.filled,
      );
    });

    test(
      'auto-reopens when an employee separates (filled drops below target)',
      () {
        // Listing was at 3/3 (FILLED) — one resigns → 2/3 → OPEN again.
        expect(
          deriveEffectiveStatus(status: 'OPEN', filled: 3, target: 3),
          ListingEffectiveStatus.filled,
        );
        expect(
          deriveEffectiveStatus(status: 'OPEN', filled: 2, target: 3),
          ListingEffectiveStatus.open,
        );
      },
    );

    test('PAUSED overrides slot math', () {
      expect(
        deriveEffectiveStatus(status: 'PAUSED', filled: 0, target: 3),
        ListingEffectiveStatus.paused,
      );
      expect(
        deriveEffectiveStatus(status: 'PAUSED', filled: 3, target: 3),
        ListingEffectiveStatus.paused,
      );
    });

    test('CLOSED overrides slot math', () {
      expect(
        deriveEffectiveStatus(status: 'CLOSED', filled: 0, target: 3),
        ListingEffectiveStatus.closed,
      );
      expect(
        deriveEffectiveStatus(status: 'CLOSED', filled: 3, target: 3),
        ListingEffectiveStatus.closed,
      );
    });

    test('exceeds target → still FILLED (overstaffed)', () {
      expect(
        deriveEffectiveStatus(status: 'OPEN', filled: 5, target: 3),
        ListingEffectiveStatus.filled,
      );
    });
  });
}
