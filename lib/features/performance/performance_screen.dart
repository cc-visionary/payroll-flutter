import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';
import 'auto_generate.dart';

class PerformanceScreen extends ConsumerStatefulWidget {
  const PerformanceScreen({super.key});
  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  List<String> _statuses = const ['DRAFT', 'SUBMITTED', 'UNDER_REVIEW'];
  bool _autoGenStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_autoGenStarted) return;
      _autoGenStarted = true;
      try {
        await autoGeneratePerformanceForCurrentQuarter(ref);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Performance auto-gen failed: $e')),
        );
      }
      if (mounted) {
        ref.invalidate(performanceCheckInListProvider);
      }
    });
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
      appBar: AppBar(title: const Text('Performance')),
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
                  c.status,
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
