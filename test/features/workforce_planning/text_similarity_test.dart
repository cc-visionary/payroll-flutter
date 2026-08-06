import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/text_similarity.dart';

void main() {
  test(
    'normalizeName lowercases, strips punctuation, collapses whitespace',
    () {
      expect(
        normalizeName('  Pack, Label &  Dispatch!! '),
        'pack label dispatch',
      );
    },
  );

  test(
    'nameSimilarity is 1.0 for the same words in any order, 0 for disjoint',
    () {
      expect(
        nameSimilarity('pack and dispatch orders', 'dispatch orders and pack'),
        1.0,
      );
      expect(
        nameSimilarity('reconcile bank statements', 'design social ads'),
        0.0,
      );
    },
  );

  test('nameSimilarity is a fraction for partial overlap', () {
    // {pack, orders} vs {pack, orders, daily}: intersection 2, union 3
    expect(
      nameSimilarity('pack orders', 'pack orders daily'),
      closeTo(2 / 3, 1e-9),
    );
  });

  test('nameSimilarity handles empty names', () {
    expect(nameSimilarity('', ''), 1.0);
    expect(nameSimilarity('', 'anything'), 0.0);
    expect(nameSimilarity('anything', ''), 0.0);
  });

  test(
    'clusterBySimilarity groups names above the threshold, isolates the rest',
    () {
      final items = [
        'Pack orders',
        'Pack the orders',
        'Reconcile bank statements',
      ];
      final clusters = clusterBySimilarity<String>(
        items,
        (s) => s,
        threshold: 0.5,
      );
      // two packing names cluster; the finance one stands alone
      expect(clusters.length, 2);
      expect(clusters.firstWhere((c) => c.length == 2).toSet(), {
        'Pack orders',
        'Pack the orders',
      });
      expect(
        clusters.any(
          (c) => c.length == 1 && c.first == 'Reconcile bank statements',
        ),
        isTrue,
      );
    },
  );
}
