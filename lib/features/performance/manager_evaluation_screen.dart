import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/manager_review.dart';
import '../../data/models/review_kpi_result.dart';
import '../../data/models/review_skill_rating.dart';
import '../../data/repositories/review_cycle_repository.dart';

class ManagerEvaluationScreen extends ConsumerStatefulWidget {
  final String reviewId;
  const ManagerEvaluationScreen({super.key, required this.reviewId});

  @override
  ConsumerState<ManagerEvaluationScreen> createState() =>
      _ManagerEvaluationScreenState();
}

class _ManagerEvaluationScreenState
    extends ConsumerState<ManagerEvaluationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _feedback = TextEditingController();
  final _concerns = TextEditingController();
  final _support = TextEditingController();
  final _readiness = TextEditingController();
  final List<_StrengthInput> _strengths = [];
  final List<_DevelopmentInput> _developmentAreas = [];
  final Map<String, _KpiInput> _kpis = {};
  final Map<String, _SkillInput> _skills = {};
  double? _overallRating;
  String? _outcome;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _feedback.dispose();
    _concerns.dispose();
    _support.dispose();
    _readiness.dispose();
    for (final item in _strengths) {
      item.dispose();
    }
    for (final item in _developmentAreas) {
      item.dispose();
    }
    for (final item in _kpis.values) {
      item.dispose();
    }
    for (final item in _skills.values) {
      item.dispose();
    }
    super.dispose();
  }

  void _initialize(
    List<ReviewKpiResult> kpis,
    List<ReviewSkillRating> skills,
    ManagerReview? managerReview,
    double? rating,
    String? outcome,
  ) {
    if (_initialized) return;
    _initialized = true;
    for (final item in kpis) {
      _kpis[item.id] = _KpiInput(item);
    }
    for (final item in skills) {
      _skills[item.id] = _SkillInput(item);
    }
    if (managerReview != null) {
      _feedback.text = managerReview.overallFeedback ?? '';
      _concerns.text = managerReview.performanceConcerns ?? '';
      _support.text = managerReview.supportManagerWillProvide ?? '';
      _readiness.text = managerReview.readinessForAdditionalDuties ?? '';
      _strengths.addAll(managerReview.strengths.map(_StrengthInput.fromMap));
      _developmentAreas.addAll(
        managerReview.developmentAreas.map(_DevelopmentInput.fromMap),
      );
    }
    _overallRating = rating;
    _outcome = outcome ?? managerReview?.recommendedOutcome;
  }

  Future<void> _save({required bool submit}) async {
    if (submit && !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(reviewCycleRepositoryProvider)
          .saveManagerEvaluation(
            reviewId: widget.reviewId,
            kpis: _kpis.entries
                .map((entry) => entry.value.toMap(entry.key))
                .toList(),
            skills: _skills.entries
                .map((entry) => entry.value.toMap(entry.key))
                .toList(),
            overallFeedback: _feedback.text,
            performanceConcerns: _concerns.text,
            supportManagerWillProvide: _support.text,
            readinessForAdditionalDuties: _readiness.text,
            strengths: _strengths.map((item) => item.toMap()).toList(),
            developmentAreas: _developmentAreas
                .map((item) => item.toMap())
                .toList(),
            overallRating: _overallRating,
            recommendedOutcome: _outcome,
            submit: submit,
          );
      ref.invalidate(employeeReviewProvider(widget.reviewId));
      ref.invalidate(reviewKpisProvider(widget.reviewId));
      ref.invalidate(reviewSkillsProvider(widget.reviewId));
      ref.invalidate(managerReviewProvider(widget.reviewId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(submit ? 'Manager review submitted.' : 'Draft saved.'),
        ),
      );
      if (submit) context.go('/performance/reviews/${widget.reviewId}');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save evaluation: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(employeeReviewProvider(widget.reviewId));
    final kpis = ref.watch(reviewKpisProvider(widget.reviewId));
    final skills = ref.watch(reviewSkillsProvider(widget.reviewId));
    final managerReview = ref.watch(managerReviewProvider(widget.reviewId));
    if ([review, kpis, skills, managerReview].any((value) => value.isLoading)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final error =
        review.error ?? kpis.error ?? skills.error ?? managerReview.error;
    if (error != null) {
      return Scaffold(
        body: Center(child: Text('Could not load evaluation: $error')),
      );
    }
    final reviewValue = review.value;
    if (reviewValue == null) {
      return const Scaffold(body: Center(child: Text('Review not found.')));
    }
    final locked =
        reviewValue.status == 'FINALIZED' ||
        reviewValue.status == 'CANCELLED' ||
        reviewValue.status == 'READY_FOR_DISCUSSION' ||
        reviewValue.status == 'DISCUSSION_COMPLETED';
    _initialize(
      kpis.value ?? const [],
      skills.value ?? const [],
      managerReview.value,
      reviewValue.overallRating,
      reviewValue.overallOutcome,
    );
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.go('/performance/reviews/${widget.reviewId}'),
        ),
        title: Text('Evaluate ${reviewValue.employeeNameSnapshot}'),
        actions: [
          TextButton(
            onPressed: _saving || locked ? null : () => _save(submit: false),
            child: const Text('Save draft'),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: FilledButton(
              onPressed: _saving || locked ? null : () => _save(submit: true),
              child: Text(_saving ? 'Saving...' : 'Submit manager review'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            if (locked)
              const _Notice(
                text:
                    'This manager evaluation is read-only at the current review stage.',
              ),
            _Heading(
              title: 'KPI results',
              subtitle:
                  'Enter the result before assigning a rating. Use Not applicable or Not enough data when appropriate.',
            ),
            ..._kpis.entries.map(
              (entry) => _KpiEditor(input: entry.value, locked: locked),
            ),
            const SizedBox(height: 32),
            const _Heading(
              title: 'Skill ratings',
              subtitle:
                  'Rate required skills and behavioral expectations using one consistent 1 to 5 scale.',
            ),
            ..._skills.entries.map(
              (entry) => _SkillEditor(input: entry.value, locked: locked),
            ),
            const SizedBox(height: 32),
            const _Heading(
              title: 'Manager review',
              subtitle:
                  'Summarize performance and the support you will provide next.',
            ),
            TextFormField(
              controller: _feedback,
              enabled: !locked,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Overall feedback'),
              validator: (value) => value?.trim().isEmpty == true
                  ? 'Overall feedback is required'
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _concerns,
                    enabled: !locked,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Performance concerns (optional)',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _support,
                    enabled: !locked,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Support the manager will provide',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _readiness,
              enabled: !locked,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Readiness for additional duties',
              ),
            ),
            const SizedBox(height: 32),
            _CollectionHeading(
              title: 'Strengths',
              count: _strengths.length,
              limit: 3,
              onAdd: locked || _strengths.length >= 3
                  ? null
                  : () => setState(() => _strengths.add(_StrengthInput())),
            ),
            ..._strengths.asMap().entries.map(
              (entry) => _StrengthEditor(
                input: entry.value,
                locked: locked,
                onRemove: () => setState(() {
                  _strengths.removeAt(entry.key).dispose();
                }),
              ),
            ),
            const SizedBox(height: 24),
            _CollectionHeading(
              title: 'Development areas',
              count: _developmentAreas.length,
              limit: 2,
              onAdd: locked || _developmentAreas.length >= 2
                  ? null
                  : () => setState(
                      () => _developmentAreas.add(_DevelopmentInput()),
                    ),
            ),
            ..._developmentAreas.asMap().entries.map(
              (entry) => _DevelopmentEditor(
                input: entry.value,
                locked: locked,
                onRemove: () => setState(() {
                  _developmentAreas.removeAt(entry.key).dispose();
                }),
              ),
            ),
            const SizedBox(height: 32),
            const _Heading(
              title: 'Recommendation',
              subtitle:
                  'This recommendation does not automatically create a promotion or PIP.',
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<double>(
                    initialValue: _overallRating,
                    decoration: const InputDecoration(
                      labelText: 'Overall rating',
                    ),
                    items: [1, 2, 3, 4, 5]
                        .map(
                          (rating) => DropdownMenuItem(
                            value: rating.toDouble(),
                            child: Text('$rating - ${_ratingLabel(rating)}'),
                          ),
                        )
                        .toList(),
                    onChanged: locked
                        ? null
                        : (value) => _overallRating = value,
                    validator: (value) =>
                        value == null ? 'Select an overall rating' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _outcome,
                    decoration: const InputDecoration(
                      labelText: 'Recommended outcome',
                    ),
                    items: _outcomes
                        .map(
                          (outcome) => DropdownMenuItem(
                            value: outcome,
                            child: Text(_label(outcome)),
                          ),
                        )
                        .toList(),
                    onChanged: locked ? null : (value) => _outcome = value,
                    validator: (value) =>
                        value == null ? 'Select an outcome' : null,
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

class _KpiInput {
  final ReviewKpiResult source;
  final actual = TextEditingController();
  final comment = TextEditingController();
  String? status;
  int? rating;
  _KpiInput(this.source) {
    actual.text = source.actualValue ?? '';
    comment.text = source.managerComment ?? '';
    status = source.resultStatus;
    rating = source.managerRating;
  }
  Map<String, dynamic> toMap(String id) => {
    'id': id,
    'actual_value': actual.text.trim(),
    'result_status': status,
    'manager_rating': rating,
    'manager_comment': comment.text.trim(),
  };
  void dispose() {
    actual.dispose();
    comment.dispose();
  }
}

class _SkillInput {
  final ReviewSkillRating source;
  final comment = TextEditingController();
  int? rating;
  bool developmentNeeded;
  _SkillInput(this.source) : developmentNeeded = source.developmentNeeded {
    comment.text = source.managerComment ?? '';
    rating = source.managerRating;
  }
  Map<String, dynamic> toMap(String id) => {
    'id': id,
    'manager_rating': rating,
    'manager_comment': comment.text.trim(),
    'development_needed': developmentNeeded,
  };
  void dispose() => comment.dispose();
}

class _KpiEditor extends StatefulWidget {
  final _KpiInput input;
  final bool locked;
  const _KpiEditor({required this.input, required this.locked});
  @override
  State<_KpiEditor> createState() => _KpiEditorState();
}

class _KpiEditorState extends State<_KpiEditor> {
  @override
  Widget build(BuildContext context) {
    final item = widget.input.source;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.kpiName, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            [
              'Measurement: ${item.measurementUnit ?? 'Not set'}',
              'Target: ${item.targetValue ?? 'Not set'}',
              'Check: ${item.checkFrequency ?? 'Not set'}',
            ].join('  •  '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: widget.input.actual,
                  enabled: !widget.locked,
                  decoration: const InputDecoration(labelText: 'Actual result'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: widget.input.status,
                  decoration: const InputDecoration(labelText: 'Result status'),
                  items: _kpiStatuses
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_label(value)),
                        ),
                      )
                      .toList(),
                  onChanged: widget.locked
                      ? null
                      : (value) => setState(() => widget.input.status = value),
                  validator: (value) =>
                      value == null ? 'Select result status' : null,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<int>(
                  initialValue: widget.input.rating,
                  decoration: const InputDecoration(labelText: 'Rating'),
                  items: [1, 2, 3, 4, 5]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value - ${_ratingLabel(value)}'),
                        ),
                      )
                      .toList(),
                  onChanged: widget.locked
                      ? null
                      : (value) => setState(() => widget.input.rating = value),
                  validator: (value) => value == null ? 'Select rating' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.input.comment,
            enabled: !widget.locked,
            decoration: const InputDecoration(labelText: 'Manager comment'),
            maxLines: 2,
          ),
          const Divider(height: 32),
        ],
      ),
    );
  }
}

class _SkillEditor extends StatefulWidget {
  final _SkillInput input;
  final bool locked;
  const _SkillEditor({required this.input, required this.locked});
  @override
  State<_SkillEditor> createState() => _SkillEditorState();
}

class _SkillEditorState extends State<_SkillEditor> {
  @override
  Widget build(BuildContext context) {
    final item = widget.input.source;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.skillName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (item.skillDescription?.isNotEmpty == true)
                      Text(
                        item.skillDescription!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Text(
                item.skillCategory == 'BEHAVIORAL'
                    ? 'Behavioral expectation'
                    : 'Required skill',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int>(
                  initialValue: widget.input.rating,
                  decoration: const InputDecoration(
                    labelText: 'Manager rating',
                  ),
                  items: [1, 2, 3, 4, 5]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value - ${_skillRatingLabel(value)}'),
                        ),
                      )
                      .toList(),
                  onChanged: widget.locked
                      ? null
                      : (value) => setState(() => widget.input.rating = value),
                  validator: (value) => value == null ? 'Select rating' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: widget.input.comment,
                  enabled: !widget.locked,
                  decoration: const InputDecoration(
                    labelText: 'Manager comment',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Checkbox(
                value: widget.input.developmentNeeded,
                onChanged: widget.locked
                    ? null
                    : (value) => setState(
                        () => widget.input.developmentNeeded = value ?? false,
                      ),
              ),
              const Text('Development needed'),
            ],
          ),
          const Divider(height: 32),
        ],
      ),
    );
  }
}

