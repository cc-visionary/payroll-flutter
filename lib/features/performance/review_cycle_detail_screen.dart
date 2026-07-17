import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/status_colors.dart';
import '../../data/models/employee.dart';
import '../../data/models/employee_review.dart';
import '../../data/models/review_cycle.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/review_cycle_repository.dart';
import 'review_eligibility.dart';

class ReviewCycleDetailScreen extends ConsumerStatefulWidget {
  final String cycleId;
  const ReviewCycleDetailScreen({super.key, required this.cycleId});

  @override
  ConsumerState<ReviewCycleDetailScreen> createState() =>
      _ReviewCycleDetailState();
}

class _ReviewCycleDetailState extends ConsumerState<ReviewCycleDetailScreen> {
  final Set<String> _selected = {};
  bool _generating = false;
  bool _activating = false;
  bool _retrying = false;

  Future<void> _retryFailed() async {
    setState(() => _retrying = true);
    try {
      final result = await ref
          .read(reviewCycleRepositoryProvider)
          .retryFailedSelfReviews(widget.cycleId);
      ref.invalidate(selfReviewRequestsForCycleProvider(widget.cycleId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Retry complete. Sent ${result.sent}; ${result.failed} still failed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Retry failed: $error')));
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _activate(ReviewCycle cycle, int reviewCount) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Activate review cycle?'),
            content: Text(
              'This will queue self-review requests for $reviewCount '
              'employee${reviewCount == 1 ? '' : 's'} and send them through Lark.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Activate and send'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _activating = true);
    try {
      final result = await ref
          .read(reviewCycleRepositoryProvider)
          .activateCycle(cycle.id);
      ref.invalidate(reviewCycleProvider(widget.cycleId));
      ref.invalidate(reviewCycleListProvider);
      ref.invalidate(employeeReviewsForCycleProvider(widget.cycleId));
      ref.invalidate(selfReviewRequestsForCycleProvider(widget.cycleId));
      if (!mounted) return;
      final detail = result.failed == 0
          ? 'Activated. Sent ${result.sent} of ${result.queued} self-review requests.'
          : 'Activated. Sent ${result.sent}; ${result.failed} require retry.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(detail)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Activation failed: $error')));
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _generate(
    List<Employee> employees,
    Set<String> generatedIds,
  ) async {
    final targets = employees.where(
      (employee) =>
          _selected.contains(employee.id) &&
          !generatedIds.contains(employee.id) &&
          reviewEligibilityIssue(employee) == null,
    );
    if (targets.isEmpty) return;
    setState(() => _generating = true);
    var created = 0;
    final failures = <String>[];
    for (final employee in targets) {
      try {
        await ref
            .read(reviewCycleRepositoryProvider)
            .generateEmployeeReview(
              cycleId: widget.cycleId,
              employeeId: employee.id,
            );
        created++;
      } catch (error) {
        failures.add('${employee.fullName}: $error');
      }
    }
    ref.invalidate(employeeReviewsForCycleProvider(widget.cycleId));
    ref.invalidate(reviewCycleProvider(widget.cycleId));
    if (!mounted) return;
    setState(() {
      _generating = false;
      _selected.clear();
    });
    final message = failures.isEmpty
        ? 'Generated $created employee review${created == 1 ? '' : 's'}.'
        : 'Generated $created. ${failures.length} failed: ${failures.join(' | ')}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cycle = ref.watch(reviewCycleProvider(widget.cycleId));
    final employees = ref.watch(
      employeeListProvider(const EmployeeListQuery(includeArchived: false)),
    );
    final reviews = ref.watch(employeeReviewsForCycleProvider(widget.cycleId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go('/performance/review-cycles'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Review cycle'),
      ),
      body: cycle.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (value) {
          if (value == null) {
            return const Center(child: Text('Cycle not found.'));
          }
          return employees.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
            data: (employeeRows) => reviews.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
              data: (reviewRows) => _body(value, employeeRows, reviewRows),
            ),
          );
        },
      ),
    );
  }

