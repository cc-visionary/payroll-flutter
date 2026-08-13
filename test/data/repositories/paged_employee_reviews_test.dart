import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/review_cycle_repository.dart';

Map<String, dynamic> _row(String id, String periodEnd) => {
  'id': id,
  'review_cycle_id': 'cycle-1',
  'employee_id': 'e-$id',
  'employee_name_snapshot': 'Snapshot $id',
  'responsibility_card_id': 'card-1',
  'responsibility_card_version': 1,
  'direct_manager_id': 'mgr-1',
  'review_type': 'MONTHLY_CHECK_IN',
  'review_period_start': '2026-07-01',
  'review_period_end': periodEnd,
  'status': 'FINALIZED',
  'responsibility_snapshot': const [],
  'created_at': periodEnd,
  'updated_at': periodEnd,
};

/// Fake page source over a fixed list of raw rows — mirrors
/// `pagination_test.dart`'s `_FakeSource`, but yielding the
/// `employee_reviews` row shape [pagedEmployeeReviews] maps.
class _FakeReviewPages {
  _FakeReviewPages(this.rows);
  final List<Map<String, dynamic>> rows;
  final List<List<int>> ranges = [];

  Future<List<Map<String, dynamic>>> page(int from, int to) async {
    ranges.add([from, to]);
    if (from >= rows.length) return const [];
    final end = (to + 1) > rows.length ? rows.length : to + 1;
    return rows.sublist(from, end);
  }
}

void main() {
  test(
    'concatenates rows across more than one page, in the order fetched',
    () async {
      // pageSize defaults to 1000 inside fetchAllPages; 1200 rows forces a
      // second page, and the mapping must not drop or reorder anything the
      // walk collects.
      final rows = List.generate(
        1200,
        (i) => _row('r$i', '2026-0${(i % 9) + 1}-15'),
      );
      final source = _FakeReviewPages(rows);

      final reviews = await pagedEmployeeReviews(source.page);

      expect(reviews.length, 1200);
      expect(reviews.first.id, 'r0');
      expect(reviews.last.id, 'r1199');
      expect(source.ranges, [
        [0, 999],
        [1000, 1999],
      ]);
    },
  );

  test('a single short page still maps every row', () async {
    final source = _FakeReviewPages([_row('only', '2026-08-15')]);

    final reviews = await pagedEmployeeReviews(source.page);

    expect(reviews.length, 1);
    expect(reviews.single.id, 'only');
    expect(reviews.single.employeeId, 'e-only');
  });
}
