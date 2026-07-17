import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/development_goal.dart';
import '../../data/repositories/review_cycle_repository.dart';
import '../auth/profile_provider.dart';

class ReviewCompletionScreen extends ConsumerStatefulWidget {
  final String reviewId;
  const ReviewCompletionScreen({super.key, required this.reviewId});

  @override
  ConsumerState<ReviewCompletionScreen> createState() =>
      _ReviewCompletionScreenState();
}

class _ReviewCompletionScreenState
    extends ConsumerState<ReviewCompletionScreen> {
  final _notes = TextEditingController();
  final _overrideReason = TextEditingController();
  final List<_GoalInput> _goals = [];
  DateTime _discussionDate = DateTime.now();
  bool _initialized = false;
  bool _working = false;

  @override
  void dispose() {
    _notes.dispose();
    _overrideReason.dispose();
    for (final goal in _goals) {
      goal.dispose();
    }
    super.dispose();
  }

  void _initialize(List<DevelopmentGoal> goals, DateTime? date, String? notes) {
    if (_initialized) return;
    _initialized = true;
    _discussionDate = date ?? DateTime.now();
    _notes.text = notes ?? '';
    // finalize_employee_review only accepts edits to NOT_STARTED goals. Once a
    // monthly check-in moves a goal to IN_PROGRESS, re-sending it raises "Only
    // not-started goals from this review can be edited" and a reopened review
    // can never be finalized again. Progressed goals are maintained from the
    // monthly check-in screen instead.
    _goals.addAll(
      goals
          .where((goal) => goal.status == 'NOT_STARTED')
          .map(_GoalInput.fromGoal),
    );
  }

  Future<void> _completeDiscussion() async {
    setState(() => _working = true);
    try {
      await ref
          .read(reviewCycleRepositoryProvider)
          .completeDiscussion(
            reviewId: widget.reviewId,
            discussionDate: _discussionDate,
            notes: _notes.text,
          );
      ref.invalidate(employeeReviewProvider(widget.reviewId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Discussion marked complete.')),
      );
    } catch (error) {
      _showError('Could not complete discussion', error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _finalize(bool discussionComplete) async {
    if (_goals.any((goal) => !goal.isValid)) {
      _showError(
        'Could not finalize',
        'Complete the title, target, and dates for every goal.',
      );
      return;
    }
    if (!discussionComplete && _overrideReason.text.trim().isEmpty) {
      _showError(
        'Could not finalize',
        'Enter an HR override reason when the discussion is incomplete.',
      );
      return;
    }
    setState(() => _working = true);
    try {
      await ref
          .read(reviewCycleRepositoryProvider)
          .finalizeReview(
            reviewId: widget.reviewId,
            goals: _goals.map((goal) => goal.toMap()).toList(),
            overrideReason: discussionComplete
                ? null
                : _overrideReason.text.trim(),
          );
      ref.invalidate(employeeReviewProvider(widget.reviewId));
      ref.invalidate(developmentGoalsForReviewProvider(widget.reviewId));
      if (!mounted) return;
      context.go('/performance/reviews/${widget.reviewId}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review finalized and locked.')),
      );
    } catch (error) {
      _showError('Could not finalize', error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(String prefix, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$prefix: $error')));
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(employeeReviewProvider(widget.reviewId));
    final goals = ref.watch(developmentGoalsForReviewProvider(widget.reviewId));
    final profile = ref.watch(userProfileProvider).value;
    if (review.isLoading || goals.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final error = review.error ?? goals.error;
    if (error != null) {
      return Scaffold(
        body: Center(child: Text('Could not load review: $error')),
      );
    }
    final value = review.value;
    if (value == null) {
      return const Scaffold(body: Center(child: Text('Review not found.')));
    }
    _initialize(
      goals.value ?? const [],
      value.discussionDate,
      value.discussionNotes,
    );
    final discussionComplete = value.discussionCompletedAt != null;
    final finalized = value.status == 'FINALIZED';
    final canCompleteDiscussion = value.status == 'READY_FOR_DISCUSSION';
    final canFinalize = profile?.isHrOrAdmin == true && !finalized;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.go('/performance/reviews/${widget.reviewId}'),
        ),
        title: Text('Complete ${value.employeeNameSnapshot} review'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
        children: [
          _StepHeader(
            number: '1',
            title: 'Review discussion',
            status: discussionComplete ? 'Completed' : 'Pending',
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 240,
                child: InkWell(
                  onTap: canCompleteDiscussion && !_working
                      ? () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: _discussionDate,
                            firstDate: value.reviewPeriodStart,
                            lastDate: DateTime.now().add(
                              const Duration(days: 30),
                            ),
                          );
                          if (selected != null && mounted) {
                            setState(() => _discussionDate = selected);
                          }
                        }
                      : null,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Discussion date',
                    ),
                    child: Text(_date(_discussionDate)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _notes,
                  enabled: canCompleteDiscussion && !_working,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Discussion notes (optional)',
                    hintText:
                        'Record agreements, clarifications, or employee comments.',
                  ),
                ),
              ),
            ],
          ),
          if (canCompleteDiscussion) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _working ? null : _completeDiscussion,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark discussion complete'),
              ),
            ),
          ],
          const Divider(height: 48),
          _StepHeader(
            number: '2',
            title: 'Next-quarter goals',
            status: '${_goals.length} of 2',
          ),
          const SizedBox(height: 6),
          Text(
            'Use one performance goal and one skill or cross-training goal when both are needed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ..._goals.asMap().entries.map(
            (entry) => _GoalEditor(
              input: entry.value,
              enabled: canFinalize && !_working,
              onRemove: () => setState(() {
                _goals.removeAt(entry.key).dispose();
              }),
            ),
          ),
          if (_goals.length < 2 && canFinalize)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _working
                    ? null
                    : () => setState(() => _goals.add(_GoalInput())),
                icon: const Icon(Icons.add),
                label: const Text('Add development goal'),
              ),
            ),
          const Divider(height: 48),
          _StepHeader(
            number: '3',
            title: 'HR finalization',
            status: finalized ? 'Locked' : 'Not finalized',
          ),
          const SizedBox(height: 16),
          if (!discussionComplete && canFinalize)
            TextField(
              controller: _overrideReason,
              enabled: !_working,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'HR override reason',
                helperText:
                    'Required only when finalizing without a completed discussion.',
              ),
            ),
          if (canFinalize) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _working
                    ? null
                    : () => _finalize(discussionComplete),
                icon: const Icon(Icons.lock_outline),
                label: Text(
                  _working ? 'Finalizing...' : 'Finalize and lock review',
                ),
              ),
            ),
          ] else if (!finalized)
            const Text('HR must finalize and lock this review.'),
        ],
      ),
    );
  }
}