  Widget _body(
    ReviewCycle cycle,
    List<Employee> employees,
    List<EmployeeReview> reviews,
  ) {
    final requests =
        ref
            .watch(selfReviewRequestsForCycleProvider(widget.cycleId))
            .asData
            ?.value ??
        const [];
    final sentCount = requests
        .where((request) => request.status == 'SENT')
        .length;
    final failedCount = requests
        .where((request) => request.status == 'FAILED')
        .length;
    final generatedByEmployee = {
      for (final review in reviews) review.employeeId: review,
    };
    final eligible = employees
        .where((employee) => reviewEligibilityIssue(employee) == null)
        .toList();
    final availableEligible = eligible
        .where(
          (employee) =>
              cycle.status == 'DRAFT' &&
              !generatedByEmployee.containsKey(employee.id),
        )
        .toList();
    final allSelected =
        availableEligible.isNotEmpty &&
        availableEligible.every((employee) => _selected.contains(employee.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CycleHeader(
          cycle: cycle,
          generatedCount: reviews.length,
          sentCount: sentCount,
          failedCount: failedCount,
          activating: _activating,
          retrying: _retrying,
          onRetryFailed: failedCount > 0 ? _retryFailed : null,
          onActivate: cycle.status == 'DRAFT' && reviews.isNotEmpty
              ? () => _activate(cycle, reviews.length)
              : null,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Employees',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select employees to create immutable role-standard snapshots.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: availableEligible.isEmpty
                    ? null
                    : () => setState(() {
                        if (allSelected) {
                          _selected.removeAll(
                            availableEligible.map((employee) => employee.id),
                          );
                        } else {
                          _selected.addAll(
                            availableEligible.map((employee) => employee.id),
                          );
                        }
                      }),
                child: Text(
                  allSelected ? 'Clear selection' : 'Select all eligible',
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _generating || _selected.isEmpty
                    ? null
                    : () => _generate(
                        employees,
                        generatedByEmployee.keys.toSet(),
                      ),
                icon: _generating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add_check),
                label: Text(
                  _generating
                      ? 'Generating...'
                      : 'Generate reviews (${_selected.length})',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: employees.isEmpty
              ? const Center(child: Text('No employees found.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: employees.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final employee = employees[index];
                    final issue = reviewEligibilityIssue(employee);
                    final review = generatedByEmployee[employee.id];
                    final selectable =
                        cycle.status == 'DRAFT' &&
                        issue == null &&
                        review == null;
                    return CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: review != null || _selected.contains(employee.id),
                      onChanged: selectable
                          ? (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(employee.id);
                              } else {
                                _selected.remove(employee.id);
                              }
                            })
                          : null,
                      title: Row(
                        children: [
                          Expanded(child: Text(employee.fullName)),
                          if (review != null)
                            TextButton(
                              onPressed: () => context.push(
                                '/performance/reviews/${review.id}',
                              ),
                              child: const Text('Open review'),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        issue ?? employee.jobTitle ?? 'Role title not set',
                        style: issue == null
                            ? null
                            : TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                      ),
                      secondary: review == null
                          ? issue == null
                                ? const StatusChip(
                                    label: 'Eligible',
                                    tone: StatusTone.success,
                                  )
                                : const StatusChip(
                                    label: 'Needs setup',
                                    tone: StatusTone.warning,
                                  )
                          : StatusChip(
                              label: _label(review.status),
                              tone: toneForStatusString(review.status),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CycleHeader extends StatelessWidget {
  final ReviewCycle cycle;
  final int generatedCount;
  final int sentCount;
  final int failedCount;
  final bool activating;
  final bool retrying;
  final VoidCallback? onActivate;
  final VoidCallback? onRetryFailed;
  const _CycleHeader({
    required this.cycle,
    required this.generatedCount,
    required this.sentCount,
    required this.failedCount,
    required this.activating,
    required this.retrying,
    required this.onActivate,
    required this.onRetryFailed,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Wrap(
      spacing: 24,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cycle.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              StatusChip(
                label: _label(cycle.status),
                tone: toneForStatusString(cycle.status),
              ),
            ],
          ),
        ),
        _Fact(label: 'Type', value: _label(cycle.reviewType)),
        _Fact(
          label: 'Review period',
          value: '${_date(cycle.periodStart)} to ${_date(cycle.periodEnd)}',
        ),
        _Fact(label: 'Self-review due', value: _date(cycle.selfReviewDueDate)),
        _Fact(label: 'Reviews generated', value: '$generatedCount'),
        if (cycle.status != 'DRAFT')
          _Fact(label: 'Lark requests sent', value: '$sentCount'),
        if (failedCount > 0)
          _Fact(label: 'Delivery failed', value: '$failedCount'),
        if (failedCount > 0)
          OutlinedButton.icon(
            onPressed: retrying ? null : onRetryFailed,
            icon: retrying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(retrying ? 'Retrying...' : 'Retry failed'),
          ),
        if (cycle.status == 'DRAFT')
          FilledButton.icon(
            onPressed: activating ? null : onActivate,
            icon: activating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(activating ? 'Activating...' : 'Activate and send'),
          ),
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
      Text(value, style: Theme.of(context).textTheme.bodyMedium),
    ],
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
