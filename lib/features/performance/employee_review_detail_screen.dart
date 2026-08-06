import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/status_colors.dart';
import '../../app/tokens.dart';
import '../../data/models/self_review_submission.dart';
import '../../data/repositories/review_cycle_repository.dart';
import '../auth/profile_provider.dart';

class EmployeeReviewDetailScreen extends ConsumerWidget {
  final String reviewId;
  const EmployeeReviewDetailScreen({super.key, required this.reviewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(employeeReviewProvider(reviewId));
    final profile = ref.watch(userProfileProvider).value;
    final status = review.value?.status;
    // Mirrors can_manage_employee_review() in 20260717000006: HR/admin, or the
    // employee's own direct manager. The RPC enforces this regardless; gating
    // here keeps us from offering an action the backend will reject.
    final canEvaluate =
        profile != null &&
        (profile.isHrOrAdmin ||
            (profile.employeeId != null &&
                profile.employeeId == review.value?.directManagerId)) &&
        status != null &&
        status != 'FINALIZED' &&
        status != 'CANCELLED';
    return Scaffold(
      appBar: AppBar(
        // The review routes are flat siblings, so arriving here via context.go
        // (from evaluate/complete/check-in) leaves nothing to pop.
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/performance'),
        ),
        title: const Text('Performance review'),
        actions: [
          if (review.value?.status == 'FINALIZED')
            TextButton.icon(
              onPressed: () => context.push(
                '/performance/reviews/$reviewId/monthly-check-in',
              ),
              icon: const Icon(Icons.event_note_outlined),
              label: const Text('Monthly check-in'),
            ),
          if (review.value?.status == 'FINALIZED' &&
              profile?.isHrOrAdmin == true)
            TextButton.icon(
              onPressed: () => _reopen(context, ref),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Reopen'),
            )
          else if (review.value?.status == 'READY_FOR_DISCUSSION' ||
              review.value?.status == 'DISCUSSION_COMPLETED')
            TextButton.icon(
              onPressed: () =>
                  context.push('/performance/reviews/$reviewId/complete'),
              icon: const Icon(Icons.task_alt),
              label: const Text('Complete review'),
            ),
          if (review.value != null)
            TextButton.icon(
              onPressed: () => context.push(
                '/responsibility-cards/${review.value!.responsibilityCardId}/pdf',
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Role reference'),
            ),
          const SizedBox(width: 8),
          if (canEvaluate)
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: FilledButton.icon(
                onPressed: () =>
                    context.push('/performance/reviews/$reviewId/evaluate'),
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Manager evaluation'),
              ),
            ),
        ],
      ),
      body: review.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load review: $error')),
        data: (value) {
          if (value == null) {
            return const Center(child: Text('Review not found.'));
          }
          final submissions = ref.watch(
            selfReviewSubmissionsProvider(reviewId),
          );
          final kpis = ref.watch(reviewKpisProvider(reviewId));
          final skills = ref.watch(reviewSkillsProvider(reviewId));
          final managerReview = ref.watch(managerReviewProvider(reviewId));
          final goals = ref.watch(developmentGoalsForReviewProvider(reviewId));
          final checkins = ref.watch(
            monthlyDevelopmentCheckinsProvider(reviewId),
          );
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                spacing: 32,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value.employeeNameSnapshot,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        StatusChip(
                          label: _label(value.status),
                          tone: toneForStatusString(value.status),
                        ),
                      ],
                    ),
                  ),
                  _Fact(label: 'Type', value: _label(value.reviewType)),
                  _Fact(
                    label: 'Review period',
                    value:
                        '${_date(value.reviewPeriodStart)} to ${_date(value.reviewPeriodEnd)}',
                  ),
                  _Fact(
                    label: 'Responsibility Card',
                    value: 'Version ${value.responsibilityCardVersion}',
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _Section(
                title: 'Employee self-review',
                subtitle: 'Synced from Lark. Responses are read-only.',
                child: submissions.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('Could not load response: $error'),
                  data: (rows) => _SelfReviewContent(rows: rows),
                ),
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'KPI standards',
                subtitle: 'Snapshot from the Responsibility Card.',
                child: kpis.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('Could not load KPIs: $error'),
                  data: (rows) => rows.isEmpty
                      ? const Text('No KPI standards were included.')
                      : Column(
                          children: rows
                              .map(
                                (item) => _StandardRow(
                                  title: item.kpiName,
                                  description: [
                                    if (item.measurementUnit?.isNotEmpty ==
                                        true)
                                      'Measurement: ${item.measurementUnit}',
                                    if (item.targetValue?.isNotEmpty == true)
                                      'Target: ${item.targetValue}',
                                  ].join('  •  '),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'Skills and behavioral expectations',
                subtitle:
                    'Descriptions are preserved from the review snapshot.',
                child: skills.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('Could not load standards: $error'),
                  data: (rows) => rows.isEmpty
                      ? const Text('No skill standards were included.')
                      : Column(
                          children: rows
                              .map(
                                (item) => _StandardRow(
                                  title: item.skillName,
                                  description: item.skillDescription ?? '',
                                  label: item.skillCategory == 'BEHAVIORAL'
                                      ? 'Behavioral expectation'
                                      : 'Required skill',
                                ),
                              )
                              .toList(),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'Manager review',
                subtitle: 'Submitted evaluation and recommendation.',
                child: managerReview.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) =>
                      Text('Could not load manager review: $error'),
                  data: (row) => row == null
                      ? const Text('The manager evaluation is not submitted.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Response(
                              label: 'Overall feedback',
                              value: row.overallFeedback,
                            ),
                            _Response(
                              label: 'Performance concerns',
                              value: row.performanceConcerns,
                            ),
                            _Response(
                              label: 'Support from manager',
                              value: row.supportManagerWillProvide,
                            ),
                            _Response(
                              label: 'Recommended outcome',
                              value: row.recommendedOutcome == null
                                  ? null
                                  : _label(row.recommendedOutcome!),
                            ),
                            if (row.strengths.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Strengths',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              ...row.strengths.map(
                                (item) => Text('• ${item['title']}'),
                              ),
                            ],
                            if (row.developmentAreas.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Development areas',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              ...row.developmentAreas.map(
                                (item) => Text('• ${item['area']}'),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'Development goals',
                subtitle: 'Goals created from this review.',
                child: goals.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('Could not load goals: $error'),
                  data: (rows) => rows.isEmpty
                      ? const Text('No development goals created yet.')
                      : Column(
                          children: rows
                              .map(
                                (goal) => _StandardRow(
                                  title: goal.title,
                                  description:
                                      '${_label(goal.goalType)}  •  Target: ${goal.target}  •  Due: ${_date(goal.dueDate)}',
                                  label: '${goal.progress}%',
                                ),
                              )
                              .toList(),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'Monthly check-ins',
                subtitle: 'Progress conversations linked to these goals.',
                child: checkins.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) =>
                      Text('Could not load monthly check-ins: $error'),
                  data: (rows) => rows.isEmpty
                      ? const Text('No monthly development check-ins yet.')
                      : Column(
                          children: rows
                              .map(
                                (checkin) => _StandardRow(
                                  title:
                                      '${_date(checkin.checkinDate)}  •  ${_label(checkin.generalStatus)}',
                                  description:
                                      'Next action: ${checkin.agreedNextAction}  •  Due: ${_date(checkin.actionDueDate)}',
                                  label:
                                      '${checkin.goalUpdates.length} goal update${checkin.goalUpdates.length == 1 ? '' : 's'}',
                                ),
                              )
                              .toList(),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reopen finalized review?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Explain why this review must be reopened.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Reopen review'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await ref
          .read(reviewCycleRepositoryProvider)
          .reopenReview(reviewId: reviewId, reason: reason.trim());
      // Reopening moves the review out of FINALIZED, which changes every list
      // that renders its status. Those screens stay mounted underneath this one
      // (they were pushed, not replaced), so they need explicit invalidation or
      // they keep showing "Finalized".
      ref.invalidate(employeeReviewProvider(reviewId));
      ref.invalidate(employeeReviewsForCycleProvider);
      ref.invalidate(employeeReviewsForEmployeeProvider);
      ref.invalidate(performanceDashboardProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Review reopened.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reopen review: $error')),
      );
    }
  }
}

class _Response extends StatelessWidget {
  final String label;
  final String? value;
  const _Response({required this.label, this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value?.trim().isNotEmpty == true ? value! : 'Not provided'),
      ],
    ),
  );
}

class _SelfReviewContent extends StatelessWidget {
  final List<SelfReviewSubmission> rows;
  const _SelfReviewContent({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text('The employee has not submitted a self-review yet.');
    }
    final active = rows.where((row) => row.isActive).firstOrNull ?? rows.first;
    final fields = <(String, String?)>[
      ('Accomplishments', active.accomplishments),
      ('Challenges', active.challenges),
      ('Learnings', active.learnings),
      ('Desired development area', active.desiredDevelopmentArea),
      ('Support needed', active.supportNeeded),
      ('Additional comments', active.additionalComments),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Submitted ${_dateTime(active.submittedAt)}  •  Form version ${active.formVersion}  •  Response ${active.versionNumber} of ${rows.length}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        ...fields.map(
          (field) => Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.$1, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 5),
                Text(
                  field.$2?.trim().isNotEmpty == true
                      ? field.$2!
                      : 'No response',
                ),
              ],
            ),
          ),
        ),
        if (active.attachments.isNotEmpty)
          Text(
            '${active.attachments.length} attachment reference${active.attachments.length == 1 ? '' : 's'} synced.',
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(LuxiumRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 20),
        child,
      ],
    ),
  );
}

class _StandardRow extends StatelessWidget {
  final String title;
  final String description;
  final String? label;
  const _StandardRow({
    required this.title,
    required this.description,
    this.label,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 16),
          Text(label!, style: Theme.of(context).textTheme.labelSmall),
        ],
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 4),
      Text(value),
    ],
  );
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);
String _dateTime(DateTime value) => value.toLocal().toString().substring(0, 16);
String _label(String value) => value
    .toLowerCase()
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