class _StrengthInput {
  final title = TextEditingController();
  final description = TextEditingController();
  final evidence = TextEditingController();
  _StrengthInput();
  factory _StrengthInput.fromMap(Map<String, dynamic> map) {
    final item = _StrengthInput();
    item.title.text = map['title']?.toString() ?? '';
    item.description.text = map['description']?.toString() ?? '';
    item.evidence.text = map['evidence']?.toString() ?? '';
    return item;
  }
  Map<String, dynamic> toMap() => {
    'title': title.text.trim(),
    'description': description.text.trim(),
    'evidence': evidence.text.trim(),
  };
  void dispose() {
    title.dispose();
    description.dispose();
    evidence.dispose();
  }
}

class _DevelopmentInput {
  final area = TextEditingController();
  final gap = TextEditingController();
  final standard = TextEditingController();
  final action = TextEditingController();
  _DevelopmentInput();
  factory _DevelopmentInput.fromMap(Map<String, dynamic> map) {
    final item = _DevelopmentInput();
    item.area.text = map['area']?.toString() ?? '';
    item.gap.text = map['gap']?.toString() ?? '';
    item.standard.text = map['expected_standard']?.toString() ?? '';
    item.action.text = map['recommended_action']?.toString() ?? '';
    return item;
  }
  Map<String, dynamic> toMap() => {
    'area': area.text.trim(),
    'gap': gap.text.trim(),
    'expected_standard': standard.text.trim(),
    'recommended_action': action.text.trim(),
  };
  void dispose() {
    area.dispose();
    gap.dispose();
    standard.dispose();
    action.dispose();
  }
}

