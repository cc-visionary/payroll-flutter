import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../capacity_math.dart';
import '../tabs/load_chip.dart';
import '../wp_providers.dart';

/// The fourth pane of the role workbench: who holds this role, how loaded
/// they are, and how many of the role's KPIs they are measured on — which,
/// under pure inheritance, is always all of them.
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
                        load: loadByEmployee[holder.id],
                        roleKpiCount: roleKpis.length,
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

/// One holder's row: their name, load band, and how many of the role's KPIs
/// they are measured on. Under pure inheritance a holder tracks every KPI on
/// their role card — there is no per-employee subset to pick, so this is a
/// plain read-out, not a picker. A role with no KPIs at all is a gap; the
/// Needs-attention strip's "N roles with no KPI" signal flags it at the role
/// level rather than once per holder.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    super.key,
    required this.employee,
    required this.load,
    required this.roleKpiCount,
  });

  final Employee employee;
  final WpPersonLoad? load;
  final int roleKpiCount;

  @override
  Widget build(BuildContext context) {
    return ListTile(
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
      subtitle: roleKpiCount == 0
          ? const StatusChip(
              label: 'Role has no KPIs',
              tone: StatusTone.warning,
            )
          : Text('tracks all $roleKpiCount of $roleKpiCount'),
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
