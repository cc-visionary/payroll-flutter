import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/pagination.dart';

/// Fake page source over a fixed list. Records the (from, to) ranges it was
/// asked for so we can assert the loop walks them correctly.
class _FakeSource {
  final List<int> rows;
  final List<List<int>> ranges = [];
  _FakeSource(int count) : rows = List.generate(count, (i) => i);

  Future<List<int>> page(int from, int to) async {
    ranges.add([from, to]);
    if (from >= rows.length) return const [];
    final end = (to + 1) > rows.length ? rows.length : to + 1;
    return rows.sublist(from, end);
  }
}

void main() {
  group('fetchAllPages', () {
    test('single short page stops after one request', () async {
      final src = _FakeSource(3);
      final out = await fetchAllPages<int>(src.page, pageSize: 1000);
      expect(out.length, 3);
      expect(src.ranges, [
        [0, 999],
      ]);
    });

    test('empty result stops after one request', () async {
      final src = _FakeSource(0);
      final out = await fetchAllPages<int>(src.page, pageSize: 1000);
      expect(out, isEmpty);
      expect(src.ranges.length, 1);
    });

    test('walks past the 1000-row cap and returns every row', () async {
      final src = _FakeSource(2500);
      final out = await fetchAllPages<int>(src.page, pageSize: 1000);
      expect(out.length, 2500);
      expect(out.first, 0);
      expect(out.last, 2499);
      expect(src.ranges, [
        [0, 999],
        [1000, 1999],
        [2000, 2999],
      ]);
    });

    test('exact multiple of pageSize needs a trailing empty page', () async {
      final src = _FakeSource(2000);
      final out = await fetchAllPages<int>(src.page, pageSize: 1000);
      expect(out.length, 2000);
      // Full page at 1000-1999 is indistinguishable from "more to come",
      // so the loop must probe once more and get an empty page.
      expect(src.ranges, [
        [0, 999],
        [1000, 1999],
        [2000, 2999],
      ]);
    });

    test('respects a custom pageSize', () async {
      final src = _FakeSource(5);
      final out = await fetchAllPages<int>(src.page, pageSize: 2);
      expect(out.length, 5);
      expect(src.ranges, [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('maxPages guard prevents an infinite loop on a misbehaving source',
        () async {
      // A source that always returns a full page would loop forever.
      Future<List<int>> alwaysFull(int from, int to) async =>
          List.generate(to - from + 1, (i) => from + i);
      final out =
          await fetchAllPages<int>(alwaysFull, pageSize: 10, maxPages: 3);
      expect(out.length, 30);
    });
  });
}
