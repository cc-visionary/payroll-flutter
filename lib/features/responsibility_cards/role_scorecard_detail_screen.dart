import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../core/money.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';

class RoleScorecardDetailScreen extends ConsumerWidget {
  final String cardId;
  const RoleScorecardDetailScreen({super.key, required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(roleScorecardListProvider);
    final counts = ref.watch(scorecardEmployeeCountProvider).asData?.value ?? const {};
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.isHrOrAdmin ?? false;
    final canDelete = profile?.appRole == AppRole.SUPER_ADMIN;

    final mobile = isMobile(context);
    return Scaffold(
      drawer: mobile ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Responsibility Card'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/responsibility-cards'),
        ),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: mobile
                  ? IconButton(
                      tooltip: 'Edit',
                      onPressed: () => context
                          .push('/responsibility-cards/$cardId/edit'),
                      icon: const Icon(Icons.edit),
                    )
                  : FilledButton.icon(
                      onPressed: () => context
                          .push('/responsibility-cards/$cardId/edit'),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
            ),
          if (canDelete)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'delete') {
                  final card = async.asData?.value
                      .where((c) => c.id == cardId)
                      .firstOrNull;
                  if (card == null) return;
                  _confirmDelete(context, ref, card, counts[cardId] ?? 0);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
        ),
        data: (rows) {
          final card = rows.where((c) => c.id == cardId).firstOrNull;
          if (card == null) {
            return const Center(child: Text('Card not found.'));
          }
          final count = counts[card.id] ?? 0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _DetailBody(card: card, employeeCount: count),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext ctx,
    WidgetRef ref,
    RoleScorecard card,
    int count,
  ) async {
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
    if (ctx.mounted) ctx.go('/responsibility-cards');
  }
}

class _DetailBody extends StatelessWidget {
  final RoleScorecard card;
  final int employeeCount;
  const _DetailBody({required this.card, required this.employeeCount});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final mobile = isMobile(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(mobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.jobTitle,
              style: t.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tooltip(
                  message:
                      '$employeeCount employee${employeeCount == 1 ? '' : 's'} assigned',
                  child: Chip(
                    avatar: const Icon(Icons.people, size: 16),
                    label: Text('$employeeCount'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (card.baseSalary != null)
                  Text('Base: ${Money.fmtPhp(card.baseSalary!)}',
                      style: t.textTheme.bodyMedium),
                Chip(
                    label: Text(card.wageType),
                    visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Effective ${card.effectiveDate.toIso8601String().substring(0, 10)} '
              '• ${card.workHoursPerDay}h/day • ${card.workDaysPerWeek}',
              style: t.textTheme.bodySmall,
            ),
            if (card.missionStatement.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(card.missionStatement, style: t.textTheme.bodyMedium),
            ],
            if (card.responsibilities.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Responsibilities',
                style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final area in card.responsibilities)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ${area.area}', style: const TextStyle(fontWeight: FontWeight.w500)),
                      for (final task in area.tasks)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 2),
                          child: Text('– $task', style: t.textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
            ],
            if (card.kpis.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'KPIs',
                style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in card.kpis)
                    Chip(
                      label: Text('${k.metric} (${k.frequency})'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
