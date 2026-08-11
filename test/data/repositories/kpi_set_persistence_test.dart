import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

void main() {
  const role = ['a', 'b', 'c'];

  group('initialCheckedKpiIds', () {
    test('an absent set stays absent — it no longer means "all of them"', () {
      // The backfill in 20260811000002 gave everyone who had an effective set
      // an explicit one, so empty now means nobody has chosen.
      expect(initialCheckedKpiIds(const {}, role), isEmpty);
    });

    test('a stored set is shown exactly as stored', () {
      expect(initialCheckedKpiIds({'a', 'c'}, role), {'a', 'c'});
    });

    test('drops ids that are no longer on the role', () {
      // Survives an employee being moved to a different role card.
      expect(initialCheckedKpiIds({'a', 'z'}, role), {'a'});
    });

    test('a stored set that is entirely off-role reads as absent', () {
      expect(initialCheckedKpiIds({'y', 'z'}, role), isEmpty);
    });
  });

  group('kpiIdsToPersist', () {
    test('persists every checked id, including when all are checked', () {
      // The old rule collapsed this to [] and lost the distinction between
      // "tracks all three" and "nobody has chosen".
      expect(kpiIdsToPersist({'a', 'b', 'c'}, role), ['a', 'b', 'c']);
    });

    test('persists a partial selection in role order', () {
      expect(kpiIdsToPersist({'c', 'a'}, role), ['a', 'c']);
    });

    test('drops checked ids that are not on the role', () {
      expect(kpiIdsToPersist({'a', 'z'}, role), ['a']);
    });

    test('an empty selection persists as empty', () {
      expect(kpiIdsToPersist(const {}, role), isEmpty);
    });
  });
}
