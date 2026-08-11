/// What "remove" means for a given row. Archive buys reversibility and an audit
/// trail; it does NOT protect an already-issued document, because saved
/// documents re-render live from these same rows (see the spec's known
/// limitation). Deleting a row that something else references is the case this
/// exists to prevent.
enum RemovalAction { delete, archive, blocked }

/// A `wp_tasks` row. Assignments (`wp_task_assignments`) are the history that
/// makes a task worth keeping — costing and load attribution both hang off
/// them.
RemovalAction removalActionForTask({required int assignmentCount}) =>
    assignmentCount > 0 ? RemovalAction.archive : RemovalAction.delete;

/// A `role_scorecard_kpis` row. [hasLogs] is always false until Spec B creates
/// `kpi_logs`; the rule is encoded now so B only has to supply the fact.
RemovalAction removalActionForKpiLink({required bool hasLogs}) =>
    hasLogs ? RemovalAction.archive : RemovalAction.delete;

/// A `kpis` row. Archive here means `is_active = false`.
RemovalAction removalActionForLibraryKpi({
  required int roleLinkCount,
  required bool hasLogs,
}) => (roleLinkCount > 0 || hasLogs)
    ? RemovalAction.archive
    : RemovalAction.delete;
