import '../../data/models/attendance_day.dart';
import '../../data/models/employee_review.dart';
import '../../data/models/kpi_result.dart' show KpiScope;

/// A source's raw answer for one KPI/period — the pair `evaluateKpi`
/// (`kpi_status.dart`) turns into a verdict.
///
/// Both fields null together means the source could not answer at all. That
/// is deliberately distinct from a real `(0, x)`: a source must never return
/// `(0, 0)` to mean "nothing to report" — `evaluateKpi` cannot tell that
/// apart from a genuine zero-over-zero, and Task 1's whole status rule
/// exists to keep "no judgement yet" from reading as a failure.
typedef KpiSourceInput = ({num? numerator, num? denominator});

/// One place the app can answer a KPI's numerator/denominator for itself,
/// with nobody typing a number in.
///
/// A source is registered under [key] in [buildSourceRegistry] — that key is
/// what a KPI's data method will eventually name (a Task 7 concern, not this
/// file's). [read] takes the population it must answer over ([employeeIds],
/// already resolved by `populationFor` in the caller — this file never
/// resolves scope on its own) and returns what it found, or [_noData] if it
/// could not answer.
abstract class KpiSource {
  String get key;

  Future<KpiSourceInput> read({
    required KpiScope scope,
    required String period,
    List<String> employeeIds = const [],
  });
}

/// No population, an unparsable period, or (for a given source) a real
/// population with zero qualifying rows. Every source funnels every
/// "cannot answer" case through this single constant so the same pair —
/// never `(0, 0)` — comes out no matter which branch found it.
const _noData = (numerator: null, denominator: null);

/// Parses a `YYYY-MM` KPI period into the first and last calendar day of
/// that month. Returns null for anything that doesn't parse cleanly — an
/// unparsable period answers nothing, same as an empty population.
({DateTime start, DateTime end})? _monthRange(String period) {
  final parts = period.split('-');
  if (parts.length != 2) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return null;
  // Day 0 of next month is the last day of this month — handles December's
  // year rollover for free via DateTime's own normalization.
  return (start: DateTime(year, month, 1), end: DateTime(year, month + 1, 0));
}