class _StrengthEditor extends StatelessWidget {
  final _StrengthInput input;
  final bool locked;
  final VoidCallback onRemove;
  const _StrengthEditor({
    required this.input,
    required this.locked,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: input.title,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Strength title'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: input.description,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: input.evidence,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Evidence or example'),
          ),
        ),
        IconButton(
          onPressed: locked ? null : onRemove,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove strength',
        ),
      ],
    ),
  );
}

class _DevelopmentEditor extends StatelessWidget {
  final _DevelopmentInput input;
  final bool locked;
  final VoidCallback onRemove;
  const _DevelopmentEditor({
    required this.input,
    required this.locked,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: input.area,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Development area'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: input.gap,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Current gap'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: input.standard,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Expected standard'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: input.action,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Recommended action'),
          ),
        ),
        IconButton(
          onPressed: locked ? null : onRemove,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove development area',
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

class _CollectionHeading extends StatelessWidget {
  final String title;
  final int count;
  final int limit;
  final VoidCallback? onAdd;
  const _CollectionHeading({
    required this.title,
    required this.count,
    required this.limit,
    required this.onAdd,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          '$title ($count of $limit)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: Text('Add ${title.toLowerCase().replaceAll(RegExp('s\$'), '')}'),
      ),
    ],
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
        const Icon(Icons.lock_outline),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

const _kpiStatuses = [
  'EXCEEDED',
  'MET',
  'PARTIALLY_MET',
  'NOT_MET',
  'NOT_APPLICABLE',
  'NOT_ENOUGH_DATA',
];
const _outcomes = [
  'PERFORMING_WELL',
  'CONTINUE_DEVELOPMENT',
  'READY_FOR_CROSS_TRAINING',
  'READY_FOR_ADDITIONAL_RESPONSIBILITY',
  'PROMOTION_CONSIDERATION',
  'NEEDS_CLOSER_COACHING',
  'FORMAL_PERFORMANCE_CONCERN',
  'PIP_RECOMMENDED',
];
String _label(String value) => value
    .toLowerCase()
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
String _ratingLabel(int rating) => const {
  1: 'Below standard',
  2: 'Needs improvement',
  3: 'Meets expectations',
  4: 'Exceeds expectations',
  5: 'Exceptional',
}[rating]!;
String _skillRatingLabel(int rating) => const {
  1: 'Not trained',
  2: 'Learning',
  3: 'Normal supervision',
  4: 'Independent',
  5: 'Can train others',
}[rating]!;
