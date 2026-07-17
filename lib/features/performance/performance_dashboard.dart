import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/status_colors.dart';
import '../../data/repositories/review_cycle_repository.dart';
import '../auth/profile_provider.dart';

class PerformanceDashboard extends ConsumerWidget {
  const PerformanceDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final dashboard = ref.watch(
      performanceDashboardProvider(profile.isHrOrAdmin),
    );
    return dashboard.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Could not load dashboard: $error')),
      data: (data) {
        final queue = data.reviews
            .where(
              (review) =>
                  !const {'FINALIZED', 'CANCELLED'}.contains(review.status),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
          children: [
            Text(
              profile.isHrOrAdmin
                  ? 'Company review progress'
                  : 'My team review progress',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              profile.isHrOrAdmin
                  ? 'Current review workload, development goals, and setup gaps.'
                  : 'Only employees allocated to you are included.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 32,
              runSpacing: 20,
              children: [
                _Metric(
                  label: 'Awaiting self-review',
                  value: data.awaitingSelfReview,
                  tone: data.awaitingSelfReview > 0
                      ? StatusTone.warning
                      : StatusTone.neutral,
                ),
                _Metric(
                  label: 'Manager review pending',
                  value: data.pendingManagerReview,
                  tone: data.pendingManagerReview > 0
                      ? StatusTone.info
                      : StatusTone.neutral,
                ),
                _Metric(
                  label: 'Ready for discussion',
                  value: data.readyForDiscussion,
                  tone: data.readyForDiscussion > 0
                      ? StatusTone.success
                      : StatusTone.neutral,
                ),
                _Metric(
                  label: 'Reviews overdue',
                  value: data.overdueReviews,
                  tone: data.overdueReviews > 0
                      ? StatusTone.danger
                      : StatusTone.neutral,
                ),
                _Metric(
                  label: 'Active goals',
                  value: data.activeGoals,
                  tone: StatusTone.neutral,
                ),
                _Metric(
                  label: 'Goals at risk',
                  value: data.goalsAtRisk,
                  tone: data.goalsAtRisk > 0
                      ? StatusTone.warning
                      : StatusTone.neutral,
                ),
              ],
            ),
            if (profile.isHrOrAdmin) ...[
              const Divider(height: 48),
              Text(
                'Setup attention',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _SetupIssue(
                    label: 'Employees without direct manager',
                    count: data.employeesWithoutManager,
                  ),
                  _SetupIssue(
                    label: 'Employees without Responsibility Card',
                    count: data.employeesWithoutResponsibilityCard,
                  ),
                ],
              ),
            ],
            const Divider(height: 48),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Work queue',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${queue.length} open review${queue.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (queue.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('No open reviews in your queue.')),
              )
            else
              ...queue.map(
                (review) => Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(review.employeeNameSnapshot),
                      subtitle: Text(
                        '${_label(review.reviewType)}  •  ${_date(review.reviewPeriodEnd)}',
                      ),
                      trailing: StatusChip(
                        label: _label(review.status),
                        tone: toneForStatusString(review.status),
                      ),
                      onTap: () =>
                          context.push('/performance/reviews/${review.id}'),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;
  final StatusTone tone;
  const _Metric({required this.label, required this.value, required this.tone});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(width: 10),
            StatusChip(label: value == 0 ? 'Clear' : 'Open', tone: tone),
          ],
        ),
      ],
    ),
  );
}

class _SetupIssue extends StatelessWidget {
  final String label;
  final int count;
  const _SetupIssue({required this.label, required this.count});
  @override
  Widget build(BuildContext context) => Container(
    width: 300,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text('$count', style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);
String _label(String value) => value
    .toLowerCase()
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
