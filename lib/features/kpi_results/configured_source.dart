import '../../data/models/employee.dart';
import '../../data/models/kpi_result.dart' show KpiScope;
import '../../data/models/kpi_source_config.dart';
import '../../data/models/role_scorecard.dart';
import 'automatic_sources.dart' show KpiSource, KpiSourceInput;
import 'source_rows.dart';

/// Matches `KpiSourceConfigRepository.subjectMapFor`'s signature
/// (`kpi_source_config_repository.dart`) closely enough that production
/// wiring can pass the bound method itself -- `repo.subjectMapFor` tears
/// off cleanly here, the same technique `AttendanceRangeReader`
/// (automatic_sources.dart) uses for `AttendanceRepository.listByRange`.
/// Tests pass a plain function instead; neither touches Supabase.
typedef SubjectMapReader = Future<List<KpiSubjectMap>> Function(
  String connectionId,
);

/// One raw answer from the `fetch-kpi-source` edge function: the HTTP
/// status plus whatever the body decoded to. [body] is deliberately
/// `dynamic`, not `Map<String, dynamic>` -- [ConfiguredSource.read] must be
/// able to treat "the body isn't even a JSON object" as ordinary malformed
/// input rather than a type-cast crash, and a narrower type here would just
/// move that crash one line earlier.
typedef ConfiguredSourceFetchResult = ({int statusCode, dynamic body});

/// Calls `fetch-kpi-source` (Task 5) for [bindingId]/[period] and returns
/// its raw answer. Shaped to match `SupabaseClient.functions.invoke`
/// closely enough that production wiring adapts it in a few lines
/// (`res.status`, `res.data`, with a `FunctionException` caught and turned
/// into its own status/body pair) -- see this file's header comment for why
/// that adapter is NOT written here. Tests pass a plain function; neither
/// touches Supabase, and none of the tests in `configured_source_test.dart`
/// require a live edge function.
typedef ConfiguredSourceFetcher = Future<ConfiguredSourceFetchResult> Function({
  required String bindingId,
  required String period,
});

/// Everything one [ConfiguredSource.readDetailed] call found: the pair
/// [KpiSource.read] returns, plus the external `subject_key`s this call
/// could not map to an employee. [KpiSource.read] itself discards the keys
/// and returns the pair alone -- the interface's [KpiSourceInput] has no
/// room for them, and `computeResults` (compute_kpi_results.dart) has no
/// use for them either. Task 9's Settings surface is the one caller that
/// needs the ACTUAL KEYS, not just whether any exist (that is why this is a
/// keyed list, not the boolean `aggregateSourceRows` already exposes as
/// `unresolvedPresent`) -- it calls [readDetailed] directly, bypassing the
/// `KpiSource` interface entirely, the same way a caller that needs a
/// richer answer than an interface promises always does.
///
/// Empty on every failure path (the fetcher threw, a non-2xx, a malformed
/// body, a missing `rows` key) -- there is nothing to report as unresolved
/// when nothing was read at all.
typedef ConfiguredSourceResult = ({
  num? numerator,
  num? denominator,
  List<String> unresolvedSubjectKeys,
});

const _emptyResult = (
  numerator: null,
  denominator: null,
  unresolvedSubjectKeys: <String>[],
);

/// `value` if it is already a [num], `null` otherwise. Deliberately NOT a
/// parse: `num.tryParse('30')` would turn a numeric-looking string into a
/// real number, which is exactly the "coerce something plausible instead of
/// admitting the source sent the wrong shape" failure this whole plan
/// exists to rule out. A row whose `numerator`/`denominator` arrives as a
/// string, a bool, a list, or anything else that is not already a JSON
/// number has that ONE FIELD read as null -- not the row's other field, and
/// not the whole read -- matching `SourceRow`'s own doc comment that
/// numerator and denominator are independently nullable.
num? _numOrNull(dynamic value) => value is num ? value : null;

