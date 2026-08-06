import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/payroll_run.dart';
import 'package:payroll_flutter/features/payroll/runs/new/default_pay_period.dart';

PayrollRun _run({
  required String company,
  required String status,
  String? freq,
  required String end, // period_end (ISO date)
  required String payDate, // pay_date (ISO date, drives newest-first sort)
}) => PayrollRun.fromRow({
  'id': 'r-$company-$end',
  'company_id': company,
  'status': status,
  'period_end': end,
  'pay_date': payDate,
  'pay_frequency': freq,
  'created_at': '${payDate}T00:00:00Z',
});

void main() {
  group('defaultPayPeriod', () {
    final today = DateTime(2026, 7, 3);

    test(
      'with a last release: unpaid window (release+1 .. yesterday), pay today',
      () {
        final p = defaultPayPeriod(
          today: today,
          lastReleasedEnd: DateTime(2026, 6, 30),
        );
        expect(
          p.start,
          DateTime(2026, 7, 1),
        ); // day after the last released period end
        expect(
          p.end,
          DateTime(2026, 7, 2),
        ); // yesterday (last day with attendance)
        expect(p.payDate, DateTime(2026, 7, 3)); // today
      },
    );

    test('missed a cycle: spans the full unpaid gap (no cap)', () {
      final p = defaultPayPeriod(
        today: today,
        lastReleasedEnd: DateTime(2026, 5, 20),
      );
      expect(p.start, DateTime(2026, 5, 21));
      expect(p.end, DateTime(2026, 7, 2));
    });

    test('no last release: 15-day window ending yesterday, pay today', () {
      final p = defaultPayPeriod(today: today, lastReleasedEnd: null);
      expect(p.end, DateTime(2026, 7, 2)); // yesterday
      expect(
        p.start,
        DateTime(2026, 6, 18),
      ); // yesterday - 14 => 15-day inclusive window
      expect(p.payDate, DateTime(2026, 7, 3));
    });

    test(
      'already paid up (release end >= yesterday): falls back to 15-day window',
      () {
        final p = defaultPayPeriod(
          today: today,
          lastReleasedEnd: DateTime(2026, 7, 2),
        );
        expect(p.end, DateTime(2026, 7, 2));
        expect(
          p.start,
          DateTime(2026, 6, 18),
        ); // fallback, not 7/3 (start would be after end)
        expect(p.payDate, DateTime(2026, 7, 3));
      },
    );

    test('normalizes a today with a time component to date-only', () {
      final p = defaultPayPeriod(
        today: DateTime(2026, 7, 3, 14, 30),
        lastReleasedEnd: DateTime(2026, 6, 30, 9),
      );
      expect(p.start, DateTime(2026, 7, 1));
      expect(p.end, DateTime(2026, 7, 2));
      expect(p.payDate, DateTime(2026, 7, 3));
    });
  });

  group('lastReleasedPeriodEnd', () {
    test(
      'scopes to the company (ignores another company\'s newer release)',
      () {
        // Newest-first: company A released more recently than company B.
        final runs = [
          _run(
            company: 'A',
            status: 'RELEASED',
            freq: 'SEMI_MONTHLY',
            end: '2026-07-02',
            payDate: '2026-07-02',
          ),
          _run(
            company: 'B',
            status: 'RELEASED',
            freq: 'SEMI_MONTHLY',
            end: '2026-06-15',
            payDate: '2026-06-15',
          ),
        ];
        // For company B we must get B's end, NOT A's more-recent one.
        expect(
          lastReleasedPeriodEnd(
            runs,
            companyId: 'B',
            frequency: 'SEMI_MONTHLY',
          ),
          DateTime(2026, 6, 15),
        );
      },
    );

    test('prefers the same frequency, else falls back to any', () {
      final runs = [
        _run(
          company: 'A',
          status: 'RELEASED',
          freq: 'MONTHLY',
          end: '2026-07-01',
          payDate: '2026-07-05',
        ),
        _run(
          company: 'A',
          status: 'RELEASED',
          freq: 'SEMI_MONTHLY',
          end: '2026-06-15',
          payDate: '2026-06-20',
        ),
      ];
      // Same frequency wins even though MONTHLY is more recent.
      expect(
        lastReleasedPeriodEnd(runs, companyId: 'A', frequency: 'SEMI_MONTHLY'),
        DateTime(2026, 6, 15),
      );
      // No WEEKLY release → fall back to the most recent released of any freq.
      expect(
        lastReleasedPeriodEnd(runs, companyId: 'A', frequency: 'WEEKLY'),
        DateTime(2026, 7, 1),
      );
    });

    test(
      'ignores non-RELEASED runs; null when the company has no releases',
      () {
        final runs = [
          _run(
            company: 'A',
            status: 'DRAFT',
            freq: 'SEMI_MONTHLY',
            end: '2026-07-02',
            payDate: '2026-07-02',
          ),
          _run(
            company: 'A',
            status: 'RELEASED',
            freq: 'SEMI_MONTHLY',
            end: '2026-06-15',
            payDate: '2026-06-15',
          ),
        ];
        expect(
          lastReleasedPeriodEnd(
            runs,
            companyId: 'A',
            frequency: 'SEMI_MONTHLY',
          ),
          DateTime(2026, 6, 15), // ignores the newer DRAFT
        );
        expect(
          lastReleasedPeriodEnd(
            runs,
            companyId: 'Z',
            frequency: 'SEMI_MONTHLY',
          ),
          isNull, // no releases for company Z
        );
      },
    );
  });
}