/// `YYYY-MM` for a [DateTime], matching the period vocabulary
/// `exception_aggregation.dart` uses for the exact same bucketing purpose.
String _period(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

/// Matches [AttendanceRepository.listByRange]'s signature closely enough
/// that production wiring can pass the bound method itself — Dart allows a
/// function with extra optional named parameters (`employeeId`,
/// `companyId`) to satisfy a narrower function type, so `repo.listByRange`
/// tears off cleanly here. Tests pass a plain function instead; neither
/// touches Supabase.
typedef AttendanceRangeReader =
    Future<List<AttendanceDay>> Function({
      required DateTime start,
      required DateTime end,
    });

/// `app.attendance.present_days` — present days over scheduled days.
///
/// A day is "scheduled" if the employee was expected to show up at all:
/// every `attendance_status` except `REST_DAY` and `HOLIDAY` — an unworked
/// holiday's status is `HOLIDAY`, while a worked one already reports
/// `PRESENT` (see `payslip_pdf.dart`'s day-type handling), so neither is a
/// day the employee needed to attend. `ABSENT`/`HALF_DAY`/`ON_LEAVE` all
/// count as scheduled-but-not-present, exactly as their names say. "Present"
/// is the literal `PRESENT` status, nothing softened or partially credited.
///
/// [AttendanceRepository.listByRange] already pages past PostgREST's
/// `max_rows` cap internally (`attendance_repository.dart:89`, via
/// `fetchAllPages`), so this source inherits that safety for free — no
/// separate pagination concern here.
class AttendancePresentDaysSource implements KpiSource {
  AttendancePresentDaysSource(this._listByRange);
  final AttendanceRangeReader _listByRange;

  @override
  String get key => 'app.attendance.present_days';

  @override
  Future<KpiSourceInput> read({
    required KpiScope scope,
    required String period,
    List<String> employeeIds = const [],
  }) async {
    // No population asked for means no answer — never fall back to reading
    // everyone, mirroring populationFor's own fail-safe direction.
    if (employeeIds.isEmpty) return _noData;
    final range = _monthRange(period);
    if (range == null) return _noData;

    final population = employeeIds.toSet();
    final rows = await _listByRange(start: range.start, end: range.end);

    num scheduled = 0;
    num present = 0;
    for (final row in rows) {
      if (!population.contains(row.employeeId)) continue;
      if (row.attendanceStatus == 'REST_DAY' ||
          row.attendanceStatus == 'HOLIDAY') {
        continue;
      }
      scheduled += 1;
      if (row.attendanceStatus == 'PRESENT') present += 1;
    }

    // Zero scheduled days is missing data, not a perfect score — the same
    // rule evaluateKpi enforces on the judgement side, applied here on the
    // input side before a verdict is ever formed.
    if (scheduled == 0) return _noData;
    return (numerator: present, denominator: scheduled);
  }
}

/// Every `employee_reviews` row visible to the caller, unfiltered by period
/// or employee — this source does that filtering itself, since it needs
/// `reviewPeriodEnd` (to bucket by period) and `finalizedAt` (to judge "on
/// time") on rows the underlying query has no reason to narrow by date.
/// Production wiring supplies this from whatever review repository method
/// reads the full table (paginated); tests pass a plain function. Neither
/// touches Supabase.
typedef EmployeeReviewsReader = Future<List<EmployeeReview>> Function();

/// `app.reviews.completed_on_time` — reviews finalized by their period end,
/// over reviews due.
///
/// "Due" is every non-`CANCELLED` review whose `reviewPeriodEnd` falls in
/// the KPI period — a cancelled review was never going to be completed, so
/// it is not counted as owed. "Completed on time" reuses this app's own
/// completion vocabulary (`review_completion_screen.dart`'s
/// `finalized = status == 'FINALIZED'`) rather than inventing a second
/// opinion, and additionally requires `finalizedAt` to land on or before the
/// period end — inclusive, same boundary convention as `evaluateKpi`'s own
/// GTE/LTE checks. A review finalized late is due, but not on time.
class ReviewsCompletedOnTimeSource implements KpiSource {
  ReviewsCompletedOnTimeSource(this._listReviews);
  final EmployeeReviewsReader _listReviews;

  @override
  String get key => 'app.reviews.completed_on_time';

  @override
  Future<KpiSourceInput> read({
    required KpiScope scope,
    required String period,
    List<String> employeeIds = const [],
  }) async {
    if (employeeIds.isEmpty) return _noData;

    final population = employeeIds.toSet();
    final reviews = await _listReviews();

    num due = 0;
    num completedOnTime = 0;
    for (final review in reviews) {
      if (!population.contains(review.employeeId)) continue;
      if (review.status == 'CANCELLED') continue;
      if (_period(review.reviewPeriodEnd) != period) continue;

      due += 1;
      if (review.status == 'FINALIZED' &&
          review.finalizedAt != null &&
          !review.finalizedAt!.isAfter(review.reviewPeriodEnd)) {
        completedOnTime += 1;
      }
    }

    // No reviews due this period is missing data, not a perfect 100% — the
    // same rule as an empty attendance period, applied to a differently
    // shaped source.
    if (due == 0) return _noData;
    return (numerator: completedOnTime, denominator: due);
  }
}

/// The live source registry. Adding a source later means adding an entry to
/// this list — never teaching a caller a new switch case, and never editing
/// any of the existing sources to make room for it.
///
/// `app.hiring.critical_vacancy_aging` and
/// `app.employees.documentation_complete` are deliberately absent. Both
/// depend on a business definition — what makes a vacancy "critical", what
/// counts as a "complete" employee record — that does not exist anywhere in
/// this schema today and is with the product owner, not this codebase. Their
/// absence here is a pending follow-up task, not an oversight: do not fill
/// either in without that decision landing first, and do not invent a
/// threshold to make the table look complete.
Map<String, KpiSource> buildSourceRegistry({
  required AttendanceRangeReader attendanceRangeReader,
  required EmployeeReviewsReader employeeReviewsReader,
}) {
  final sources = <KpiSource>[
    AttendancePresentDaysSource(attendanceRangeReader),
    ReviewsCompletedOnTimeSource(employeeReviewsReader),
  ];
  return {for (final source in sources) source.key: source};
}
