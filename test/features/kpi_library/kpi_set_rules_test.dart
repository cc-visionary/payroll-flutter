import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_set_rules.dart';

void main() {
  KpiSetVerdict verdict(
    Set<String> selected, {
    Set<String> role = const {'a', 'b', 'c', 'd', 'e', 'f'},
    Set<String> measurable = const {'a', 'b', 'c', 'd', 'e', 'f'},
  }) => validateKpiSet(
    selectedKpiIds: selected,
    roleKpiIds: role,
    measurableKpiIds: measurable,
  );

  test('a set of 3 to 5 measurable role KPIs is clean', () {
    for (final s in [
      {'a', 'b', 'c'},
      {'a', 'b', 'c', 'd'},
      {'a', 'b', 'c', 'd', 'e'},
    ]) {
      final v = verdict(s);
      expect(v.blocked, isFalse, reason: '$s');
      expect(v.problems, isEmpty, reason: '$s');
      expect(v.warnings, isEmpty, reason: '$s');
    }
  });

  test('fewer than 3 or more than 5 warns but saves', () {
    final few = verdict({'a', 'b'});
    expect(few.blocked, isFalse);
    expect(few.warnings.single, contains('3'));

    final many = verdict({'a', 'b', 'c', 'd', 'e', 'f'});
    expect(many.blocked, isFalse);
    expect(many.warnings.single, contains('5'));
  });

  test('an empty set is blocked — it no longer means "all of them"', () {
    final v = verdict(const {});
    expect(v.blocked, isTrue);
    expect(v.problems.single, contains('at least one'));
  });

  test('an unmeasurable KPI is blocked from the set', () {
    final v = verdict({'a', 'b', 'c'}, measurable: {'a', 'b'});
    expect(v.blocked, isTrue);
    expect(v.problems.single, contains('not measurable'));
  });

  test('a KPI that is not on the role is blocked', () {
    // Can happen after the employee is moved to a different role card.
    final v = verdict({'a', 'z'}, role: {'a', 'b'}, measurable: {'a', 'z'});
    expect(v.blocked, isTrue);
    expect(v.problems.single, contains('not on this role'));
  });

  test('reports every problem at once rather than one per save', () {
    final v = verdict({'z'}, role: {'a'}, measurable: const {});
    expect(v.problems.length, 2);
    expect(v.blocked, isTrue);
  });

  test('employeeNeedsKpiSet flags only an empty set', () {
    expect(employeeNeedsKpiSet(const {}), isTrue);
    expect(employeeNeedsKpiSet({'a'}), isFalse);
  });
}
