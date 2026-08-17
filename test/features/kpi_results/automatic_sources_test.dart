import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/attendance_day.dart';
import 'package:payroll_flutter/data/models/employee_review.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/data/models/kpi_source_config.dart';
import 'package:payroll_flutter/features/kpi_results/automatic_sources.dart';
import 'package:payroll_flutter/features/kpi_results/configured_source.dart';

/// A minimal, never-actually-read [ConfiguredSource] -- every test in the
/// `buildSourceRegistry` group below asserts on registry SHAPE (which keys
/// map to which source), never on what `read()`/`readDetailed()` return, so
/// the fetcher and subject map reader are never invoked.
ConfiguredSource _configuredSource({
  required String kpiId,
  String bindingId = 'b-1',
}) => ConfiguredSource(
  binding: KpiSourceBinding(
    id: bindingId,
    companyId: 'c',
    kpiId: kpiId,
    connectionId: 'conn-1',
    objectName: 'daily_sales_fact',
    periodColumn: 'period',
    subjectColumn: 'staff_id',
    numeratorColumn: 'revenue',
    subjectKind: SubjectKind.none,
  ),
  subjectMapReader: (connectionId) async => const [],
  fetcher: ({required bindingId, required period}) async =>
      (statusCode: 200, body: {'rows': []}),
  employees: const [],
  roles: const [],
);

AttendanceDay _day({
  required String employeeId,
  required String date,
  required String status,
}) => AttendanceDay(
  id: 'a-$employeeId-$date',
  employeeId: employeeId,
  attendanceDate: DateTime.parse(date),
  dayType: 'WORKDAY',
  attendanceStatus: status,
  sourceType: 'MANUAL',
  earlyInApproved: false,
  lateOutApproved: false,
  lateInApproved: false,
  earlyOutApproved: false,
  isLocked: false,
);

EmployeeReview _review({
  required String employeeId,
  required String status,
  required String periodEnd,
  String? finalizedAt,
}) => EmployeeReview(
  id: 'r-$employeeId-$periodEnd',
  reviewCycleId: 'cycle-1',
  employeeId: employeeId,
  employeeNameSnapshot: 'Snapshot',
  responsibilityCardId: 'card-1',
  responsibilityCardVersion: 1,
  directManagerId: 'mgr-1',
  reviewType: 'MONTHLY_CHECK_IN',
  reviewPeriodStart: DateTime.parse(periodEnd).subtract(
    const Duration(days: 30),
  ),
  reviewPeriodEnd: DateTime.parse(periodEnd),
  status: status,
  responsibilitySnapshot: const [],
  finalizedAt: finalizedAt == null ? null : DateTime.parse(finalizedAt),
  createdAt: DateTime.parse(periodEnd),
  updatedAt: DateTime.parse(periodEnd),
);