/// A [KpiSource] backed entirely by admin configuration -- Task 3's three
/// tables (`kpi_connections`, `kpi_source_bindings`, `kpi_subject_map`),
/// Task 5's edge function, and Task 1's [aggregateSourceRows], with nothing
/// compiled in beyond how to call each. Registered under
/// `'cfg:<bindingId>'` so a KPI's `numerator_source` (repurposed as a
/// registry key, per `compute_kpi_results.dart`'s decision 1) can name a
/// configured binding exactly the way it already names a compiled-in
/// source like `app.attendance.present_days`.
///
/// **`employeeToDepartment` is built here, once, from [employees]/[roles]
/// -- never from `Employee.departmentId`.** That column is a denormalised
/// copy the employee form writes at save time, so it goes stale the moment
/// a role moves to another department and its holders are not re-saved.
/// [_buildEmployeeToDepartment] resolves the department through the
/// EMPLOYEE'S ROLE instead, matching `populationFor`'s `deptByRole`
/// resolution (`kpi_population.dart`) rule for rule: same two-step lookup
/// (`employee.roleScorecardId` -> `role.departmentId`), same "no role, no
/// department" fallthrough, same authority given to the role over the
/// employee row. `kpi_population_test.dart`'s "a stale employees
/// .department_id does not win over the role" test pins exactly this rule
/// for [populationFor]; this class duplicates the two-line map-building
/// step rather than importing a helper from that file, because
/// `kpi_population.dart` exports no such map today and this task's file
/// list does not include changing it.
///
/// [employees] and [roles] are the full, in-memory company roster --
/// unlike [AttendanceRangeReader] (automatic_sources.dart), which reads a
/// period-dependent range lazily, this dependency does not vary by
/// `read()`'s arguments, so there is nothing to gain from an async reader
/// re-fetching it on every call. Task 7's registry construction already has
/// both lists in hand (`kpi_results_screen.dart`'s `_recompute` loads them
/// before building `buildSourceRegistry`'s input) by the time it builds one
/// `ConfiguredSource` per active binding.
class ConfiguredSource implements KpiSource {
  ConfiguredSource({
    required this.binding,
    required SubjectMapReader subjectMapReader,
    required ConfiguredSourceFetcher fetcher,
    required List<Employee> employees,
    required List<RoleScorecard> roles,
  }) : bindingId =
           binding.id ??
           (throw ArgumentError(
             'ConfiguredSource requires a persisted binding (binding.id is null)',
           )),
       _subjectMapReader = subjectMapReader,
       _fetcher = fetcher,
       _employeeToDepartment = _buildEmployeeToDepartment(employees, roles);

  final KpiSourceBinding binding;
  final String bindingId;
  final SubjectMapReader _subjectMapReader;
  final ConfiguredSourceFetcher _fetcher;
  final Map<String, String> _employeeToDepartment;

  @override
  String get key => 'cfg:$bindingId';

  @override
  Future<KpiSourceInput> read({
    required KpiScope scope,
    required String period,
    List<String> employeeIds = const [],
  }) async {
    final result = await readDetailed(
      scope: scope,
      period: period,
      employeeIds: employeeIds,
    );
    return (numerator: result.numerator, denominator: result.denominator);
  }

