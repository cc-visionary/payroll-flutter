import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/role_kpi.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../employees/profile/tabs/role_tab.dart' show EmployeeKpiAssignmentSection;
import '../../kpi_library/kpi_set_rules.dart';
import '../capacity_math.dart';
import '../tabs/load_chip.dart';
import '../wp_providers.dart';

/// The fourth pane of the role workbench: who holds this role, how loaded
/// they are, and which of the role's KPIs each holder is actually measured
/// on.
///
/// Unlike [RoleDetailsPane]/`ResponsibilitiesPane`/`KpisPane`, this pane has
/// no local mutable draft and therefore no capture-once snapshot to go stale
/// — it watches `wpActiveEmployeesProvider`, `wpPersonLoadsProvider` and
/// `roleKpisProvider` directly on every build, so it can never disagree with
/// what those providers currently hold.
///
/// Holders are filtered to ACTIVE, non-deleted employees on this card. Per
/// `resolveEffectiveOwner`'s documented gap, `wpActiveEmployeesProvider`
/// itself only excludes `deleted_at`-set rows — it does NOT exclude the six
/// non-ACTIVE employment statuses (RESIGNED, TERMINATED, AWOL, DECEASED,
/// END_OF_CONTRACT, RETIRED). The `wp_person_load` view's holders CTE (what
/// actually splits hours/attributes ownership server-side) requires both
/// `employment_status = 'ACTIVE'` AND `deleted_at is null`; filtering here
/// the same way keeps this pane's holder list in agreement with that view
/// instead of quietly showing a separated employee as if they still held the
/// role.
class PeoplePane extends ConsumerWidget {
  const PeoplePane({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees =
        ref.watch(wpActiveEmployeesProvider).asData?.value ??
        const <Employee>[];
    final loads =
        ref.watch(wpPersonLoadsProvider).asData?.value ??
        const <WpPersonLoad>[];
    final roleKpisAsync = ref.watch(roleKpisProvider(cardId));

    final holders =
        employees
            .where(
              (e) =>
                  e.roleScorecardId == cardId &&
                  e.employmentStatus == 'ACTIVE' &&
                  e.deletedAt == null,
            )
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final loadByEmployee = {for (final l in loads) l.employeeId: l};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'People',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            roleKpisAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text("Could not load this role's KPIs: $e"),
              ),
              data: (roleKpis) {
                if (holders.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Nobody holds this role yet.'),
                  );
                }
                return Column(
                  children: [
                    for (final holder in holders)
                      _PersonRow(
                        key: ValueKey('person-${holder.id}'),
                        employee: holder,
                        cardId: cardId,
                        load: loadByEmployee[holder.id],
                        roleKpis: roleKpis,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One holder's row: collapsed, it names them, their load band, and either
/// `tracks N of M` or a "No KPI set" warning chip. Expanded, it shows a
/// validation summary for their currently-saved selection followed by
/// [EmployeeKpiAssignmentSection] itself, reused rather than rebuilt.
class _PersonRow extends ConsumerWidget {
  const _PersonRow({
    super.key,
    required this.employee,
    required this.cardId,
    required this.load,
    required this.roleKpis,
  });

  final Employee employee;
  final String cardId;
  final WpPersonLoad? load;
  final List<RoleKpi> roleKpis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedAsync = ref.watch(
      employeeAssignedKpiIdsProvider(employee.id),
    );
    final roleKpiIds = {for (final k in roleKpis) k.kpiId};

    return assignedAsync.when(
      loading: () => ListTile(
        title: Text(employee.fullName),
        trailing: const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => ListTile(
        title: Text(employee.fullName),
        subtitle: Text('Could not load KPI set: $e'),
      ),
      data: (assigned) {
        final needsSet = employeeNeedsKpiSet(assigned);
        final trackedCount = assigned.intersection(roleKpiIds).length;
        return ExpansionTile(
          key: ValueKey('person-tile-${employee.id}'),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  employee.fullName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              _loadLabel(context),
            ],
          ),
          subtitle: Row(
            children: [
              if (needsSet)
                const StatusChip(label: 'No KPI set', tone: StatusTone.warning)
              else
                Text('tracks $trackedCount of ${roleKpiIds.length}'),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _validationBanner(context, assigned, roleKpiIds),
            ),
            EmployeeKpiAssignmentSection(
              employeeId: employee.id,
              roleScorecardId: cardId,
              canManage: true,
            ),
          ],
        );
      },
    );
  }

  Widget _loadLabel(BuildContext context) {
    final l = load;
    if (l == null) {
      return const StatusChip(label: 'No load data', tone: StatusTone.neutral);
    }
    final fraction = personLoad(l);
    final pct = (fraction * 100).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$pct% loaded', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 6),
        LoadStatusChip(status: loadStatus(fraction)),
      ],
    );
  }

  /// A read-only summary of `validateKpiSet` against the holder's currently
  /// saved selection — refreshed whenever `employeeAssignedKpiIdsProvider`
  /// re-fetches (including right after `EmployeeKpiAssignmentSection`'s own
  /// save invalidates it below). Problems are drawn in the same danger tone
  /// [KpisPane] uses for its own hints; warnings (the 3-5 band) are shown in
  /// warning tone but never suppress the checkboxes or Save button beneath —
  /// `validateKpiSet` itself distinguishes the two for exactly this reason.
  ///
  /// The checkboxes below only ever offer this role's own KPIs, so an
  /// off-role selection can't occur through this UI; every role KPI is
  /// treated as measurable here for the same reason KpisPane's own
  /// measurability check has nothing to add on this pane — this pane does
  /// not carry the KPI library's definition fields needed to test that
  /// properly, so it is intentionally left to the KPIs pane.
  Widget _validationBanner(
    BuildContext context,
    Set<String> assigned,
    Set<String> roleKpiIds,
  ) {
    final verdict = validateKpiSet(
      selectedKpiIds: assigned,
      roleKpiIds: roleKpiIds,
      measurableKpiIds: roleKpiIds,
    );
    if (verdict.problems.isEmpty && verdict.warnings.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in verdict.problems) _hint(context, StatusTone.danger, p),
        for (final w in verdict.warnings)
          _hint(context, StatusTone.warning, w),
      ],
    );
  }

  Widget _hint(BuildContext context, StatusTone tone, String text) {
    final color = StatusPalette.of(context, tone).foreground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}
