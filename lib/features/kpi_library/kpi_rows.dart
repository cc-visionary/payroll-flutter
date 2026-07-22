import '../../data/models/kpi.dart';
import '../../data/repositories/role_scorecard_repository.dart' show KpiAssignee;

const String kUncategorized = 'Uncategorized';
const String kNoDepartment = 'No department';

String kpiCategoryOf(Kpi k) =>
    (k.category?.trim().isNotEmpty ?? false) ? k.category!.trim() : kUncategorized;

/// Whether a KPI is tracked on anybody. An unassigned KPI is not a mistake —
/// it may be deliberately held in reserve — but it measures nothing today, and
/// that is worth being able to see and filter.
bool kpiIsAssigned(Kpi k, Map<String, List<KpiAssignee>> assignedByKpi) =>
    (assignedByKpi[k.id] ?? const []).isNotEmpty;

/// A KPI belongs to a department first and a category second — the library is
/// read department by department, because that is who answers for the numbers.
String kpiDepartmentOf(Kpi k, Map<String, String> departmentNameById) {
  final id = k.departmentId;
  if (id == null) return kNoDepartment;
  return departmentNameById[id] ?? kNoDepartment;
}

/// Departments present, alphabetical, with "No department" last — it is a gap
/// to close, not a department.
List<String> kpiDepartments(List<Kpi> kpis, Map<String, String> names) {
  final set = {for (final k in kpis) kpiDepartmentOf(k, names)};
  final out = set.where((d) => d != kNoDepartment).toList()..sort();
  if (set.contains(kNoDepartment)) out.add(kNoDepartment);
  return out;
}

/// department -> category -> KPIs, each level ordered, KPIs by name.
Map<String, Map<String, List<Kpi>>> groupKpisByDepartment(
  List<Kpi> kpis,
  Map<String, String> departmentNameById,
) {
  final byDept = <String, List<Kpi>>{};
  for (final k in kpis) {
    (byDept[kpiDepartmentOf(k, departmentNameById)] ??= []).add(k);
  }
  return {
    for (final d in kpiDepartments(kpis, departmentNameById))
      if (byDept[d] != null) d: groupKpisByCategory(byDept[d]!),
  };
}

class KpiFilter {
  const KpiFilter({
    this.query = '',
    this.department,
    this.category,
    this.assignment,
    this.showInactive = false,
  });

  /// Matched case-insensitively against name, category and measurement.
  final String query;
  final String? department;
  final String? category;

  /// true = assigned to someone, false = assigned to nobody, null = either.
  final bool? assignment;

  /// Deactivated KPIs are hidden by default: they cannot be picked for new
  /// role cards, so showing them by default pads the library with rows nobody
  /// can act on.
  final bool showInactive;

  bool get isEmpty =>
      query.trim().isEmpty &&
      department == null &&
      category == null &&
      assignment == null &&
      !showInactive;
}

List<Kpi> applyKpiFilter(
  List<Kpi> kpis,
  KpiFilter f,
  Map<String, List<KpiAssignee>> assignedByKpi, {
  Map<String, String> departmentNameById = const {},
}) {
  final q = f.query.trim().toLowerCase();
  return [
    for (final k in kpis)
      if ((f.showInactive || k.isActive) &&
          (q.isEmpty ||
              k.name.toLowerCase().contains(q) ||
              kpiCategoryOf(k).toLowerCase().contains(q) ||
              (k.measurementUnit ?? '').toLowerCase().contains(q) ||
              (k.description ?? '').toLowerCase().contains(q)) &&
          (f.department == null ||
              kpiDepartmentOf(k, departmentNameById) == f.department) &&
          (f.category == null || kpiCategoryOf(k) == f.category) &&
          (f.assignment == null ||
              kpiIsAssigned(k, assignedByKpi) == f.assignment))
        k,
  ];
}

/// Categories present in the data, alphabetical, with Uncategorized last —
/// it is a gap to be closed, not a category, so it belongs at the bottom.
List<String> kpiCategories(List<Kpi> kpis) {
  final set = {for (final k in kpis) kpiCategoryOf(k)};
  final out = set.where((c) => c != kUncategorized).toList()..sort();
  if (set.contains(kUncategorized)) out.add(kUncategorized);
  return out;
}

Map<String, List<Kpi>> groupKpisByCategory(List<Kpi> kpis) {
  final grouped = <String, List<Kpi>>{};
  for (final k in kpis) {
    (grouped[kpiCategoryOf(k)] ??= []).add(k);
  }
  for (final v in grouped.values) {
    v.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  return {
    for (final c in kpiCategories(kpis))
      if (grouped[c] != null) c: grouped[c]!,
  };
}

/// Library-level figures, so the page opens with what shape the library is in
/// rather than only a list to scroll.
class KpiLibraryStats {
  const KpiLibraryStats({
    required this.total,
    required this.active,
    required this.assigned,
    required this.uncategorized,
    required this.noDepartment,
    required this.peopleTracked,
    required this.categories,
    required this.departments,
  });

  final int total;
  final int active;

  /// Active KPIs tracked on at least one person.
  final int assigned;
  final int uncategorized;
  final int noDepartment;

  /// Distinct employees tracked on at least one KPI.
  final int peopleTracked;
  final int categories;
  final int departments;

  int get unassigned => active - assigned;
  double get assignedFraction => active == 0 ? 0 : assigned / active;
}

KpiLibraryStats kpiLibraryStats(
  List<Kpi> kpis,
  Map<String, List<KpiAssignee>> assignedByKpi, {
  Map<String, String> departmentNameById = const {},
}) {
  final active = [for (final k in kpis) if (k.isActive) k];
  final people = <String>{};
  for (final k in active) {
    for (final a in assignedByKpi[k.id] ?? const <KpiAssignee>[]) {
      people.add(a.employeeId);
    }
  }
  return KpiLibraryStats(
    total: kpis.length,
    active: active.length,
    assigned: active.where((k) => kpiIsAssigned(k, assignedByKpi)).length,
    uncategorized:
        active.where((k) => kpiCategoryOf(k) == kUncategorized).length,
    noDepartment: active
        .where((k) => kpiDepartmentOf(k, departmentNameById) == kNoDepartment)
        .length,
    peopleTracked: people.length,
    categories: kpiCategories(active).where((c) => c != kUncategorized).length,
    departments: kpiDepartments(active, departmentNameById)
        .where((d) => d != kNoDepartment)
        .length,
  );
}
