import '../../data/models/kpi_result.dart';

const _order = [KpiScope.personal, KpiScope.department, KpiScope.company];

KpiScope? _levelScope(String level) => switch (level) {
  'PERSONAL' => KpiScope.personal,
  'DEPARTMENT' => KpiScope.department,
  'COMPANY' => KpiScope.company,
  _ => null,
};

/// The scopes a KPI produces rows at.
///
/// Rolling UP is meaningful, rolling DOWN never is: a Department KPI has no
/// per-person decomposition merely because it is DIRECT. So every rule here
/// starts at the KPI's own level and only ever widens upward.
///
/// SHARED is the one that earns its own branch — it exists precisely so a team
/// outcome (Critical Stockouts) is never attributed to an individual, so it
/// starts at department however it is levelled.
Set<KpiScope> scopesFor({required String level, required String rollupType}) {
  final own = _levelScope(level);
  if (own == null) {
    // An unrecognised level computes nothing, visible as absence not wrong data.
    return {};
  }
  switch (rollupType) {
    case 'DIRECT':
      return _order.sublist(_order.indexOf(own)).toSet();
    case 'SHARED':
      final floor = own == KpiScope.personal ? KpiScope.department : own;
      return _order.sublist(_order.indexOf(floor)).toSet();
    default:
      // ALIGNED, INDEPENDENT, and anything unrecognised. Computing less than
      // asked is recoverable; inventing rows across scopes is not.
      return {own};
  }
}