class _GoalInput {
  String? id;
  String type = 'PERFORMANCE';
  final title = TextEditingController();
  final description = TextEditingController();
  final baseline = TextEditingController();
  final target = TextEditingController();
  final evidence = TextEditingController();
  DateTime startDate = DateTime.now();
  DateTime dueDate = DateTime.now().add(const Duration(days: 90));

  _GoalInput();
  factory _GoalInput.fromGoal(DevelopmentGoal goal) {
    final input = _GoalInput();
    input.id = goal.id;
    input.type = goal.goalType;
    input.title.text = goal.title;
    input.description.text = goal.description ?? '';
    input.baseline.text = goal.baseline ?? '';
    input.target.text = goal.target;
    input.evidence.text = goal.evidenceRequired ?? '';
    input.startDate = goal.startDate;
    input.dueDate = goal.dueDate;
    return input;
  }
  bool get isValid =>
      title.text.trim().isNotEmpty &&
      target.text.trim().isNotEmpty &&
      !dueDate.isBefore(startDate);
  Map<String, dynamic> toMap() => {
    'id': id,
    'goal_type': type,
    'title': title.text.trim(),
    'description': description.text.trim(),
    'baseline': baseline.text.trim(),
    'target': target.text.trim(),
    'start_date': _date(startDate),
    'due_date': _date(dueDate),
    'trainer_id': null,
    'evidence_required': evidence.text.trim(),
  };
  void dispose() {
    title.dispose();
    description.dispose();
    baseline.dispose();
    target.dispose();
    evidence.dispose();
  }
}

class _GoalEditor extends StatefulWidget {
  final _GoalInput input;
  final bool enabled;
  final VoidCallback onRemove;
  const _GoalEditor({
    required this.input,
    required this.enabled,
    required this.onRemove,
  });
  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  Future<void> _pickDate(bool start) async {
    final current = start ? widget.input.startDate : widget.input.dueDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        widget.input.startDate = selected;
        if (widget.input.dueDate.isBefore(selected)) {
          widget.input.dueDate = selected;
        }
      } else {
        widget.input.dueDate = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: widget.input.type,
                decoration: const InputDecoration(labelText: 'Goal type'),
                items: _goalTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_label(type)),
                      ),
                    )
                    .toList(),
                onChanged: widget.enabled
                    ? (value) => setState(() => widget.input.type = value!)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: widget.input.title,
                enabled: widget.enabled,
                decoration: const InputDecoration(labelText: 'Goal title'),
              ),
            ),
            IconButton(
              onPressed: widget.enabled ? widget.onRemove : null,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove goal',
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.input.description,
          enabled: widget.enabled,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.input.baseline,
                enabled: widget.enabled,
                decoration: const InputDecoration(labelText: 'Baseline'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.input.target,
                enabled: widget.enabled,
                decoration: const InputDecoration(labelText: 'Target'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.input.evidence,
                enabled: widget.enabled,
                decoration: const InputDecoration(
                  labelText: 'Evidence required',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Start date',
                value: widget.input.startDate,
                enabled: widget.enabled,
                onTap: () => _pickDate(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateField(
                label: 'Due date',
                value: widget.input.dueDate,
                enabled: widget.enabled,
                onTap: () => _pickDate(false),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final bool enabled;
  final VoidCallback onTap;
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, enabled: enabled),
      child: Text(_date(value)),
    ),
  );
}

class _StepHeader extends StatelessWidget {
  final String number;
  final String title;
  final String status;
  const _StepHeader({
    required this.number,
    required this.title,
    required this.status,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(radius: 14, child: Text(number)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      Text(status, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

const _goalTypes = [
  'PERFORMANCE',
  'SKILL_DEVELOPMENT',
  'CROSS_TRAINING',
  'BEHAVIORAL_IMPROVEMENT',
  'CAREER_READINESS',
  'COMPLIANCE',
];
String _date(DateTime value) => value.toIso8601String().substring(0, 10);
String _label(String value) => value
    .toLowerCase()
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
