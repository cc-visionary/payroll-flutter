import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/development_goal.dart';
import '../../data/repositories/review_cycle_repository.dart';

class MonthlyDevelopmentCheckinScreen extends ConsumerStatefulWidget {
  final String reviewId;
  const MonthlyDevelopmentCheckinScreen({super.key, required this.reviewId});

  @override
  ConsumerState<MonthlyDevelopmentCheckinScreen> createState() =>
      _MonthlyDevelopmentCheckinScreenState();
}

class _MonthlyDevelopmentCheckinScreenState
    extends ConsumerState<MonthlyDevelopmentCheckinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _wentWell = TextEditingController();
  final _attention = TextEditingController();
  final _support = TextEditingController();
  final _nextAction = TextEditingController();
  final Map<String, _GoalProgressInput> _goalInputs = {};
  DateTime _checkinDate = DateTime.now();
  DateTime _actionDueDate = DateTime.now().add(const Duration(days: 30));
  String _generalStatus = 'ON_TRACK';
  String? _actionOwnerId;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _wentWell.dispose();
    _attention.dispose();
    _support.dispose();
    _nextAction.dispose();
    for (final input in _goalInputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  void _initialize(List<DevelopmentGoal> goals, String employeeId) {
    if (_initialized) return;
    _initialized = true;
    _actionOwnerId = employeeId;
    for (final goal in goals.where((goal) => goal.status != 'CANCELLED')) {
      _goalInputs[goal.id] = _GoalProgressInput(goal);
    }
  }

  Future<void> _pickDate({required bool actionDue}) async {
    final current = actionDue ? _actionDueDate : _checkinDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (actionDue) {
        _actionDueDate = selected;
      } else {
        _checkinDate = selected;
        if (_actionDueDate.isBefore(selected)) {
          _actionDueDate = selected.add(const Duration(days: 7));
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_actionDueDate.isBefore(_checkinDate)) {
      _error('The action due date cannot be before the check-in date.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(reviewCycleRepositoryProvider)
          .recordMonthlyCheckin(
            reviewId: widget.reviewId,
            checkinDate: _checkinDate,
            whatWentWell: _wentWell.text,
            needsAttention: _attention.text,
            supportNeeded: _support.text,
            agreedNextAction: _nextAction.text,
            actionOwnerId: _actionOwnerId!,
            actionDueDate: _actionDueDate,
            generalStatus: _generalStatus,
            goalUpdates: _goalInputs.entries
                .map((entry) => entry.value.toMap(entry.key))
                .toList(),
          );
      ref.invalidate(monthlyDevelopmentCheckinsProvider(widget.reviewId));
      ref.invalidate(developmentGoalsForReviewProvider(widget.reviewId));
      if (!mounted) return;
      context.go('/performance/reviews/${widget.reviewId}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monthly check-in completed.')),
      );
    } catch (error) {
      _error('Could not complete check-in: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(employeeReviewProvider(widget.reviewId));
    final goals = ref.watch(developmentGoalsForReviewProvider(widget.reviewId));
    if (review.isLoading || goals.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final error = review.error ?? goals.error;
    if (error != null) {
      return Scaffold(
        body: Center(child: Text('Could not load check-in: $error')),
      );
    }
    final value = review.value;
    if (value == null) {
      return const Scaffold(body: Center(child: Text('Review not found.')));
    }
    final goalRows = goals.value ?? const [];
    _initialize(goalRows, value.employeeId);
    final eligible = value.status == 'FINALIZED';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.go('/performance/reviews/${widget.reviewId}'),
        ),
        title: Text('Monthly check-in: ${value.employeeNameSnapshot}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: FilledButton.icon(
              onPressed: _saving || !eligible ? null : _submit,
              icon: const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Complete check-in'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            if (!eligible)
              const _Notice(
                text:
                    'Monthly development check-ins require a finalized review.',
              ),
            const _Heading(
              title: 'Progress conversation',
              subtitle:
                  'Capture only what changed since the last review or check-in.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Check-in date',
                    value: _checkinDate,
                    enabled: eligible && !_saving,
                    onTap: () => _pickDate(actionDue: false),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _generalStatus,
                    decoration: const InputDecoration(
                      labelText: 'General status',
                    ),
                    items: _generalStatuses
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(_label(status)),
                          ),
                        )
                        .toList(),
                    onChanged: eligible && !_saving
                        ? (value) => setState(() => _generalStatus = value!)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _wentWell,
                    enabled: eligible && !_saving,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'What went well',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _attention,
                    enabled: eligible && !_saving,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'What needs attention',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _support,
                    enabled: eligible && !_saving,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Support needed',
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 48),
            const _Heading(
              title: 'Goal progress',
              subtitle: 'Update the active goals created from this review.',
            ),
            const SizedBox(height: 12),
            if (_goalInputs.isEmpty)
              const Text('No development goals are linked to this review.')
            else
              ..._goalInputs.values.map(
                (input) => _GoalProgressEditor(
                  input: input,
                  enabled: eligible && !_saving,
                ),
              ),
            const Divider(height: 48),
            const _Heading(
              title: 'Next action',
              subtitle:
                  'Agree on one concrete action before the next check-in.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nextAction,
              enabled: eligible && !_saving,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Agreed next action',
              ),
              validator: (value) => value?.trim().isEmpty == true
                  ? 'One next action is required'
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _actionOwnerId,
                    decoration: const InputDecoration(
                      labelText: 'Action owner',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: value.employeeId,
                        child: Text(value.employeeNameSnapshot),
                      ),
                      DropdownMenuItem(
                        value: value.directManagerId,
                        child: const Text('Direct manager'),
                      ),
                    ],
                    onChanged: eligible && !_saving
                        ? (owner) => setState(() => _actionOwnerId = owner)
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _DateField(
                    label: 'Action due date',
                    value: _actionDueDate,
                    enabled: eligible && !_saving,
                    onTap: () => _pickDate(actionDue: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalProgressInput {
  final DevelopmentGoal goal;
  final note = TextEditingController();
  double progress;
  String status;
  _GoalProgressInput(this.goal)
    : progress = goal.progress.toDouble(),
      status = goal.status == 'NOT_STARTED' ? 'IN_PROGRESS' : goal.status;

  Map<String, dynamic> toMap(String goalId) => {
    'goal_id': goalId,
    'progress': progress.round(),
    'goal_status': progress.round() == 100 ? 'COMPLETED' : status,
    'progress_note': note.text.trim(),
  };
  void dispose() => note.dispose();
}

class _GoalProgressEditor extends StatefulWidget {
  final _GoalProgressInput input;
  final bool enabled;
  const _GoalProgressEditor({required this.input, required this.enabled});
  @override
  State<_GoalProgressEditor> createState() => _GoalProgressEditorState();
}

class _GoalProgressEditorState extends State<_GoalProgressEditor> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.input.goal.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text('${widget.input.progress.round()}%'),
          ],
        ),
        Slider(
          value: widget.input.progress,
          min: 0,
          max: 100,
          divisions: 20,
          label: '${widget.input.progress.round()}%',
          onChanged: widget.enabled
              ? (value) => setState(() {
                  widget.input.progress = value;
                  if (value == 100) widget.input.status = 'COMPLETED';
                })
              : null,
        ),
        Row(
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: widget.input.status,
                decoration: const InputDecoration(labelText: 'Goal status'),
                items: _goalStatuses
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_label(status)),
                      ),
                    )
                    .toList(),
                onChanged: widget.enabled
                    ? (value) => setState(() {
                        widget.input.status = value!;
                        if (value == 'COMPLETED') widget.input.progress = 100;
                      })
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: widget.input.note,
                enabled: widget.enabled,
                decoration: const InputDecoration(labelText: 'Progress note'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Heading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Heading({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ],
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

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 24),
    padding: const EdgeInsets.all(16),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Row(
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

const _generalStatuses = ['ON_TRACK', 'NEEDS_ATTENTION', 'OFF_TRACK'];
const _goalStatuses = [
  'IN_PROGRESS',
  'ON_TRACK',
  'AT_RISK',
  'OFF_TRACK',
  'COMPLETED',
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
