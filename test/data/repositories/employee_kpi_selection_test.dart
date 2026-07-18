import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

void main() {
  group('initialCheckedKpiIds', () {
    test('no assignment -> all role KPIs checked (default all)', () {
      expect(
        initialCheckedKpiIds(<String>{}, ['a', 'b', 'c']),
        {'a', 'b', 'c'},
      );
    });
    test('with assignment -> only assigned that are on the role', () {
      expect(
        initialCheckedKpiIds({'a', 'z'}, ['a', 'b', 'c']),
        {'a'}, // 'z' not on the role is ignored
      );
    });
    test('assignment with no on-role ids -> all checked (matches migration fallback)', () {
      expect(initialCheckedKpiIds({'z'}, ['a', 'b', 'c']), {'a', 'b', 'c'});
    });
  });

  group('kpiIdsToPersist', () {
    test('all role KPIs checked -> persist none (default all)', () {
      expect(kpiIdsToPersist({'a', 'b', 'c'}, ['a', 'b', 'c']), isEmpty);
    });
    test('a subset checked -> persist that subset', () {
      expect(kpiIdsToPersist({'a', 'c'}, ['a', 'b', 'c']), ['a', 'c']);
    });
    test('none checked -> persist none (falls back to default all)', () {
      expect(kpiIdsToPersist(<String>{}, ['a', 'b', 'c']), isEmpty);
    });
    test('checked contains a stale off-role id -> persist only the on-role subset', () {
      expect(kpiIdsToPersist({'a', 'b', 'z'}, ['a', 'b', 'c']), ['a', 'b']);
    });
    test('only off-role ids checked -> persist none (default all)', () {
      expect(kpiIdsToPersist({'x', 'y'}, ['a', 'b', 'c']), isEmpty);
    });
  });
}
