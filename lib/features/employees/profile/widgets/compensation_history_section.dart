import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/status_colors.dart';
import '../../../../core/money.dart';
import '../../../../data/models/compensation_change.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/compensation_change_repository.dart';
import 'compensation_change_dialog.dart';
import 'delete_compensation_change_action.dart';

/// Maps a `compensation_changes.status` to the semantic tone used to render
/// its [StatusChip]. Pure — no BuildContext, no theme lookups.
StatusTone statusToneFor(String status) => switch (status) {
      'SCHEDULED' => StatusTone.warning,
      'APPLIED' => StatusTone.success,
      'CANCELLED' => StatusTone.danger,
      _ => StatusTone.warning,
    };

/// Title-cases a raw status string for display, e.g. `SCHEDULED` -> `Scheduled`.
String _titleCase(String s) =>
    s.isEmpty ? s : '${s[0]}${s.substring(1).toLowerCase()}';

/// Full history of compensation changes for an employee — every row the
/// employee has ever had (SCHEDULED, APPLIED, and CANCELLED), newest first.
/// Hosts the delete action, wired in a follow-up task.
class CompensationHistorySection extends ConsumerWidget {
  final Employee employee;
  final bool canManage;
  const CompensationHistorySection({
    super.key,
    required this.employee,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changesAsync =
        ref.watch(compensationChangesByEmployeeProvider(employee.id));

    return changesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Could not load compensation history: $e',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      data: (changes) => _HistoryCard(
        changes: changes,
        canManage: canManage,
        employee: employee,
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final List<CompensationChange> changes;
  final bool canManage;
  final Employee employee;
  const _HistoryCard({
    required this.changes,
    required this.canManage,
    required this.employee,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              'Compensation History',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: changes.isEmpty
                ? Text(
                    'No compensation changes recorded. Pay comes from the '
                    'role scorecard.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < changes.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 24, color: Theme.of(context).dividerColor),
                        _HistoryRow(
                          change: changes[i],
                          canManage: canManage,
                          employee: employee,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  final CompensationChange change;
  final bool canManage;
  final Employee employee;
  const _HistoryRow({
    required this.change,
    required this.canManage,
    required this.employee,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prev = change.prevBaseSalary == null
        ? '—'
        : Money.fmtPhp(change.prevBaseSalary!);
    final next = change.newBaseSalary == null
        ? '—'
        : Money.fmtPhp(change.newBaseSalary!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    compensationChangeTypeLabel(change.changeType),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    label: _titleCase(change.status),
                    tone: statusToneFor(change.status),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$prev → $next',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Effective ${change.effectiveDate.toIso8601String().substring(0, 10)}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Row(
                children: [
                  if (change.workflowId != null)
                    TextButton(
                      onPressed: () =>
                          context.go('/workflows/${change.workflowId}'),
                      child: const Text('Workflow'),
                    ),
                  if (change.documentId != null)
                    TextButton(
                      onPressed: () =>
                          context.go('/documents/view/${change.documentId}'),
                      child: const Text('Notice'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (canManage)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => runDeleteCompensationChange(
              ref: ref,
              context: context,
              employee: employee,
              change: change,
            ),
          ),
      ],
    );
  }
}
