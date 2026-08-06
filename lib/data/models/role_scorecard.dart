import 'package:decimal/decimal.dart';

import 'workforce_planning.dart';

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
/// Areas order by their smallest `area_sort` (ties by name); tasks by
/// `task_sort`, tied-broken by `id` (Dart's `List.sort` is not stable, so two
/// rows sharing a `task_sort` — e.g. two areas typed with the same name that
/// merge into one bucket on reload — would otherwise render in a
/// non-deterministic order between builds, shifting PDF/contract order;
/// mirrors the same tie-break in tasks_rows.dart's `_groupByArea`).
/// Rows with no area or no name are not card responsibilities and are skipped.
List<ResponsibilityArea> responsibilitiesFromTaskRows(
  List<Map<String, dynamic>> rows,
) {
  final areaSort = <String, int>{};
  final byArea = <String, List<({int sort, String name, String id})>>{};
  for (final r in rows) {
    final area = (r['responsibility_area'] as String?)?.trim() ?? '';
    final name = (r['name'] as String?)?.trim() ?? '';
    if (area.isEmpty || name.isEmpty) continue;
    if ((r['status'] as String?) == 'ARCHIVED')
      continue; // archived leaves the card's derived list
    final aSort = (r['area_sort'] as num?)?.toInt() ?? 0;
    final tSort = (r['task_sort'] as num?)?.toInt() ?? 0;
    final id = (r['id'] as String?) ?? '';
    final prev = areaSort[area];
    areaSort[area] = prev == null || aSort < prev ? aSort : prev;
    (byArea[area] ??= []).add((sort: tSort, name: name, id: id));
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
        tasks:
            (byArea[a]!..sort((x, y) {
                  final c = x.sort.compareTo(y.sort);
                  return c != 0 ? c : x.id.compareTo(y.id);
                }))
                .map((e) => e.name)
                .toList(),
      ),
  ];
}

/// The accountabilities SHARED to [cardId] (via a wp_task_assignments row
/// targeting it) that this card did NOT itself author. [assignedToCard] is
/// `assignedTasksByCard()[cardId]` — every ACTIVE task with an assignment
/// pointing at this card, including tasks the card authors itself (e.g. the
/// PRIMARY self-assignment wired in createDraftRoleFromTasks). A task whose
/// own `role_scorecard_id` (its author/owner) already equals [cardId] is
/// skipped here — it's already counted via the wp_tasks embed that builds
/// the card's authored `responsibilities` (see responsibilitiesFromTaskRows),
/// so including it again would duplicate it.
///
/// Grouped and ordered the same way responsibilitiesFromTaskRows orders
/// authored rows (area by min area_sort, ties by name; tasks by task_sort,
/// ties by id) — but as a wholly separate list of areas, NEVER merged into
/// an authored area of the same name. Callers must APPEND this after the
/// card's authored responsibilities, never interleave: a shared row must not
/// reorder, reword, or otherwise alter the authored output (Risk #2 — this
/// list feeds the role-card PDF and the employment contract's Annex A).
/// A task with no `responsibility_area` lands in the [fallbackArea] bucket
/// ("Shared" by default; the contract's owned-task append passes
/// "Additional Responsibilities").
List<ResponsibilityArea> responsibilitiesFromAssignedTasks(
  String cardId,
  List<WpTask> assignedToCard, {
  String fallbackArea = 'Shared',
}) {
  final areaSort = <String, int>{};
  final byArea = <String, List<({int sort, String name, String id})>>{};
  for (final t in assignedToCard) {
    if (t.roleScorecardId == cardId)
      continue; // authored here already — not a share
    final name = t.name.trim();
    if (name.isEmpty) continue;
    final rawArea = t.responsibilityArea?.trim() ?? '';
    final area = rawArea.isEmpty ? fallbackArea : rawArea;
    final prev = areaSort[area];
    areaSort[area] = prev == null || t.areaSort < prev ? t.areaSort : prev;
    (byArea[area] ??= []).add((sort: t.taskSort, name: name, id: t.id));
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
        tasks:
            (byArea[a]!..sort((x, y) {
                  final c = x.sort.compareTo(y.sort);
                  return c != 0 ? c : x.id.compareTo(y.id);
                }))
                .map((e) => e.name)
                .toList(),
      ),
  ];
}