  /// The full answer, including the unresolved `subject_key`s -- see
  /// [ConfiguredSourceResult]'s doc comment for who calls this directly and
  /// why. [read] is a thin wrapper over this that keeps only the pair the
  /// `KpiSource` interface promises.
  ///
  /// EVERY FAILURE BECOMES [_emptyResult] -- the fetcher throwing, a
  /// non-2xx status, a body that is not a JSON object, a body with no
  /// `rows` list. Never a partial number and never a zero:
  /// `computeResults` (compute_kpi_results.dart) turns a null numerator
  /// into `NO_DATA`/`MISSING_SOURCE`, which is the honest answer for "the
  /// source could not be read", and a zero would instead read as a real,
  /// confidently wrong measurement.
  Future<ConfiguredSourceResult> readDetailed({
    required KpiScope scope,
    required String period,
    List<String> employeeIds = const [],
  }) async {
    final ConfiguredSourceFetchResult fetched;
    try {
      fetched = await _fetcher(bindingId: bindingId, period: period);
    } catch (_) {
      // Network blip, edge function outage, an unexpected throw out of a
      // fake fetcher in a test -- contained here, same as
      // `compute_kpi_results.dart`'s own `_readSource` contains a whole
      // `KpiSource.read` throw. This function has its own guard too,
      // because the brief requires this exact branch tested in isolation,
      // not merely relied upon via the caller's safety net.
      return _emptyResult;
    }

    // Non-2xx: the function's own contract (`fetch-kpi-source/index.ts`'s
    // header comment) is "rows, or a non-2xx" -- never a 200 carrying an
    // error. A caller-side auth failure, a missing binding, an unreachable
    // source all surface as a status outside 200-299 with no rows to trust.
    if (fetched.statusCode < 200 || fetched.statusCode > 299) {
      return _emptyResult;
    }

    final body = fetched.body;
    // Malformed body: not even a JSON object (a raw string, null, a list,
    // ...). Distinct from the next check -- a well-formed object that is
    // simply missing `rows` -- because both are real, independently
    // reachable shapes a broken fetcher or a drifted edge function could
    // produce, and the brief tests them as two separate branches.
    if (body is! Map) {
      return _emptyResult;
    }
    final rawRows = body['rows'];
    if (rawRows is! List) {
      return _emptyResult;
    }

    // Row-level parsing never throws: a row that is not even a JSON object,
    // or whose `subject_key` is not a string, contributes nothing rather
    // than aborting every other row's contribution. A row whose
    // `numerator`/`denominator` is the wrong type keeps its `subject_key`
    // (so it can still be counted as "this subject happened, but we don't
    // know its number") with that one field read as null -- see
    // [_numOrNull].
    final rows = <SourceRow>[
      for (final rawRow in rawRows)
        if (rawRow is Map && rawRow['subject_key'] is String)
          SourceRow(
            subjectKey: rawRow['subject_key'] as String,
            numerator: _numOrNull(rawRow['numerator']),
            denominator: _numOrNull(rawRow['denominator']),
          ),
    ];

    // Only an EMPLOYEE-kind binding has an identity to resolve at all --
    // DEPARTMENT rows already ARE a department id, and NONE rows have no
    // subject. Skipping the subject-map read for those two kinds avoids a
    // pointless repository round trip on every single read.
    final subjectMap = binding.subjectKind == SubjectKind.employee
        ? await _subjectMapReader(binding.connectionId)
        : const <KpiSubjectMap>[];
    final subjectToEmployee = <String, String>{
      for (final m in subjectMap)
        if (m.employeeId != null) m.externalKey: m.employeeId!,
    };

    // aggregateSourceRows wants a single employeeId/departmentId, not the
    // population list `read`'s own [employeeIds] carries -- derive it from
    // that population the same way `computeResults` built it in the first
    // place: PERSONAL's population is exactly one holder
    // (`populationFor`'s personal branch), and DEPARTMENT's population is
    // every holder of ONE department (`populationFor`'s department
    // branch), so any one member's resolved department names the whole
    // population's department. An empty population resolves to null either
    // way -- no employeeId/departmentId to filter by, which
    // `aggregateSourceRows` already reads as "nobody asked for", not
    // "everybody".
    String? employeeId;
    String? departmentId;
    switch (scope) {
      case KpiScope.personal:
        employeeId = employeeIds.isEmpty ? null : employeeIds.first;
      case KpiScope.department:
        departmentId = employeeIds.isEmpty
            ? null
            : _employeeToDepartment[employeeIds.first];
      case KpiScope.company:
        break;
    }

    final aggregate = aggregateSourceRows(
      rows: rows,
      scope: scope,
      subjectKind: binding.subjectKind,
      subjectToEmployee: subjectToEmployee,
      employeeToDepartment: _employeeToDepartment,
      employeeId: employeeId,
      departmentId: departmentId,
    );

    final unresolved = <String>{};
    if (binding.subjectKind == SubjectKind.employee) {
      for (final row in rows) {
        if (!subjectToEmployee.containsKey(row.subjectKey)) {
          unresolved.add(row.subjectKey);
        }
      }
    }

    return (
      numerator: aggregate.numerator,
      denominator: aggregate.denominator,
      unresolvedSubjectKeys: unresolved.toList()..sort(),
    );
  }
}

/// employeeId -> departmentId, resolved through each employee's ROLE. See
/// [ConfiguredSource]'s own doc comment for why this duplicates
/// `populationFor`'s `deptByRole` rule instead of reading
/// `Employee.departmentId` directly.
Map<String, String> _buildEmployeeToDepartment(
  List<Employee> employees,
  List<RoleScorecard> roles,
) {
  final deptByRole = {for (final r in roles) r.id: r.departmentId};
  final map = <String, String>{};
  for (final e in employees) {
    final roleId = e.roleScorecardId;
    if (roleId == null) continue;
    final deptId = deptByRole[roleId];
    if (deptId == null) continue;
    map[e.id] = deptId;
  }
  return map;
}
