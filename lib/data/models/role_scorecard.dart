import 'package:decimal/decimal.dart';

class ResponsibilityArea {
  final String area;
  final List<String> tasks;
  const ResponsibilityArea({required this.area, required this.tasks});
  factory ResponsibilityArea.fromJson(Map<String, dynamic> j) =>
      ResponsibilityArea(
        area: j['area'] as String? ?? '',
        tasks:
            (j['tasks'] as List<dynamic>? ??
                    (j['task'] != null
                        ? <dynamic>[j['task']]
                        : const <dynamic>[]))
                .map((e) => e.toString())
                .toList(),
      );
  Map<String, dynamic> toJson() => {'area': area, 'tasks': tasks};
}

/// Rebuilds a card's ordered responsibility tree from its wp_tasks rows.
/// Areas order by their smallest `area_sort` (ties by name); tasks by `task_sort`.
/// Rows with no area or no name are not card responsibilities and are skipped.
List<ResponsibilityArea> responsibilitiesFromTaskRows(List<Map<String, dynamic>> rows) {
  final areaSort = <String, int>{};
  final byArea = <String, List<({int sort, String name})>>{};
  for (final r in rows) {
    final area = (r['responsibility_area'] as String?)?.trim() ?? '';
    final name = (r['name'] as String?)?.trim() ?? '';
    if (area.isEmpty || name.isEmpty) continue;
    final aSort = (r['area_sort'] as num?)?.toInt() ?? 0;
    final tSort = (r['task_sort'] as num?)?.toInt() ?? 0;
    final prev = areaSort[area];
    areaSort[area] = prev == null || aSort < prev ? aSort : prev;
    (byArea[area] ??= []).add((sort: tSort, name: name));
  }
  final areas = byArea.keys.toList()
    ..sort((a, b) {
      final c = areaSort[a]!.compareTo(areaSort[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final a in areas)
      ResponsibilityArea(
        area: a,
        tasks: (byArea[a]!..sort((x, y) => x.sort.compareTo(y.sort)))
            .map((e) => e.name)
            .toList(),
      ),
  ];
}

class KpiItem {
  final String name;
  final String measurement;
  final String target;
  final String frequency;

  const KpiItem({
    required this.name,
    required this.measurement,
    required this.target,
    required this.frequency,
  });

  /// Compatibility for employment-contract and legacy check-in consumers.
  String get metric => name;

  factory KpiItem.fromJson(Map<String, dynamic> j) => KpiItem(
    name: j['name'] as String? ?? j['metric'] as String? ?? '',
    measurement: j['measurement'] as String? ?? '',
    target: j['target'] as String? ?? '',
    frequency: j['frequency'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'measurement': measurement,
    'target': target,
    'frequency': frequency,
  };
}

class RequiredSkill {
  final String name;
  final String description;

  const RequiredSkill({required this.name, required this.description});

  factory RequiredSkill.fromJson(Map<String, dynamic> json) => RequiredSkill(
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'name': name, 'description': description};
}

class BehavioralExpectation {
  final String name;
  final String description;

  const BehavioralExpectation({required this.name, required this.description});

  factory BehavioralExpectation.fromJson(Map<String, dynamic> json) =>
      BehavioralExpectation(
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'description': description};
}

class RoleScorecard {
  final String id;
  final String companyId;
  final String jobTitle;
  final String? departmentId;
  final String missionStatement;
  final List<ResponsibilityArea> responsibilities;
  final List<KpiItem> kpis;
  final List<RequiredSkill> requiredSkills;
  final List<BehavioralExpectation> behavioralExpectations;
  final int version;
  final Decimal? salaryRangeMin;
  final Decimal? salaryRangeMax;
  final Decimal? baseSalary;
  final String wageType;
  final int workHoursPerDay;
  final String workDaysPerWeek;
  final bool isActive;
  final DateTime effectiveDate;
  final String? supersededById;
  final String? shiftTemplateId;
  final String? hiringEntityId;

  const RoleScorecard({
    required this.id,
    required this.companyId,
    required this.jobTitle,
    this.departmentId,
    required this.missionStatement,
    required this.responsibilities,
    required this.kpis,
    this.requiredSkills = const [],
    this.behavioralExpectations = const [],
    this.version = 1,
    this.salaryRangeMin,
    this.salaryRangeMax,
    this.baseSalary,
    required this.wageType,
    required this.workHoursPerDay,
    required this.workDaysPerWeek,
    required this.isActive,
    required this.effectiveDate,
    this.supersededById,
    this.shiftTemplateId,
    this.hiringEntityId,
  });

  factory RoleScorecard.fromRow(Map<String, dynamic> r) {
    final rawResp = r['key_responsibilities'];
    final rawKpis = r['kpis'];
    final rawSkills = r['required_skills'];
    final rawExpectations = r['behavioral_expectations'];
    final rawTasks = r['wp_tasks'];
    List<ResponsibilityArea> responsibilities;
    if (rawTasks is List) {
      // Authoritative source post-responsibility-unification: wp_tasks rows,
      // grouped/ordered by area_sort/task_sort (see responsibilitiesFromTaskRows).
      // The embed key is present (even as []) whenever it was requested — an
      // empty embed means "no responsibilities", NOT "fall back to the JSON
      // column" (PostgREST returns [] for a requested-but-empty embed, it does
      // not omit the key; a deleted-to-zero card must not resurrect stale JSON).
      responsibilities =
          responsibilitiesFromTaskRows(rawTasks.cast<Map<String, dynamic>>());
    } else if (rawResp is List) {
      // Legacy fallback: the JSON column, for pre-unification rows or any
      // select that doesn't embed wp_tasks.
      responsibilities = rawResp
          .cast<Map<String, dynamic>>()
          .map(ResponsibilityArea.fromJson)
          .toList();
    } else {
      responsibilities = const [];
    }
    List<KpiItem> kpis;
    final embeddedKpis = r['role_scorecard_kpis'];
    if (embeddedKpis is List) {
      // Authoritative source post-KPI-library migration: the link table,
      // ordered by sort_order. measurement comes from the library KPI.
      final links = embeddedKpis.whereType<Map>().toList()
        ..sort((a, b) =>
            (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
      kpis = [
        for (final link in links)
          KpiItem(
            name: (link['kpis'] as Map?)?['name'] as String? ?? '',
            measurement:
                (link['kpis'] as Map?)?['measurement_unit'] as String? ?? '',
            target: link['target'] as String? ?? '',
            frequency: link['frequency'] as String? ?? '',
          ),
      ];
    } else if (rawKpis is List) {
      // Back-compat: the upsert-return row and any pre-migration read.
      kpis = rawKpis.cast<Map<String, dynamic>>().map(KpiItem.fromJson).toList();
    } else {
      kpis = const [];
    }
    final requiredSkills = rawSkills is List
        ? rawSkills
              .whereType<Map>()
              .map(
                (item) =>
                    RequiredSkill.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const <RequiredSkill>[];
    final behavioralExpectations = rawExpectations is List
        ? rawExpectations
              .whereType<Map>()
              .map(
                (item) => BehavioralExpectation.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : const <BehavioralExpectation>[];
    Decimal? dec(Object? v) => v == null ? null : Decimal.parse(v.toString());
    return RoleScorecard(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      jobTitle: r['job_title'] as String,
      departmentId: r['department_id'] as String?,
      missionStatement: r['mission_statement'] as String? ?? '',
      responsibilities: responsibilities,
      kpis: kpis,
      requiredSkills: requiredSkills,
      behavioralExpectations: behavioralExpectations,
      version: (r['version'] as num?)?.toInt() ?? 1,
      salaryRangeMin: dec(r['salary_range_min']),
      salaryRangeMax: dec(r['salary_range_max']),
      baseSalary: dec(r['base_salary']),
      wageType: r['wage_type'] as String? ?? 'MONTHLY',
      workHoursPerDay: r['work_hours_per_day'] as int? ?? 8,
      workDaysPerWeek:
          r['work_days_per_week'] as String? ?? 'Monday to Saturday',
      isActive: r['is_active'] as bool? ?? true,
      effectiveDate: DateTime.parse(r['effective_date'] as String),
      supersededById: r['superseded_by_id'] as String?,
      shiftTemplateId: r['shift_template_id'] as String?,
      hiringEntityId: r['hiring_entity_id'] as String?,
    );
  }

  Map<String, dynamic> toUpsertPayload() => {
    'id': id,
    'company_id': companyId,
    'job_title': jobTitle,
    'department_id': departmentId,
    'mission_statement': missionStatement,
    // Responsibilities now live in wp_tasks (see 20260720000002). The column is
    // NOT NULL and kept read-only for rollback — write [] to satisfy it on
    // INSERT; omitting the key raises 23502.
    'key_responsibilities': const [],
    // The kpis JSON column is NOT NULL and kept as read-only legacy (KPIs now
    // live in role_scorecard_kpis). Write an empty array to satisfy the
    // constraint on INSERT; it is never read for display.
    'kpis': const <Map<String, dynamic>>[],
    'required_skills': requiredSkills.map((s) => s.toJson()).toList(),
    'behavioral_expectations': behavioralExpectations
        .map((e) => e.toJson())
        .toList(),
    'version': version,
    'salary_range_min': salaryRangeMin?.toString(),
    'salary_range_max': salaryRangeMax?.toString(),
    'base_salary': baseSalary?.toString(),
    'wage_type': wageType,
    'work_hours_per_day': workHoursPerDay,
    'work_days_per_week': workDaysPerWeek,
    'is_active': isActive,
    'effective_date': effectiveDate.toIso8601String().substring(0, 10),
    'hiring_entity_id': hiringEntityId,
  };
}
