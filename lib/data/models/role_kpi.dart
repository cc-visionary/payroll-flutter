/// One KPI on a role card, with its stable library id — used by the per-employee
/// assignment UI (which keys on kpi_id) rather than the display-only KpiItem.
class RoleKpi {
  final String kpiId;
  final String name;
  final String? target;
  final String? frequency;
  const RoleKpi({
    required this.kpiId,
    required this.name,
    this.target,
    this.frequency,
  });

  factory RoleKpi.fromRow(Map<String, dynamic> r) => RoleKpi(
    kpiId: r['kpi_id'] as String,
    name: (r['kpis'] as Map?)?['name'] as String? ?? '',
    target: r['target'] as String?,
    frequency: r['frequency'] as String?,
  );
}
