import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../data/repositories/review_cycle_repository.dart';
import '../auth/profile_provider.dart';

class ReviewCycleFormScreen extends ConsumerStatefulWidget {
  const ReviewCycleFormScreen({super.key});

  @override
  ConsumerState<ReviewCycleFormScreen> createState() => _ReviewCycleFormState();
}

class _ReviewCycleFormState extends ConsumerState<ReviewCycleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _larkTemplate = TextEditingController();
  String _reviewType = 'QUARTERLY';
  DateTime _periodStart = DateTime(DateTime.now().year, 7, 1);
  DateTime _periodEnd = DateTime(DateTime.now().year, 9, 30);
  DateTime _selfDue = DateTime(DateTime.now().year, 10, 5);
  DateTime _managerDue = DateTime(DateTime.now().year, 10, 12);
  DateTime? _finalDue = DateTime(DateTime.now().year, 10, 17);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _larkTemplate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final dateError = _validateDates();
    if (dateError != null) {
      setState(() => _error = dateError);
      return;
    }
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cycle = await ref
          .read(reviewCycleRepositoryProvider)
          .createCycle(
            companyId: profile.companyId,
            name: _name.text,
            reviewType: _reviewType,
            periodStart: _periodStart,
            periodEnd: _periodEnd,
            selfReviewDueDate: _selfDue,
            managerReviewDueDate: _managerDue,
            finalizationDueDate: _finalDue,
            larkFormTemplateId: _larkTemplate.text,
            createdBy: profile.userId,
          );
      ref.invalidate(reviewCycleListProvider);
      if (mounted) context.go('/performance/review-cycles/${cycle.id}');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateDates() {
    if (_periodStart.isAfter(_periodEnd)) {
      return 'Period start must be on or before period end.';
    }
    if (_periodEnd.isAfter(_selfDue)) {
      return 'Self-review due date must be on or after the review period.';
    }
    if (_selfDue.isAfter(_managerDue)) {
      return 'Manager review must be due after the self-review.';
    }
    if (_finalDue != null && _managerDue.isAfter(_finalDue!)) {
      return 'Finalization must be due after the manager review.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go('/performance/review-cycles'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('New review cycle'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(isMobile(context) ? 16 : 24),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cycle details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _responsive([
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Cycle name *',
                        hintText: '2026 Q3 Review',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _reviewType,
                      decoration: const InputDecoration(
                        labelText: 'Review type',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          const [
                                ('MONTHLY_CHECK_IN', 'Monthly check-in'),
                                ('QUARTERLY', 'Quarterly review'),
                                ('PROBATIONARY', 'Probationary review'),
                                ('REGULARIZATION', 'Regularization review'),
                                ('ANNUAL', 'Annual review'),
                                ('AD_HOC', 'Ad hoc review'),
                                ('PIP_REVIEW', 'PIP review'),
                              ]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.$1,
                                  child: Text(item.$2),
                                ),
                              )
                              .toList(),
                      onChanged: (value) =>
                          setState(() => _reviewType = value!),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Text(
                    'Review period',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _responsive([
                    _DateField(
                      label: 'Period start',
                      value: _periodStart,
                      onChanged: (value) =>
                          setState(() => _periodStart = value!),
                    ),
                    _DateField(
                      label: 'Period end',
                      value: _periodEnd,
                      onChanged: (value) => setState(() => _periodEnd = value!),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Text(
                    'Deadlines',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _responsive([
                    _DateField(
                      label: 'Self-review due',
                      value: _selfDue,
                      onChanged: (value) => setState(() => _selfDue = value!),
                    ),
                    _DateField(
                      label: 'Manager review due',
                      value: _managerDue,
                      onChanged: (value) =>
                          setState(() => _managerDue = value!),
                    ),
                    _DateField(
                      label: 'Finalization due',
                      value: _finalDue,
                      optional: true,
                      onChanged: (value) => setState(() => _finalDue = value),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _larkTemplate,
                    decoration: const InputDecoration(
                      labelText: 'Lark form template ID *',
                      helperText:
                          'Universal employee self-review form template.',
                      border: OutlineInputBorder(),
                    ),
                    validator: _required,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => context.go('/performance/review-cycles'),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Creating...' : 'Create cycle'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _responsive(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 720) {
        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );

  String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Required' : null;
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool optional;
  final ValueChanged<DateTime?> onChanged;
  const _DateField({
    required this.label,
    required this.value,
    this.optional = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final selected = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (selected != null && context.mounted) onChanged(selected);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: optional ? '$label (optional)' : label,
        border: const OutlineInputBorder(),
        suffixIcon: value != null && optional
            ? IconButton(
                tooltip: 'Clear date',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close),
              )
            : const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(value == null ? 'Not set' : _date(value!)),
    ),
  );
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);
