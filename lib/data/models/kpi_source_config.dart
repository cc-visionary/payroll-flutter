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

/// Matches `kpi_source_bindings.subject_kind`'s CHECK constraint in
/// `20260815000002_kpi_source_config.sql`.
const _subjectKindCodes = {
  SubjectKind.employee: 'EMPLOYEE',
  SubjectKind.department: 'DEPARTMENT',
  SubjectKind.none: 'NONE',
};

String subjectKindCode(SubjectKind kind) => _subjectKindCodes[kind]!;

/// Throws rather than guessing: `subject_kind` is NOT NULL with a CHECK
/// constraint, so a real row can never carry anything else. The same
/// fail-loud rule `kpiScopeFromCode` (`kpi_result.dart`) applies to
/// `kpi_results.scope` for the same reason — an unrecognized value here
/// means the row and this model have drifted, and guessing a kind would
/// hide that instead of surfacing it.
SubjectKind subjectKindFromCode(String? code) => switch (code) {
  'EMPLOYEE' => SubjectKind.employee,
  'DEPARTMENT' => SubjectKind.department,
  'NONE' => SubjectKind.none,
  _ => throw ArgumentError(
    'unrecognized kpi_source_bindings.subject_kind: $code',
  ),
};

String? _blankToNull(String? v) =>
    (v == null || v.trim().isEmpty) ? null : v.trim();

/// A named external source system — Cashflow's Postgres, a sibling
/// Supabase project. Mirrors `kpi_connections`
/// (`20260815000002_kpi_source_config.sql`).
///
/// [credentialRef] names a secret; it never holds one. [credentialKind]
/// says which mechanism to resolve it through — see that migration's
/// header comment for the two paths (`VAULT` / `ENV`) and why the choice
/// was deferred to apply time rather than decided here.
class KpiConnection {
  /// Null for a freshly-built connection not yet written.
  final String? id;
  final String companyId;
  final String name;

  /// `POSTGRES` / `SUPABASE`.
  final String kind;
  final String host;
  final int port;
  final String database;
  final String dbSchema;

  /// `VAULT` / `ENV` — which mechanism [credentialRef] names a secret in.
  final String credentialKind;

  /// The secret's NAME, never its value.
  final String credentialRef;
  final bool isActive;

  const KpiConnection({
    this.id,
    required this.companyId,
    required this.name,
    required this.kind,
    required this.host,
    this.port = 5432,
    required this.database,
    this.dbSchema = 'public',
    required this.credentialKind,
    required this.credentialRef,
    this.isActive = true,
  });

  factory KpiConnection.fromRow(Map<String, dynamic> r) => KpiConnection(
    id: r['id'] as String?,
    companyId: r['company_id'] as String,
    name: r['name'] as String,
    kind: r['kind'] as String,
    host: r['host'] as String,
    port: (r['port'] as num?)?.toInt() ?? 5432,
    database: r['database'] as String,
    dbSchema: r['db_schema'] as String? ?? 'public',
    credentialKind: r['credential_kind'] as String,
    credentialRef: r['credential_ref'] as String,
    isActive: r['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toUpsertPayload() => {
    'id': id,
    'company_id': companyId,
    'name': name.trim(),
    'kind': kind,
    'host': host,
    'port': port,
    'database': database,
    'db_schema': dbSchema,
    'credential_kind': credentialKind,
    'credential_ref': credentialRef,
    'is_active': isActive,
  };
}

/// How one KPI reads from one connection: which table/view, and which of
/// its columns are the period, subject, numerator and denominator. Mirrors
/// `kpi_source_bindings` (`20260815000002_kpi_source_config.sql`).
///
/// [objectName] and the four `*Column` fields reach SQL in Task 5's edge
/// function — see `isValidSqlIdentifier`
/// (`lib/features/kpi_results/sql_identifier.dart`) for the shape they must
/// satisfy before that happens. This model does not itself validate them;
/// it is the round-trip, not the gate.
class KpiSourceBinding {
  /// Null for a freshly-built binding not yet written.
  final String? id;
  final String companyId;
  final String kpiId;
  final String connectionId;

