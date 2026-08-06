import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../role_rollup.dart';
import '../wp_providers.dart';
import 'load_chip.dart';
import 'tab_intro.dart';

/// A single person's computed owned tasks (times/minutes/hours resolved).
/// Public (not `_`-prefixed) so widget tests can override it directly.
final ownerComputedProvider =
    FutureProvider.family<List<WpTaskComputed>, String>(
      (ref, employeeId) => ref
          .watch(workforcePlanningRepositoryProvider)
          .taskComputedForOwner(employeeId),
    );

/// The Roles tab: cost and load per ROLE CARD.
///
/// The per-PERSON lens that used to live here was removed — Balance answers
/// "what is this person carrying?" better (drag to move work, before/after
/// preview, headroom), and two tabs answering the same question is how a hub
/// gets confusing. This tab now answers only the question Balance cannot: is
/// the ROLE viable, whoever holds it?
class RoleViewTab extends StatelessWidget {
  const RoleViewTab({super.key});

  @override
  Widget build(BuildContext context) =>
      const _RoleLens(header: SizedBox.shrink());
}

/// The per-ROLE lens: one row per active role card with its responsibility
/// count, modelled hours, load against the combined capacity of its holders,
/// monthly cost and cost per hour.
///
/// Deliberately reads "—" rather than 0 wherever a figure is unknown. Most
/// responsibilities are still uncosted, and a 0% load or ₱0/hr would be read as
/// a finding rather than as missing data.
class _RoleLens extends ConsumerWidget {
  const _RoleLens({required this.header});

  final Widget header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final tasksAsync = ref.watch(wpTasksProvider);
    final computedAsync = ref.watch(wpAllTaskComputedProvider);
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);

    if (cardsAsync.isLoading ||
        empsAsync.isLoading ||
        tasksAsync.isLoading ||
        computedAsync.isLoading ||
        loadsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err =
        cardsAsync.error ??
        empsAsync.error ??
        tasksAsync.error ??
        computedAsync.error ??
        loadsAsync.error;
    if (err != null) {
      return Center(
        child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
      );
    }

    // Capacity comes from wp_person_load, which already resolves the per-person
    // override and the company default — re-deriving it here would be a second
    // implementation free to drift from the view.
    final capacityByEmployee = {
      for (final l in loadsAsync.asData!.value) l.employeeId: l.capacityHours,
    };
    final rows = buildRoleRollup(
      cards: cardsAsync.asData!.value,
      employees: empsAsync.asData!.value,
      tasks: tasksAsync.asData!.value,
      computedByTaskId: {
        for (final c in computedAsync.asData!.value) c.taskId: c,
      },
      multiplier: multiplier,
      capacityHoursFor: (id) => capacityByEmployee[id] ?? 0,
    );
    final totals = totalRoleRollup(rows);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const TabIntro(
            purpose:
                'Is each role viable, whoever holds it? '
                'Effort and cost per role card, not per person.',
            details: [
              (
                term: 'Why this differs from Balance.',
                meaning:
                    'Balance asks whether a PERSON is overloaded. This asks '
                    'whether the ROLE is — the question that survives someone '
                    'leaving or a second holder joining.',
              ),
              (
                term: 'Cost/mo',
                meaning:
                    'The role card\'s base salary × 26 working days × how '
                    'many people hold it — the same working-day figure payroll '
                    'uses. A card with no salary reads "—", never ₱0.',
              ),
              (
                term: 'Why so many dashes.',
                meaning:
                    'A role with nothing costed shows "—" rather than 0%, '
                    'because unknown and idle are not the same finding.',
              ),
              WpGlossary.weighted,
              WpGlossary.load,
            ],
          ),
          const SizedBox(height: 16),
          if (totals.uncosted > 0) ...[
            _uncostedNotice(context, totals),
            const SizedBox(height: 12),
          ],
          if (rows.isEmpty)
            const Text('No active role cards.')
          else
            _table(context, rows, totals),
        ],
      ),
    );
  }

  Widget _uncostedNotice(BuildContext context, RoleRollupTotals t) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${t.uncosted} of ${t.responsibilities} responsibilities are not costed, '
              'so hours and load are incomplete. Cost them on the Tasks tab.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(
    BuildContext context,
    List<RoleRollupRow> rows,
    RoleRollupTotals t,
  ) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
    final mono = AppTheme.mono(context);
    Widget num(String s) => Text(s, style: mono);

    return ResponsiveTable(
      fullWidth: true,
      child: DataTable(
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Held by'), numeric: true),
          DataColumn(label: Text('Resp.'), numeric: true),
          DataColumn(label: Text('Hours/mo'), numeric: true),
          DataColumn(label: Text('Load')),
          DataColumn(label: Text('Cost/mo'), numeric: true),
          DataColumn(label: Text('₱/hour'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      r.jobTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(num('${r.holders}')),
                DataCell(
                  num(
                    r.fullyCosted
                        ? '${r.responsibilities}'
                        : '${r.costedResponsibilities}/${r.responsibilities}',
                  ),
                ),
                DataCell(
                  num(
                    r.costedResponsibilities == 0
                        ? '—'
                        : r.hoursPerMonth.toStringAsFixed(1),
                  ),
                ),
                DataCell(_loadCell(context, r, mono)),
                DataCell(
                  num(
                    r.monthlyCost == null
                        ? '—'
                        : money.format(r.monthlyCost!.toDouble()),
                  ),
                ),
                DataCell(
                  num(
                    r.costPerHour == null
                        ? '—'
                        : money.format(r.costPerHour!.toDouble()),
                  ),
                ),
              ],
            ),
          DataRow(
            cells: [
              const DataCell(
                Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              DataCell(num('${t.holders}')),
              DataCell(
                num('${t.costedResponsibilities}/${t.responsibilities}'),
              ),
              DataCell(
                num(
                  t.hoursPerMonth == 0
                      ? '—'
                      : t.hoursPerMonth.toStringAsFixed(1),
                ),
              ),
              // No total load%: averaging load across roles is meaningless, and
              // a number here would be read as "the company is N% busy" while
              // most responsibilities are uncosted.
              const DataCell(Text('—')),
              DataCell(num(money.format(t.monthlyCost.toDouble()))),
              const DataCell(Text('—')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loadCell(BuildContext context, RoleRollupRow r, TextStyle mono) {
    final f = r.loadFraction;
    if (f == null) {
      return Tooltip(
        message: r.holders == 0
            ? 'Nobody holds this role, so there is no capacity to measure against.'
            : 'None of this role\'s responsibilities are costed yet.',
        child: const Text('—'),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${(f * 100).round()}%', style: mono),
        const SizedBox(width: 6),
        LoadStatusChip(status: r.status!),
      ],
    );
  }
}