/// Drops from [appended] any task whose trimmed, case-insensitive name
/// already appears in [existing] or earlier in [appended]; prunes areas
/// left empty. Order is otherwise preserved. The employment contract's
/// Annex A uses this so a task that is both shared to the card and
/// personally owned by the employee doesn't render twice.
List<ResponsibilityArea> dedupeAppendedAreas(
  List<ResponsibilityArea> existing,
  List<ResponsibilityArea> appended,
) {
  final seen = <String>{
    for (final a in existing)
      for (final t in a.tasks) t.trim().toLowerCase(),
  };
  final out = <ResponsibilityArea>[];
  for (final a in appended) {
    final kept = <String>[];
    for (final t in a.tasks) {
      final key = t.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      kept.add(t);
    }
    if (kept.length == a.tasks.length) {
      out.add(a); // untouched — preserve identity for callers and tests
    } else if (kept.isNotEmpty) {
      out.add(ResponsibilityArea(area: a.area, tasks: kept));
    }
  }
  return out;
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
    // An empty wp_tasks embed is authoritative ONLY for an active card: an
    // active card can't be edited down to zero without also clearing
    // key_responsibilities (see saveResponsibilities), so [] there really
    // means "deleted to zero" and must not resurrect stale JSON. An INACTIVE
    // card has no such guarantee — every card gets wp_tasks rows now (see
    // 20260720000002), but a pre-unification inactive/superseded card row
    // that predates this migration, or one whose promotion is still pending,
    // can legitimately have an empty embed with real legacy JSON still on
    // it. Falling back there keeps payslip PDFs, dashboards, and employment
    // contracts — which all resolve inactive cards via
    // list(onlyActive:false)/byId() — from rendering an empty duties annex.
    final embedIsEmptyOnInactiveCard =
        rawTasks is List && rawTasks.isEmpty && r['is_active'] == false;
    if (rawTasks is List && !embedIsEmptyOnInactiveCard) {
      // Authoritative source post-responsibility-unification: wp_tasks rows,
      // grouped/ordered by area_sort/task_sort (see responsibilitiesFromTaskRows).
      // The embed key is present (even as []) whenever it was requested — an
      // empty embed means "no responsibilities", NOT "fall back to the JSON
      // column" (PostgREST returns [] for a requested-but-empty embed, it does
      // not omit the key; a deleted-to-zero card must not resurrect stale JSON).
      responsibilities = responsibilitiesFromTaskRows(
        rawTasks.cast<Map<String, dynamic>>(),
      );
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
        ..sort(
          (a, b) => (a['sort_order'] as int? ?? 0).compareTo(
            b['sort_order'] as int? ?? 0,
          ),
        );
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
      kpis = rawKpis
          .cast<Map<String, dynamic>>()
          .map(KpiItem.fromJson)
          .toList();
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

  /// Returns a copy with [extra] responsibility areas appended after the
  /// existing (authored) ones. Used by the repository to fold in shared
  /// accountabilities (see responsibilitiesFromAssignedTasks) without
  /// touching the authored list's order or wording — a no-op copy when
  /// [extra] is empty, so callers can call this unconditionally.
  RoleScorecard withExtraResponsibilities(List<ResponsibilityArea> extra) {
    if (extra.isEmpty) return this;
    return RoleScorecard(
      id: id,
      companyId: companyId,
      jobTitle: jobTitle,
      departmentId: departmentId,
      missionStatement: missionStatement,
      responsibilities: [...responsibilities, ...extra],
      kpis: kpis,
      requiredSkills: requiredSkills,
      behavioralExpectations: behavioralExpectations,
      version: version,
      salaryRangeMin: salaryRangeMin,
      salaryRangeMax: salaryRangeMax,
      baseSalary: baseSalary,
      wageType: wageType,
      workHoursPerDay: workHoursPerDay,
      workDaysPerWeek: workDaysPerWeek,
      isActive: isActive,
      effectiveDate: effectiveDate,
      supersededById: supersededById,
      shiftTemplateId: shiftTemplateId,
      hiringEntityId: hiringEntityId,
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
