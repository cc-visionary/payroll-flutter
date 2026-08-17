import '../../data/models/attendance_day.dart';
import '../../data/models/employee_review.dart';
import '../../data/models/kpi_result.dart' show KpiScope;
import 'configured_source.dart' show ConfiguredSource;

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
///
/// `null` means the caller could not be certified to see every review in the
/// company — `ReviewCycleRepository.allReviews()` returns `null` rather than
/// RLS's own silently narrowed self/direct-report subset when the caller's
/// role does not grant full-company visibility. [ReviewsCompletedOnTimeSource]
/// treats that the same as "cannot answer", never as "zero reviews due":
/// see its own `read` for why a partial count must not read as a real one.
typedef EmployeeReviewsReader = Future<List<EmployeeReview>?> Function();

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

    final reviews = await _listReviews();
    // A `null` reader result means the caller could not be certified to see
    // every review in the company (see EmployeeReviewsReader's doc comment).
    // Reporting NO_DATA here is the only honest answer -- a caller whose
    // visibility is narrowed to self/direct-report rows would otherwise
    // report a real-looking "due"/"completed" pair that is actually a slice
    // of the company, indistinguishable from a genuine number by anything
    // downstream of this source.
    if (reviews == null) return _noData;

    final population = employeeIds.toSet();
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
/// `app.employees.documentation_complete` were planned and then **dropped by
/// the owner on 2026-08-15**, not deferred. Each needed a business definition
/// that does not exist anywhere in this schema: nothing marks a job listing
/// critical and no target age is stored; `employees` holds no documentation
/// fields at all, only generated PDFs in `employee_documents`. Rather than
/// invent a threshold to make the table look complete, the owner removed both
/// KPIs. If either returns it arrives with its definition and, probably, a
/// migration — it is not a gap to quietly fill in.
/// Composes the two code sources above with [configured] -- Task 6's
/// `ConfiguredSource` instances, one per active `kpi_source_bindings` row
/// (Task 7 Part D wires this from `kpi_results_screen.dart`'s `_recompute`).
/// [configured] defaults to empty so every existing caller (and every test
/// in `automatic_sources_test.dart` written before this parameter existed)
/// keeps compiling unchanged.
///
/// **A collision throws instead of silently overwriting.** The two code
/// sources are keyed `app.attendance.present_days` /
/// `app.reviews.completed_on_time`; every configured source is keyed
/// `cfg:<kpiId>` (`configured_source.dart`'s `ConfiguredSource.key`) --
/// there is no way for a well-formed configured source to collide with a
/// code key by construction, but this function does not trust that
/// invariant blindly. It checks the registry key ALREADY built (code
/// sources first, then each configured source in turn) before inserting,
/// so any collision -- a code key somehow reused, or two configured
/// sources resolving to the same key (e.g. two rows a caller believed were
/// both "the one active binding" for the same KPI, which
/// `kpi_source_bindings_kpi_active`'s partial unique index prevents at the
/// database level but this in-memory function has no database in front of
/// it to enforce that for it) -- throws, naming the exact key that
/// collided, rather than letting the second source silently replace the
/// first. Per the plan: "a collision means something is wrong rather than
/// something to resolve quietly."
Map<String, KpiSource> buildSourceRegistry({
  required AttendanceRangeReader attendanceRangeReader,
  required EmployeeReviewsReader employeeReviewsReader,
  List<ConfiguredSource> configured = const [],
}) {
  final sources = <KpiSource>[
    AttendancePresentDaysSource(attendanceRangeReader),
    ReviewsCompletedOnTimeSource(employeeReviewsReader),
  ];
  final registry = <String, KpiSource>{
    for (final source in sources) source.key: source,
  };
  for (final source in configured) {
    if (registry.containsKey(source.key)) {
      throw StateError(
        'buildSourceRegistry: a configured source collides with an '
        'existing registry key "${source.key}" -- refusing to silently '
        'overwrite it. A collision means something is wrong (e.g. two '
        'active-looking bindings resolving to the same KPI), not '
        'something to resolve quietly.',
      );
    }
    registry[source.key] = source;
  }
  return registry;
}
