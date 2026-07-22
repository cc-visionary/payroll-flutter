import '../../data/models/kpi.dart';
import '../../data/repositories/role_scorecard_repository.dart' show KpiAssignee;

const String kUncategorized = 'Uncategorized';

String kpiCategoryOf(Kpi k) =>
    (k.category?.trim().isNotEmpty ?? false) ? k.category!.trim() : kUncategorized;

/// Whether a KPI is tracked on anybody. An unassigned KPI is not a mistake —
/// it may be deliberately held in reserve — but it measures nothing today, and
/// that is worth being able to see and filter.
bool kpiIsAssigned(Kpi k, Map<String, List<KpiAssignee>> assignedByKpi) =>
    (assignedByKpi[k.id] ?? const []).isNotEmpty;

class KpiFilter {
  const KpiFilter({
    this.query = '',
    this.category,
    this.assignment,
    this.showInactive = false,
  });

  /// Matched case-insensitively against name, category and measurement.
  final String query;
  final String? category;

  /// true = assigned to someone, false = assigned to nobody, null = either.
  final bool? assignment;

  /// Deactivated KPIs are hidden by default: they cannot be picked for new
  /// role cards, so showing them by default pads the library with rows nobody
  /// can act on.
  final bool showInactive;

  bool get isEmpty =>
      query.trim().isEmpty && category == null && assignment == null && !showInactive;
}

List<Kpi> applyKpiFilter(
  List<Kpi> kpis,
  KpiFilter f,
  Map<String, List<KpiAssignee>> assignedByKpi,
) {
  final q = f.query.trim().toLowerCase();
  return [
    for (final k in kpis)
      if ((f.showInactive || k.isActive) &&
          (q.isEmpty ||
              k.name.toLowerCase().contains(q) ||
              kpiCategoryOf(k).toLowerCase().contains(q) ||
              (k.measurementUnit ?? '').toLowerCase().contains(q) ||
              (k.description ?? '').toLowerCase().contains(q)) &&
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
    required this.peopleTracked,
    required this.categories,
  });

  final int total;
  final int active;

  /// Active KPIs tracked on at least one person.
  final int assigned;
  final int uncategorized;

  /// Distinct employees tracked on at least one KPI.
  final int peopleTracked;
  final int categories;

  int get unassigned => active - assigned;
  double get assignedFraction => active == 0 ? 0 : assigned / active;
}

KpiLibraryStats kpiLibraryStats(
  List<Kpi> kpis,
  Map<String, List<KpiAssignee>> assignedByKpi,
) {
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
    peopleTracked: people.length,
    categories: kpiCategories(active).where((c) => c != kUncategorized).length,
  );
}