  /// Table or view name in the source's schema.
  final String objectName;
  final String periodColumn;
  final String subjectColumn;
  final String numeratorColumn;

  /// Nullable — a COUNT KPI has no denominator. Must round-trip as null,
  /// never `''`: an empty string would fail the DB's identifier CHECK on
  /// write, and reads back as "a zero-length column name" rather than "no
  /// denominator" if it ever did.
  final String? denominatorColumn;
  final SubjectKind subjectKind;

  /// How the source writes a period, e.g. `YYYY-MM`.
  final String periodFormat;
  final bool isActive;

  const KpiSourceBinding({
    this.id,
    required this.companyId,
    required this.kpiId,
    required this.connectionId,
    required this.objectName,
    required this.periodColumn,
    required this.subjectColumn,
    required this.numeratorColumn,
    this.denominatorColumn,
    required this.subjectKind,
    this.periodFormat = 'YYYY-MM',
    this.isActive = true,
  });

  factory KpiSourceBinding.fromRow(Map<String, dynamic> r) =>
      KpiSourceBinding(
        id: r['id'] as String?,
        companyId: r['company_id'] as String,
        kpiId: r['kpi_id'] as String,
        connectionId: r['connection_id'] as String,
        objectName: r['object_name'] as String,
        periodColumn: r['period_column'] as String,
        subjectColumn: r['subject_column'] as String,
        numeratorColumn: r['numerator_column'] as String,
        denominatorColumn: _blankToNull(r['denominator_column'] as String?),
        subjectKind: subjectKindFromCode(r['subject_kind'] as String?),
        periodFormat: r['period_format'] as String? ?? 'YYYY-MM',
        isActive: r['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toUpsertPayload() => {
    'id': id,
    'company_id': companyId,
    'kpi_id': kpiId,
    'connection_id': connectionId,
    'object_name': objectName,
    'period_column': periodColumn,
    'subject_column': subjectColumn,
    'numerator_column': numeratorColumn,
    // _blankToNull, not a raw pass-through: a caller that built this from a
    // blank text field (a COUNT KPI's unused denominator input) must not
    // send '' where the DB — and the next fromRow — expects null.
    'denominator_column': _blankToNull(denominatorColumn),
    'subject_kind': subjectKindCode(subjectKind),
    'period_format': periodFormat,
    'is_active': isActive,
  };
}

/// One source's own key (a staff id, an email) resolved to this app's
/// employee or department, per connection. Mirrors `kpi_subject_map`
/// (`20260815000002_kpi_source_config.sql`), whose CHECK constraint
/// enforces exactly one of [employeeId] / [departmentId] is set — this
/// model carries both and trusts the DB to have enforced that rather than
/// re-validating it here.
class KpiSubjectMap {
  /// Null for a freshly-built row not yet written.
  final String? id;
  final String companyId;
  final String connectionId;
  final String externalKey;
  final String? employeeId;
  final String? departmentId;

  const KpiSubjectMap({
    this.id,
    required this.companyId,
    required this.connectionId,
    required this.externalKey,
    this.employeeId,
    this.departmentId,
  });

  factory KpiSubjectMap.fromRow(Map<String, dynamic> r) => KpiSubjectMap(
    id: r['id'] as String?,
    companyId: r['company_id'] as String,
    connectionId: r['connection_id'] as String,
    externalKey: r['external_key'] as String,
    employeeId: r['employee_id'] as String?,
    departmentId: r['department_id'] as String?,
  );

  Map<String, dynamic> toUpsertPayload() => {
    'id': id,
    'company_id': companyId,
    'connection_id': connectionId,
    'external_key': externalKey,
    'employee_id': employeeId,
    'department_id': departmentId,
  };
}
