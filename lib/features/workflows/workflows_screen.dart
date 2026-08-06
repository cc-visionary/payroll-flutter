import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/repositories/workflow_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../auth/profile_provider.dart';

class WorkflowsScreen extends ConsumerStatefulWidget {
  const WorkflowsScreen({super.key});

  @override
  ConsumerState<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends ConsumerState<WorkflowsScreen> {
  List<String> _statuses = const ['DRAFT', 'IN_PROGRESS', 'COMPLETED'];
  List<String> _types = const [];

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (!(profile?.isHrOrAdmin ?? false)) {
      return Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(title: const Text('Workflows')),
        body: const Center(
          child: Text('You do not have permission to view workflows.'),
        ),
      );
    }
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Workflows')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(
            statuses: _statuses,
            types: _types,
            onStatusesChanged: (s) => setState(() => _statuses = s),
            onTypesChanged: (t) => setState(() => _types = t),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _HintBanner(),
          ),
          Expanded(
            child: _WorkflowsTable(statuses: _statuses, types: _types),
          ),
        ],
      ),
    );
  }
}

const _kAllTypes = <String>[
  'HIRING',
  'REGULARIZATION',
  'SALARY_CHANGE',
  'ROLE_CHANGE',
  'DISCIPLINARY',
  'SEPARATION',
  'REPAYMENT_AGREEMENT',
];
const _kAllStatuses = <String>[
  'DRAFT',
  'IN_PROGRESS',
  'COMPLETED',
  'CANCELLED',
];

class _HintBanner extends StatelessWidget {
  const _HintBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Workflows start from the HR action that justifies them — use "Start Workflow" on an employee\'s profile, convert an applicant, or record a penalty.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<String> statuses;
  final List<String> types;
  final ValueChanged<List<String>> onStatusesChanged;
  final ValueChanged<List<String>> onTypesChanged;

  const _FilterBar({
    required this.statuses,
    required this.types,
    required this.onStatusesChanged,
    required this.onTypesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
          const SizedBox(width: 12),
          for (final t in _kAllTypes)
            FilterChip(
              label: Text(t),
              selected: types.contains(t),
              onSelected: (v) {
                final next = [...types];
                if (v) {
                  next.add(t);
                } else {
                  next.remove(t);
                }
                onTypesChanged(next);
              },
            ),
        ],
      ),
    );
  }
}

class _WorkflowsTable extends ConsumerWidget {
  final List<String> statuses;
  final List<String> types;

  const _WorkflowsTable({required this.statuses, required this.types});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = WorkflowListQuery(
      statuses: statuses.isEmpty ? null : statuses,
      types: types.isEmpty ? null : types,
    );
    final async = ref.watch(workflowListProvider(q));
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

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Text('No workflows match the current filters.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final w = rows[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(w.title),
                subtitle: Text(
                  '${empNameById[w.employeeId] ?? '(unknown employee)'} · '
                  '${w.workflowType} · ${w.status}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Text(
                  w.createdAt.toIso8601String().substring(0, 10),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => context.go('/workflows/${w.id}'),
              ),
            );
          },
        );
      },
    );
  }
}
