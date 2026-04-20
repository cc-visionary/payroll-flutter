import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/money.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/role_scorecard.dart';
import '../../../../data/repositories/role_scorecard_repository.dart';
import '../../../auth/profile_provider.dart';
import '../providers.dart';

class RoleTab extends ConsumerWidget {
  final Employee employee;
  const RoleTab({super.key, required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.canManageEmployees ?? false;

    if (employee.roleScorecardId == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: _EmptyCard(
          message: 'No role assigned yet.',
          actionLabel: canManage ? 'Assign Role' : null,
          onAction: canManage
              ? () => context.push('/employees/${employee.id}/edit')
              : null,
        ),
      );
    }

    final cardsAsync = ref.watch(roleScorecardListProvider);
    return cardsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (cards) {
        final card =
            cards.where((c) => c.id == employee.roleScorecardId).firstOrNull;
        if (card == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: _EmptyCard(message: 'Assigned role scorecard is missing.'),
          );
        }
        final deptAsync = card.departmentId == null
            ? const AsyncValue<String?>.data(null)
            : ref.watch(departmentNameProvider(card.departmentId!));
        return _RoleDetail(
          employee: employee,
          card: card,
          departmentName: deptAsync.asData?.value,
          canManage: canManage,
        );
      },
    );
  }
}

class _RoleDetail extends StatelessWidget {
  final Employee employee;
  final RoleScorecard card;
  final String? departmentName;
  final bool canManage;
  const _RoleDetail({
    required this.employee,
    required this.card,
    required this.departmentName,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _Section(
          title: 'Current Role',
          trailing: canManage
              ? FilledButton(
                  onPressed: () =>
                      context.push('/employees/${employee.id}/edit'),
                  child: const Text('Change Role'),
                )
              : null,
          subtitle: card.jobTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(builder: (ctx, c) {
                final cardWidth = c.maxWidth >= 920
                    ? (c.maxWidth - 2 * 12) / 3
                    : c.maxWidth >= 600
                        ? (c.maxWidth - 12) / 2
                        : c.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'POSITION',
                        value: card.jobTitle,
                        subtitle: departmentName,
                        bg: const Color(0xFFEFF6FF),
                        fg: const Color(0xFF1D4ED8),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'BASE SALARY',
                        value: card.baseSalary == null
                            ? '—'
                            : Money.fmtPhp(card.baseSalary!),
                        subtitle: card.wageType.toLowerCase(),
                        bg: const Color(0xFFECFDF5),
                        fg: const Color(0xFF047857),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TintedCard(
                        label: 'WORK SCHEDULE',
                        value: '${card.workHoursPerDay}h / day',
                        subtitle: card.workDaysPerWeek,
                        bg: const Color(0xFFF5F3FF),
                        fg: const Color(0xFF6D28D9),
                      ),
                    ),
                  ],
                );
              }),
              if (card.salaryRangeMin != null ||
                  card.salaryRangeMax != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Salary Range for this Role',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _rangeText(card),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
              if (card.missionStatement.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Mission Statement',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    card.missionStatement,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
              if (card.responsibilities.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Key Responsibilities',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final area in card.responsibilities)
                  _AreaBlock(area: area),
              ],
              if (card.kpis.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'KPIs',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
      ],
    );
  }

  String _rangeText(RoleScorecard c) {
    final lo = c.salaryRangeMin == null ? '—' : Money.fmtPhp(c.salaryRangeMin!);
    final hi = c.salaryRangeMax == null ? '—' : Money.fmtPhp(c.salaryRangeMax!);
    return '$lo - $hi';
  }
}

class _TintedCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color? bg;
  final Color? fg;
  const _TintedCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg ?? Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: bg == null ? Theme.of(context).dividerColor : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg ?? Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: fg?.withValues(alpha: 0.8) ??
                    Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AreaBlock extends StatelessWidget {
  final ResponsibilityArea area;
  const _AreaBlock({required this.area});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            area.area,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final t in area.tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Text(
                      t,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  const _Section({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
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
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyCard({required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
