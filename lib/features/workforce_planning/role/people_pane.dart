import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/kpi.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../employees/profile/tabs/role_tab.dart' show EmployeeKpiAssignmentSection;
import '../../kpi_library/kpi_measurable.dart';
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
/// — it watches `wpActiveEmployeesProvider`, `wpPersonLoadsProvider`,
/// `roleKpisProvider` and `kpiLibraryProvider` directly on every build, so it
/// can never disagree with what those providers currently hold.
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
    final libraryAsync = ref.watch(kpiLibraryProvider);
    final libraryById = {
      for (final k in libraryAsync.asData?.value ?? const <Kpi>[]) k.id: k,
    };

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
                final roleKpiIds = {for (final k in roleKpis) k.kpiId};
                // Only a measurable KPI may join a person's tracked set —
                // `kpi_measurable.dart`'s own words. Shared with the employee
                // profile's Role tab, which gates the same Save button, so
                // the two can never disagree about what is pickable.
                final measurableKpiIds = measurableRoleKpiIds(
                  roleKpis: roleKpis,
                  libraryById: libraryById,
                  libraryLoaded: libraryAsync.hasValue,
                );
                return Column(
                  children: [
                    for (final holder in holders)
                      _PersonRow(
                        key: ValueKey('person-${holder.id}'),
                        employee: holder,
                        cardId: cardId,
                        load: loadByEmployee[holder.id],
                        roleKpiIds: roleKpiIds,
                        measurableKpiIds: measurableKpiIds,
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
/// `tracks N of M` or a "No KPI set" warning chip. Expanded, it mounts
/// [EmployeeKpiAssignmentSection] itself — reused rather than rebuilt — wired
/// to `validateKpiSet` via that widget's `validate` hook, so an unmeasurable
/// pick disables Save right there instead of only being described beside it.
class _PersonRow extends ConsumerWidget {
  const _PersonRow({
    super.key,
    required this.employee,
    required this.cardId,
    required this.load,
    required this.roleKpiIds,
    required this.measurableKpiIds,
  });

  final Employee employee;
  final String cardId;
  final WpPersonLoad? load;
  final Set<String> roleKpiIds;
  final Set<String> measurableKpiIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedAsync = ref.watch(
      employeeAssignedKpiIdsProvider(employee.id),
    );

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
        // Intersected with the role, the same way `trackedCount` below and
        // `initialCheckedKpiIds` (which defines an off-role id as absent)
        // already are. Reading the raw stored set instead meant that after a
        // manager removed a KPI from the role, a holder whose only tracked
        // KPI was that one showed "tracks 0 of 3" and no warning — the exact
        // state the chip exists to catch.
        final onRole = assigned.intersection(roleKpiIds);
        final needsSet = employeeNeedsKpiSet(onRole);
        final trackedCount = onRole.length;
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
            EmployeeKpiAssignmentSection(
              employeeId: employee.id,
              roleScorecardId: cardId,
              canManage: true,
              // "Not on this role" can't actually happen through these
              // checkboxes — they only ever list `roleKpiIds` itself. The
              // reachable problem here is an unmeasurable pick; the
              // reachable warning is the 3-5 count band. An empty set is
              // its own problem too, but that state is what the collapsed
              // "No KPI set" chip above already exists to flag as a gap to
              // close, not to block — the manager must still be able to
              // open this and start ticking boxes.
              validate: (checked) => validateKpiSet(
                selectedKpiIds: checked,
                roleKpiIds: roleKpiIds,
                measurableKpiIds: measurableKpiIds,
              ),
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
}
