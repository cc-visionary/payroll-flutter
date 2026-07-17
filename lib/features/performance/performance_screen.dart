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
import 'performance_dashboard.dart';

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
        content: Text(
          result.existed
              ? 'Check-in already existed — opened it.'
              : 'Check-in created.',
        ),
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(
          title: const Text('Performance'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Legacy check-ins'),
            ],
          ),
          actions: [
            if (profile.isHrOrAdmin) ...[
              if (isMobile(context))
                IconButton(
                  tooltip: 'Review cycles',
                  onPressed: () => context.go('/performance/review-cycles'),
                  icon: const Icon(Icons.event_note_outlined),
                )
              else
                TextButton.icon(
                  onPressed: () => context.go('/performance/review-cycles'),
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('Review cycles'),
                ),
              TextButton.icon(
                onPressed: _onNewCheckIn,
                icon: const Icon(Icons.add),
                label: const Text('New legacy check-in'),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8),
                child: FilledButton.icon(
                  onPressed: _onGenerateBatch,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Generate legacy check-ins'),
                ),
              ),
            ],
          ],
        ),
        body: TabBarView(
          children: [
            const PerformanceDashboard(),
            Column(
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
          ],
        ),
      ),
    );
  }
}

const _kAllStatuses = <String>[
  'DRAFT',
  'SUBMITTED',
  'UNDER_REVIEW',
  'COMPLETED',
  'SKIPPED',
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
    final employees =
        ref
            .watch(
              employeeListProvider(
                const EmployeeListQuery(includeArchived: true),
              ),
            )
            .asData
            ?.value ??
        const [];
    final empNameById = {for (final e in employees) e.id: e.fullName};
    final periodNames =
        ref.watch(checkInPeriodNamesProvider).asData?.value ??
        const <String, String>{};
    final isAdmin =
        ref.watch(userProfileProvider).asData?.value?.isHrOrAdmin ?? false;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Text('No check-ins match the current filters.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final c = rows[i];
            final empName = empNameById[c.employeeId] ?? '(unknown employee)';
            final periodName = periodNames[c.periodId] ?? '—';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(empName),
                subtitle: Text(
                  '$periodName · ${c.status}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.createdAt.toIso8601String().substring(0, 10),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isAdmin)
                      PopupMenuButton<String>(
                        tooltip: 'Actions',
                        onSelected: (v) {
                          if (v == 'delete') {
                            _confirmDelete(
                              context,
                              ref,
                              checkInId: c.id,
                              status: c.status,
                              empName: empName,
                              periodName: periodName,
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline),
                              title: Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                onTap: () => context.go('/performance/${c.id}'),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref, {
    required String checkInId,
    required String status,
    required String empName,
    required String periodName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this check-in?'),
        content: Text(
          "Permanently deletes $empName's $periodName check-in (status "
          '$status), along with its goals and skill ratings. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(performanceRepositoryProvider).deleteCheckIn(checkInId);
      ref.invalidate(performanceCheckInListProvider);
      messenger.showSnackBar(
        SnackBar(content: Text("Deleted $empName's $periodName check-in.")),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }
}
