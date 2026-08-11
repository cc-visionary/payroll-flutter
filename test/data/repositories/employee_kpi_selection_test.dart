import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

void main() {
  group('initialCheckedKpiIds', () {
    test('no assignment -> nothing checked (nobody has chosen)', () {
      expect(initialCheckedKpiIds(<String>{}, ['a', 'b', 'c']), isEmpty);
    });
    test('with assignment -> only assigned that are on the role', () {
      expect(
        initialCheckedKpiIds({'a', 'z'}, ['a', 'b', 'c']),
        {'a'}, // 'z' not on the role is ignored
      );
    });
    test(
      'assignment with no on-role ids -> nothing checked (reads as absent)',
      () {
        expect(initialCheckedKpiIds({'z'}, ['a', 'b', 'c']), isEmpty);
      },
    );
  });

  group('kpiIdsToPersist', () {
    test('all role KPIs checked -> persist all (no longer collapsed)', () {
      expect(kpiIdsToPersist({'a', 'b', 'c'}, ['a', 'b', 'c']), [
        'a',
        'b',
        'c',
      ]);
    });
    test('a subset checked -> persist that subset', () {
      expect(kpiIdsToPersist({'a', 'c'}, ['a', 'b', 'c']), ['a', 'c']);
    });
    test('none checked -> persist none (falls back to default all)', () {
      expect(kpiIdsToPersist(<String>{}, ['a', 'b', 'c']), isEmpty);
    });
    test(
      'checked contains a stale off-role id -> persist only the on-role subset',
      () {
        expect(kpiIdsToPersist({'a', 'b', 'z'}, ['a', 'b', 'c']), ['a', 'b']);
      },
    );
    test('only off-role ids checked -> persist none (default all)', () {
      expect(kpiIdsToPersist({'x', 'y'}, ['a', 'b', 'c']), isEmpty);
    });
  });
}
