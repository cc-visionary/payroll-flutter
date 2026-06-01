import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/workflow_instance.dart';
import '../../data/models/workflow_step.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/workflow_repository.dart';
import '../auth/profile_provider.dart';

class WorkflowDetailScreen extends ConsumerWidget {
  final String instanceId;
  const WorkflowDetailScreen({super.key, required this.instanceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (!(profile?.isHrOrAdmin ?? false)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: const Center(child: Text('You do not have permission.')),
      );
    }
    final async = ref.watch(workflowByIdProvider(instanceId));
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
        ),
      ),
      data: (w) {
        if (w == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Workflow')),
            body: const Center(child: Text('Workflow not found.')),
          );
        }
        return _Body(w: w);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final WorkflowInstance w;
  const _Body({required this.w});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee =
        ref.watch(employeeByIdProvider(w.employeeId)).asData?.value;
    final stepsAsync = ref.watch(workflowStepsProvider(w.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(w.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/workflows'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Chip(label: Text(w.workflowType)),
              const SizedBox(width: 8),
              Chip(label: Text(w.status)),
              const SizedBox(width: 12),
              if (employee != null)
                Text(employee.fullName, style: const TextStyle(fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            Text(
              'Created ${w.createdAt.toIso8601String().substring(0, 10)}'
              '${w.completedAt != null ? '  ·  Completed ${w.completedAt!.toIso8601String().substring(0, 10)}' : ''}'
              '${w.cancelledAt != null ? '  ·  Cancelled ${w.cancelledAt!.toIso8601String().substring(0, 10)}' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            stepsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading steps: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (steps) =>
                  _StepsTimeline(workflow: w, steps: steps),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepsTimeline extends StatelessWidget {
  final WorkflowInstance workflow;
  final List<WorkflowStep> steps;
  const _StepsTimeline({required this.workflow, required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Text('No steps in this workflow.');
    }
    final done = steps
        .where((s) => s.status == 'COMPLETED' || s.status == 'SKIPPED')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$done / ${steps.length} steps complete',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        for (final s in steps)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    child: Text('${s.stepIndex + 1}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (s.description != null) ...[
                          const SizedBox(height: 2),
                          Text(s.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              )),
                        ],
                        const SizedBox(height: 6),
                        Row(children: [
                          Chip(label: Text(s.status)),
                          const SizedBox(width: 8),
                          Text(s.stepType,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              )),
                        ]),
                        if (s.completedAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Completed ${s.completedAt!.toIso8601String().substring(0, 16)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ],
                        if (s.remarks != null) ...[
                          const SizedBox(height: 4),
                          Text(s.remarks!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              )),
                        ],
                        // Action buttons land in Task 12.
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
