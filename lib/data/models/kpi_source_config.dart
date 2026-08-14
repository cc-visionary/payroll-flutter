/// What a source row's `subjectKey` identifies.
///
/// Lives here, not under `features/`, for the same reason [KpiGoal] and
/// [KpiStatus] do: no model in this repo imports a feature. Task 3 extends
/// this file with the rest of an external source's configuration
/// (connection, query, column mapping); this enum is carved out first
/// because `source_rows.dart` needs it today.
enum SubjectKind {
  /// `subjectKey` is an employee-identifying value (an email, a Lark user
  /// ID, an external employee code) resolved through a caller-supplied
  /// `subjectToEmployee` map before it can be attributed anywhere.
  employee,

  /// `subjectKey` IS the department identifier already — no employee
  /// resolution step, and therefore no way to ever produce a personal
  /// figure from rows of this kind.
  department,

  /// There is no subject at all — the source answers a single company-wide
  /// figure, and `subjectKey` is ignored.
  none,
}
