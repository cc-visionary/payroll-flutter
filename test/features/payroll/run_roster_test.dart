import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/run_roster.dart';

Map<String, dynamic> _slip({
  required String gross,
  required String deductions,
  required String net,
}) => {
  'gross_pay': gross,
  'total_deductions': deductions,
  'net_pay': net,
};

void main() {
  group('effectiveRoster', () {
    test('materializes the full active list when the column is null', () {
      expect(
        effectiveRoster(included: null, allActiveIds: ['a', 'b', 'c']),
        ['a', 'b', 'c'],
      );
    });

    test('materializes the full active list when the column is empty', () {
      // An empty array reads back as "all active employees" — same as null.
      expect(
        effectiveRoster(included: const [], allActiveIds: ['a', 'b']),
        ['a', 'b'],
      );
    });

    test('keeps an explicit roster as-is', () {
      expect(
        effectiveRoster(included: ['b'], allActiveIds: ['a', 'b', 'c']),
        ['b'],
      );
    });

    test('drops ids that are no longer active from an explicit roster', () {
      // A scoped run that named an employee since archived must not resurrect
      // them just because we rewrote the column.
      expect(
        effectiveRoster(included: ['a', 'gone'], allActiveIds: ['a', 'b']),
        ['a'],
      );
    });

    test('de-duplicates', () {
      expect(
        effectiveRoster(included: ['a', 'a', 'b'], allActiveIds: ['a', 'b']),
        ['a', 'b'],
      );
    });
  });

  group('rosterAfterRemoval', () {
    test('subtracts the employee', () {
      expect(
        rosterAfterRemoval(roster: ['a', 'b', 'c'], employeeId: 'b'),
        ['a', 'c'],
      );
    });

    test('refuses to empty the roster', () {
      // Writing [] back would flip the run to the "all active employees"
      // catch-all and silently re-add everyone on the next recompute.
      expect(
        () => rosterAfterRemoval(roster: ['a'], employeeId: 'a'),
        throwsA(
          isA<RosterEditException>().having(
            (e) => e.message,
            'message',
            contains('last employee'),
          ),
        ),
      );
    });

    test('refuses an employee who is not on the roster', () {
      expect(
        () => rosterAfterRemoval(roster: ['a', 'b'], employeeId: 'z'),
        throwsA(isA<RosterEditException>()),
      );
    });
  });

  group('rosterAfterAdditions', () {
    test('appends the new ids', () {
      expect(
        rosterAfterAdditions(roster: ['a'], employeeIds: ['b', 'c']),
        ['a', 'b', 'c'],
      );
    });

    test('ignores ids already on the roster', () {
      expect(
        rosterAfterAdditions(roster: ['a', 'b'], employeeIds: ['b', 'c']),
        ['a', 'b', 'c'],
      );
    });

    test('refuses an empty addition', () {
      expect(
        () => rosterAfterAdditions(roster: ['a'], employeeIds: const []),
        throwsA(isA<RosterEditException>()),
      );
    });
  });

  group('isLarkFrozen', () {
    test('a payslip never sent to Lark is not frozen', () {
      expect(isLarkFrozen(null), isFalse);
    });

    test('every non-null status is frozen', () {
      // Mirrors PayrollComputeService: recall sets the column back to NULL,
      // so any value at all means the payslip is live in Lark.
      for (final s in ['PENDING', 'APPROVED', 'REJECTED', 'CANCELED']) {
        expect(isLarkFrozen(s), isTrue, reason: s);
      }
    });
  });

  group('sumTotals', () {
    test('adds up the remaining payslips', () {
      final t = sumTotals([
        _slip(gross: '4738.44', deductions: '1299.33', net: '3439.11'),
        _slip(gross: '5923.05', deductions: '2401.87', net: '3521.19'),
      ]);
      expect(t.gross, Decimal.parse('10661.49'));
      expect(t.deductions, Decimal.parse('3701.20'));
      expect(t.net, Decimal.parse('6960.30'));
      expect(t.count, 2);
    });

    test('an empty run zeroes out rather than leaving stale totals', () {
      final t = sumTotals(const []);
      expect(t.gross, Decimal.zero);
      expect(t.deductions, Decimal.zero);
      expect(t.net, Decimal.zero);
      expect(t.count, 0);
    });

    test('treats a null money column as zero', () {
      final t = sumTotals([
        {'gross_pay': null, 'total_deductions': '250', 'net_pay': '-250'},
      ]);
      expect(t.gross, Decimal.zero);
      expect(t.deductions, Decimal.parse('250'));
      expect(t.net, Decimal.parse('-250'));
    });
  });
}
