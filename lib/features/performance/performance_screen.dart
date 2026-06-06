import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';
import 'generate_batch_dialog.dart';
import 'new_check_in_dialog.dart';

class PerformanceScreen extends ConsumerStatefulWidget {
  const PerformanceScreen({super.key});
  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  List<String> _statuses = const ['DRAFT', 'SUBMITTED', 'UNDER_REVIEW'];

  Future<void> _onGenerateBatch() async {
    final result = await showGenerateBatchDialog(context: context);
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Created ${result.created} check-in(s)'
          '${result.existed > 0 ? ' · ${result.existed} already existed' : ''}.',
        ),
      ),
    );
  }

  Future<void> _onNewCheckIn() async {
    final result = await showNewCheckInDialog(context: context);
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.existed
            ? 'Check-in already existed — opened it.'
            : 'Check-in created.'),
      ),
    );
    if (!mounted) return;
    context.go('/performance/${result.id}');
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (profile == null) {
      return Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(title: const Text('Performance')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Performance'),
        actions: [
          if (profile.isHrOrAdmin) ...[
            TextButton.icon(
              onPressed: _onNewCheckIn,
              icon: const Icon(Icons.add),
              label: const Text('New check-in'),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: FilledButton.icon(
                onPressed: _onGenerateBatch,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Generate check-ins'),
              ),
            ),
          ],
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(
            statuses: _statuses,
            onStatusesChanged: (s) => setState(() => _statuses = s),
          ),
          Expanded(
            child: _CheckInsTable(
              statuses: _statuses,
              employeeId: profile.isHrOrAdmin ? null : profile.employeeId,
            ),
          ),
        ],
      ),
    );
  }
}

const _kAllStatuses = <String>[
  'DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'COMPLETED', 'SKIPPED',
];

class _FilterBar extends StatelessWidget {
  final List<String> statuses;
  final ValueChanged<List<String>> onStatusesChanged;
  const _FilterBar({required this.statuses, required this.onStatusesChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in _kAllStatuses)
            FilterChip(
              label: Text(s),
              selected: statuses.contains(s),
              onSelected: (v) {
                final next = [...statuses];
                if (v) {
                  next.add(s);
                } else {
                  next.remove(s);
                }
                onStatusesChanged(next);
              },
            ),
        ],
      ),
    );
  }
}

class _CheckInsTable extends ConsumerWidget {
  final List<String> statuses;
  final String? employeeId;
  const _CheckInsTable({required this.statuses, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = PerformanceListQuery(
      statuses: statuses.isEmpty ? null : statuses,
      employeeId: employeeId,
    );
    final async = ref.watch(performanceCheckInListProvider(q));
    final employees = ref.watch(
            employeeListProvider(const EmployeeListQuery(includeArchived: true)))
        .asData
        ?.value ?? const [];
    final empNameById = {for (final e in employees) e.id: e.fullName};
    final periodNames =
        ref.watch(checkInPeriodNamesProvider).asData?.value ??
            const <String, String>{};
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No check-ins match the current filters.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final c = rows[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(empNameById[c.employeeId] ?? '(unknown employee)'),
                subtitle: Text(
                  '${periodNames[c.periodId] ?? '—'} · ${c.status}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                trailing: Text(
                  c.createdAt.toIso8601String().substring(0, 10),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => context.go('/performance/${c.id}'),
              ),
            );
          },
        );
      },
    );
  }
}