void main() {
  group('AttendancePresentDaysSource', () {
    test('present days over scheduled days, ignoring rest days and holidays', () {
      final source = AttendancePresentDaysSource(
        ({required start, required end}) async => [
          _day(employeeId: 'e1', date: '2026-08-03', status: 'PRESENT'),
          _day(employeeId: 'e1', date: '2026-08-04', status: 'ABSENT'),
          _day(employeeId: 'e1', date: '2026-08-05', status: 'HALF_DAY'),
          _day(employeeId: 'e1', date: '2026-08-06', status: 'ON_LEAVE'),
          // Neither of these is a day the employee was expected to work, so
          // neither counts toward the denominator at all.
          _day(employeeId: 'e1', date: '2026-08-08', status: 'REST_DAY'),
          _day(employeeId: 'e1', date: '2026-08-09', status: 'HOLIDAY'),
        ],
      );

      return source
          .read(
            scope: KpiScope.personal,
            period: '2026-08',
            employeeIds: ['e1'],
          )
          .then((result) {
            // Scheduled: PRESENT, ABSENT, HALF_DAY, ON_LEAVE = 4. REST_DAY
            // and HOLIDAY are not days the employee was expected to show up.
            expect(result.denominator, 4);
            expect(result.numerator, 1);
          });
    });

    test('a period with no scheduled days is NO_DATA, not a perfect score', () async {
      // The tempting bug: zero rows -> 0/0 -> a "perfect" 100%. It must
      // instead be indistinguishable from "nobody has looked at this yet".
      final source = AttendancePresentDaysSource(
        ({required start, required end}) async => const [],
      );

      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e1'],
      );

      expect(result.numerator, isNull);
      expect(result.denominator, isNull);
    });

    test('rows outside the population are ignored, not just outnumbered', () async {
      final source = AttendancePresentDaysSource(
        ({required start, required end}) async => [
          _day(employeeId: 'e1', date: '2026-08-03', status: 'PRESENT'),
          // e2 is NOT in the population passed to read(). If this row leaked
          // in, denominator would be 2 and numerator 1 (50%) instead of a
          // clean 1/1 (100%) for e1 alone.
          _day(employeeId: 'e2', date: '2026-08-03', status: 'ABSENT'),
        ],
      );

      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e1'],
      );

      expect(result.numerator, 1);
      expect(result.denominator, 1);
    });

    test('an empty population reads nothing rather than falling back to everyone', () async {
      var called = false;
      final source = AttendancePresentDaysSource(
        ({required start, required end}) async {
          called = true;
          return [_day(employeeId: 'e1', date: '2026-08-03', status: 'PRESENT')];
        },
      );

      final result = await source.read(
        scope: KpiScope.department,
        period: '2026-08',
        employeeIds: const [],
      );

      expect(result, (numerator: null, denominator: null));
      expect(called, isFalse);
    });

    test('resolves the KPI period into the full calendar month', () async {
      DateTime? seenStart;
      DateTime? seenEnd;
      final source = AttendancePresentDaysSource(
        ({required start, required end}) async {
          seenStart = start;
          seenEnd = end;
          return const [];
        },
      );

      await source.read(
        scope: KpiScope.personal,
        period: '2026-02',
        employeeIds: ['e1'],
      );

      expect(seenStart, DateTime(2026, 2, 1));
      expect(seenEnd, DateTime(2026, 2, 28));
    });
  });

  group('ReviewsCompletedOnTimeSource', () {
    test('finalized by period end over reviews due', () async {
      final source = ReviewsCompletedOnTimeSource(
        () async => [
          _review(
            employeeId: 'e1',
            status: 'FINALIZED',
            periodEnd: '2026-08-31',
            finalizedAt: '2026-08-28',
          ),
          _review(
            employeeId: 'e1',
            status: 'READY_FOR_DISCUSSION',
            periodEnd: '2026-08-31',
          ),
          // A cancelled review was never going to be completed — it is not
          // owed, so it must not inflate the denominator.
          _review(
            employeeId: 'e1',
            status: 'CANCELLED',
            periodEnd: '2026-08-31',
          ),
        ],
      );

      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e1'],
      );

      expect(result.denominator, 2);
      expect(result.numerator, 1);
    });

    test('finalized AFTER the period end counts as due but not on time', () async {
      final source = ReviewsCompletedOnTimeSource(
        () async => [
          _review(
            employeeId: 'e1',
            status: 'FINALIZED',
            periodEnd: '2026-08-31',
            finalizedAt: '2026-09-04',
          ),
        ],
      );

      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e1'],
      );

      expect(result.denominator, 1);
      expect(result.numerator, 0);
    });

    test('finalized exactly ON the period end counts as on time', () async {
      // The boundary is inclusive, same convention as evaluateKpi's own
      // GTE/LTE boundaries.
      final source = ReviewsCompletedOnTimeSource(
        () async => [
          _review(
            employeeId: 'e1',
            status: 'FINALIZED',
            periodEnd: '2026-08-31',
            finalizedAt: '2026-08-31',
          ),
        ],
      );

      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e1'],
      );

      expect(result.numerator, 1);
    });

    test('no reviews due this period is NO_DATA, not a perfect score', () async {
      final source = ReviewsCompletedOnTimeSource(
        () async => [
          // Due in a different month entirely — must not count toward
          // 2026-08 at all, in either the numerator or the denominator.
          _review(
            employeeId: 'e1',
            status: 'FINALIZED',
            periodEnd: '2026-07-31',
            finalizedAt: '2026-07-30',
          ),
        ],
      );

      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e1'],
      );

      expect(result.numerator, isNull);
      expect(result.denominator, isNull);
    });

    test('rows outside the population are ignored, not just outnumbered', () async {
      final source = ReviewsCompletedOnTimeSource(
        () async => [
          _review(
            employeeId: 'e1',
            status: 'FINALIZED',
            periodEnd: '2026-08-31',
            finalizedAt: '2026-08-20',
          ),
          // e2 is outside the population. If this leaked in, denominator
          // would be 2 instead of a clean 1.
          _review(employeeId: 'e2', status: 'READY_FOR_DISCUSSION', periodEnd: '2026-08-31'),
        ],
      );

      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e1'],
      );

      expect(result.denominator, 1);
      expect(result.numerator, 1);
    });

    test('an empty population reads nothing rather than falling back to everyone', () async {
      var called = false;
      final source = ReviewsCompletedOnTimeSource(() async {
        called = true;
        return [];
      });

      final result = await source.read(
        scope: KpiScope.department,
        period: '2026-08',
        employeeIds: const [],
      );

      expect(result, (numerator: null, denominator: null));
      expect(called, isFalse);
    });

    test(
      'a caller that cannot be certified to see every review reports NO_DATA, not a partial count',
      () async {
        // Unlike the empty-population case above, the reader here IS
        // called (a non-empty population) and DOES return -- just `null`,
        // meaning ReviewCycleRepository.allReviews() could not certify the
        // caller sees the whole company's reviews (RLS would otherwise
        // silently narrow to self/direct-report rows). If the null check
        // in `read` were ever removed, this would not quietly pass with a
        // wrong number -- iterating a null list throws -- so the guard is
        // load-bearing, not decorative.
        var called = false;
        final source = ReviewsCompletedOnTimeSource(() async {
          called = true;
          return null;
        });

        final result = await source.read(
          scope: KpiScope.department,
          period: '2026-08',
          employeeIds: ['e1'],
        );

        expect(called, isTrue);
        expect(result, (numerator: null, denominator: null));
      },
    );
  });

  group('buildSourceRegistry', () {
    test('keys the two built-in sources by their source key, and nothing else', () {
      final registry = buildSourceRegistry(
        attendanceRangeReader: ({required start, required end}) async => [],
        employeeReviewsReader: () async => [],
      );

      expect(registry.keys.toSet(), {
        'app.attendance.present_days',
        'app.reviews.completed_on_time',
      });
      expect(registry['app.attendance.present_days'], isA<AttendancePresentDaysSource>());
      expect(registry['app.reviews.completed_on_time'], isA<ReviewsCompletedOnTimeSource>());
      // The two sources still pending their business definition must stay
      // absent rather than appear under a guessed behaviour.
      expect(registry.containsKey('app.hiring.critical_vacancy_aging'), isFalse);
      expect(registry.containsKey('app.employees.documentation_complete'), isFalse);
    });

    test('a configured source joins the map alongside the two code sources', () {
      final configured = _configuredSource(kpiId: 'kpi-1');
      final registry = buildSourceRegistry(
        attendanceRangeReader: ({required start, required end}) async => [],
        employeeReviewsReader: () async => [],
        configured: [configured],
      );

      expect(registry.keys.toSet(), {
        'app.attendance.present_days',
        'app.reviews.completed_on_time',
        'cfg:kpi-1',
      });
      expect(registry['cfg:kpi-1'], same(configured));
    });

    test(
      'two configured sources resolving to the same registry key collide and throw, naming the key',
      () {
        // `kpi_source_bindings_kpi_active` guarantees at most one ACTIVE
        // binding per KPI at the database level, but `buildSourceRegistry`
        // itself has no database in front of it -- it trusts whatever list
        // its caller hands it. Two bindings for the same kpiId reaching
        // this function (a caller bug, a stale cache, two "active-looking"
        // rows from two different reads) must not let the second one
        // silently win; it must be loud about exactly which key collided.
        final first = _configuredSource(kpiId: 'kpi-1', bindingId: 'b-1');
        final second = _configuredSource(kpiId: 'kpi-1', bindingId: 'b-2');

        expect(
          () => buildSourceRegistry(
            attendanceRangeReader: ({required start, required end}) async => [],
            employeeReviewsReader: () async => [],
            configured: [first, second],
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('cfg:kpi-1'),
            ),
          ),
        );
      },
    );
  });
}
