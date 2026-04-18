import 'package:decimal/decimal.dart';

class ResponsibilityArea {
  final String area;
  final List<String> tasks;
  const ResponsibilityArea({required this.area, required this.tasks});
  factory ResponsibilityArea.fromJson(Map<String, dynamic> j) => ResponsibilityArea(
        area: j['area'] as String? ?? '',
        tasks: (j['tasks'] as List<dynamic>? ??
                (j['task'] != null ? <dynamic>[j['task']] : const <dynamic>[]))
            .map((e) => e.toString())
            .toList(),
      );
  Map<String, dynamic> toJson() => {'area': area, 'tasks': tasks};
}

class KpiItem {
  final String metric;
  final String frequency;
  const KpiItem({required this.metric, required this.frequency});
  factory KpiItem.fromJson(Map<String, dynamic> j) => KpiItem(
        metric: j['metric'] as String? ?? '',
        frequency: j['frequency'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {'metric': metric, 'frequency': frequency};
}

class RoleScorecard {
  final String id;
  final String companyId;
  final String jobTitle;
  final String? departmentId;
  final String missionStatement;
  final List<ResponsibilityArea> responsibilities;
  final List<KpiItem> kpis;
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

  const RoleScorecard({
    required this.id,
    required this.companyId,
    required this.jobTitle,
    this.departmentId,
    required this.missionStatement,
    required this.responsibilities,
    required this.kpis,
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
  });

  factory RoleScorecard.fromRow(Map<String, dynamic> r) {
    final rawResp = r['key_responsibilities'];
    final rawKpis = r['kpis'];
    List<ResponsibilityArea> responsibilities;
    if (rawResp is List) {
      responsibilities = rawResp
          .cast<Map<String, dynamic>>()
          .map(ResponsibilityArea.fromJson)
          .toList();
    } else {
      responsibilities = const [];
    }
    List<KpiItem> kpis;
    if (rawKpis is List) {
      kpis = rawKpis.cast<Map<String, dynamic>>().map(KpiItem.fromJson).toList();
    } else {
      kpis = const [];
    }
    Decimal? dec(Object? v) => v == null ? null : Decimal.parse(v.toString());
    return RoleScorecard(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      jobTitle: r['job_title'] as String,
      departmentId: r['department_id'] as String?,
      missionStatement: r['mission_statement'] as String? ?? '',
      responsibilities: responsibilities,
      kpis: kpis,
      salaryRangeMin: dec(r['salary_range_min']),
      salaryRangeMax: dec(r['salary_range_max']),
      baseSalary: dec(r['base_salary']),
      wageType: r['wage_type'] as String? ?? 'MONTHLY',
      workHoursPerDay: r['work_hours_per_day'] as int? ?? 8,
      workDaysPerWeek: r['work_days_per_week'] as String? ?? 'Monday to Saturday',
      isActive: r['is_active'] as bool? ?? true,
      effectiveDate: DateTime.parse(r['effective_date'] as String),
      supersededById: r['superseded_by_id'] as String?,
      shiftTemplateId: r['shift_template_id'] as String?,
    );
  }

  Map<String, dynamic> toUpsertPayload() => {
        'id': id,
        'company_id': companyId,
        'job_title': jobTitle,
        'department_id': departmentId,
        'mission_statement': missionStatement,
        'key_responsibilities': responsibilities.map((r) => r.toJson()).toList(),
        'kpis': kpis.map((k) => k.toJson()).toList(),
        'salary_range_min': salaryRangeMin?.toString(),
        'salary_range_max': salaryRangeMax?.toString(),
        'base_salary': baseSalary?.toString(),
        'wage_type': wageType,
        'work_hours_per_day': workHoursPerDay,
        'work_days_per_week': workDaysPerWeek,
        'is_active': isActive,
        'effective_date': effectiveDate.toIso8601String().substring(0, 10),
      };
}
