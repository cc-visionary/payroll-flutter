import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../core/money.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';

class ResponsibilityCardsScreen extends ConsumerWidget {
  const ResponsibilityCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(roleScorecardListProvider);
    final counts = ref.watch(scorecardEmployeeCountProvider).asData?.value ?? const {};
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.isHrOrAdmin ?? false;
    final canDelete = profile?.appRole == AppRole.SUPER_ADMIN;

    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Responsibility Cards'),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => context.push('/responsibility-cards/new'),
                icon: const Icon(Icons.add),
                label: const Text('New card'),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('No responsibility cards yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (c, i) => _CardTile(
                  card: rows[i],
                  employeeCount: counts[rows[i].id] ?? 0,
                  canManage: canManage,
                  canDelete: canDelete,
                  onOpen: () => context.push('/responsibility-cards/${rows[i].id}'),
                  onEdit: () => context.push('/responsibility-cards/${rows[i].id}/edit'),
                  onDelete: () => _confirmDelete(context, ref, rows[i], counts[rows[i].id] ?? 0),
                ),
              ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, WidgetRef ref, RoleScorecard card, int count) async {
    if (count > 0) {
      await showDialog(
        context: ctx,
        builder: (c) => AlertDialog(
          title: const Text('Cannot delete'),
          content: Text('Reassign the $count employee(s) on "${card.jobTitle}" first.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: const Text('Delete card?'),
            content: Text('This will delete "${card.jobTitle}". This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await ref.read(roleScorecardRepositoryProvider).delete(card.id);
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(scorecardEmployeeCountProvider);
  }
}

class _CardTile extends StatelessWidget {
  final RoleScorecard card;
  final int employeeCount;
  final bool canManage;
  final bool canDelete;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CardTile({
    required this.card,
    required this.employeeCount,
    required this.canManage,
    required this.canDelete,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.jobTitle,
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Tooltip(
                    message: '$employeeCount employee${employeeCount == 1 ? '' : 's'} assigned',
                    child: Chip(
                      avatar: const Icon(Icons.people, size: 16),
                      label: Text('$employeeCount'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (card.baseSalary != null)
                    Text('Base: ${Money.fmtPhp(card.baseSalary!)}', style: t.textTheme.bodyMedium),
                  const SizedBox(width: 8),
                  Chip(label: Text(card.wageType), visualDensity: VisualDensity.compact),
                  if (canManage)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (v) {
                        if (v == 'edit') onEdit();
                        if (v == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(leading: Icon(Icons.edit), title: Text('Edit')),
                        ),
                        if (canDelete)
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete, color: Colors.red),
                              title: Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Effective ${card.effectiveDate.toIso8601String().substring(0, 10)} '
                '• ${card.workHoursPerDay}h/day • ${card.workDaysPerWeek}',
                style: t.textTheme.bodySmall,
              ),
              if (card.missionStatement.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  card.missionStatement,
                  style: t.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
