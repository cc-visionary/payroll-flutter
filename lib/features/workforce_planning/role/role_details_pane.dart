import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/breakpoints.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/repositories/department_repository.dart';
import '../../../data/repositories/hiring_entity_repository.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../documents/providers.dart' show roleScorecardByIdProvider;
import '../../responsibility_cards/scorecard_base_salary.dart';

/// Guards a `DropdownButtonFormField`'s `initialValue` against an id that
/// isn't among its current `items` — the widget asserts if `initialValue`
/// isn't found among `items` (verified against the installed Flutter SDK:
/// `DropdownButtonFormField`'s constructor asserts exactly one item matches
/// `initialValue`, unless `initialValue` is null). A card pointing at a
/// since-deleted department or hiring entity would otherwise crash this pane
/// on open. Ported from `task_form_dialog.dart`'s `_present` — the card
/// editor this pane supersedes calls `initialValue` raw on both dropdowns
/// and lacks this guard (a known, accepted latent bug in that file, which is
/// scheduled for deletion).
String? _present(String? id, Iterable<String> ids) =>
    (id != null && ids.contains(id)) ? id : null;

/// The first pane of the role workbench: identity, required skills,
/// behavioral expectations, and compensation & schedule. Ported from
/// `role_scorecard_form_screen.dart` — the same labels, the same
/// `_responsiveRow` two-column behaviour, the same validators — with two
/// departures: base salary is rendered permanently read-only (this pane only
/// ever edits an existing card), and every repeating row is keyed by its
/// draft's `identityHashCode`, never by list index.
class RoleDetailsPane extends ConsumerStatefulWidget {
  const RoleDetailsPane({super.key, required this.card});

  final RoleScorecard card;

  @override
  ConsumerState<RoleDetailsPane> createState() => _RoleDetailsPaneState();
}

class _RoleDetailsPaneState extends ConsumerState<RoleDetailsPane> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _jobTitle;
  late final TextEditingController _mission;
  late final TextEditingController _baseSalary;
  late final TextEditingController _rangeMin;
  late final TextEditingController _rangeMax;
  late final TextEditingController _hoursPerDay;
  late final TextEditingController _daysPerWeek;
  late String _wageType;
  String? _departmentId;
  String? _hiringEntityId;
  late DateTime _effectiveDate;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  final List<_SkillDraft> _skills = [];
  final List<_ExpectationDraft> _expectations = [];

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _jobTitle = TextEditingController(text: card.jobTitle);
    _mission = TextEditingController(text: card.missionStatement);
    _baseSalary = TextEditingController(
      text: card.baseSalary?.toString() ?? '',
    );
    _rangeMin = TextEditingController(
      text: card.salaryRangeMin?.toString() ?? '',
    );
    _rangeMax = TextEditingController(
      text: card.salaryRangeMax?.toString() ?? '',
    );
    _hoursPerDay = TextEditingController(
      text: card.workHoursPerDay.toString(),
    );
    _daysPerWeek = TextEditingController(text: card.workDaysPerWeek);
    _wageType = card.wageType;
    _departmentId = card.departmentId;
    _hiringEntityId = card.hiringEntityId;
    _effectiveDate = card.effectiveDate;
    _isActive = card.isActive;
    _skills.addAll(
      card.requiredSkills.map((s) => _SkillDraft(s.name, s.description)),
    );
    _expectations.addAll(
      card.behavioralExpectations.map(
        (e) => _ExpectationDraft(e.name, e.description),
      ),
    );
  }

  @override
  void dispose() {
    _jobTitle.dispose();
    _mission.dispose();
    _baseSalary.dispose();
    _rangeMin.dispose();
    _rangeMax.dispose();
    _hoursPerDay.dispose();
    _daysPerWeek.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    Decimal? dec(String s) =>
        s.trim().isEmpty ? null : Decimal.tryParse(s.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = RoleScorecard(
        id: widget.card.id,
        companyId: widget.card.companyId,
        jobTitle: _jobTitle.text.trim(),
        departmentId: _departmentId,
        hiringEntityId: _hiringEntityId,
        missionStatement: _mission.text.trim(),
        responsibilities: widget.card.responsibilities,
        kpis: widget.card.kpis,
        requiredSkills: [
          for (final skill in _skills)
            if (skill.name.trim().isNotEmpty)
              RequiredSkill(
                name: skill.name.trim(),
                description: skill.description.trim(),
              ),
        ],
        behavioralExpectations: [
          for (final expectation in _expectations)
            if (expectation.name.trim().isNotEmpty)
              BehavioralExpectation(
                name: expectation.name.trim(),
                description: expectation.description.trim(),
              ),
        ],
        version: widget.card.version,
        salaryRangeMin: dec(_rangeMin.text),
        salaryRangeMax: dec(_rangeMax.text),
        // Immutable on edit — see resolveScorecardBaseSalaryOnSave. This pane
        // only ever edits an existing card, so isEdit is always true: the
        // field's typed text (it's disabled, so never actually typed into)
        // is never what's persisted.
        baseSalary: resolveScorecardBaseSalaryOnSave(
          isEdit: true,
          existingBaseSalary: widget.card.baseSalary,
          typedText: _baseSalary.text,
        ),
        wageType: _wageType,
        workHoursPerDay: int.tryParse(_hoursPerDay.text.trim()) ?? 8,
        workDaysPerWeek: _daysPerWeek.text.trim(),
        isActive: _isActive,
        effectiveDate: _effectiveDate,
        supersededById: widget.card.supersededById,
        shiftTemplateId: widget.card.shiftTemplateId,
      );
      await ref.read(roleScorecardRepositoryProvider).upsert(updated);
      ref.invalidate(roleScorecardByIdProvider(widget.card.id));
      ref.invalidate(roleScorecardListProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Role details saved.')));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments =
        ref.watch(departmentListProvider).asData?.value ?? const [];
    final entities =
        ref.watch(hiringEntityListProvider).asData?.value ?? const [];
    return ExpansionTile(
      title: const Text('Role details'),
      initiallyExpanded: false,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Lbl('Identity'),
                _field(_jobTitle, 'Job title', required: true),
                const SizedBox(height: 12),
                _responsiveRow([
                  DropdownButtonFormField<String?>(
                    initialValue: _present(
                      _departmentId,
                      departments.map((d) => d.id),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('(none)'),
                      ),
                      for (final d in departments)
                        DropdownMenuItem<String?>(
                          value: d.id,
                          child: Text('${d.code} — ${d.name}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _departmentId = v),
                  ),
                  _DatePickerField(
                    label: 'Effective date',
                    value: _effectiveDate,
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: _effectiveDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (p != null) setState(() => _effectiveDate = p);
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _present(
                    _hiringEntityId,
                    entities.map((e) => e.id),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Company (brand)',
                    helperText:
                        'Default brand for employees on this scorecard.',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('(none)'),
                    ),
                    for (final e in entities)
                      DropdownMenuItem<String?>(
                        value: e.id,
                        child: Text(e.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _hiringEntityId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mission,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Mission statement *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const _Lbl('Required skills'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _skills.add(_SkillDraft('', ''))),
                      icon: const Icon(Icons.add),
                      label: const Text('Add skill'),
                    ),
                  ],
                ),
                Text(
                  'Describe the skills this role requires. These values are '
                  'snapshotted into each review.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (int i = 0; i < _skills.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _responsiveRow([
                      TextFormField(
                        // Keyed by draft identity, not list position:
                        // unkeyed fields are matched positionally, so
                        // removing row i left every surviving field showing
                        // the text of the row before it — on screen the LAST
                        // row looked deleted (fixed in 6ae6c9b).
                        key: ValueKey(
                          'skill-name-${identityHashCode(_skills[i])}',
                        ),
                        initialValue: _skills[i].name,
                        decoration: const InputDecoration(
                          labelText: 'Skill name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => _skills[i].name = v,
                      ),
                      TextFormField(
                        key: ValueKey(
                          'skill-desc-${identityHashCode(_skills[i])}',
                        ),
                        initialValue: _skills[i].description,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText:
                              'Describe how this skill is demonstrated in '
                              'the role',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => _skills[i].description = v,
                      ),
                      IconButton(
                        tooltip: 'Remove skill',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _skills.removeAt(i)),
                      ),
                    ]),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const _Lbl('Behavioral expectations'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(
                        () => _expectations.add(_ExpectationDraft('', '')),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add expectation'),
                    ),
                  ],
                ),
                for (int i = 0; i < _expectations.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              TextFormField(
                                key: ValueKey(
                                  'exp-name-${identityHashCode(_expectations[i])}',
                                ),
                                initialValue: _expectations[i].name,
                                decoration: const InputDecoration(
                                  labelText: 'Expectation name',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) =>
                                    _expectations[i].name = v,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                key: ValueKey(
                                  'exp-desc-${identityHashCode(_expectations[i])}',
                                ),
                                initialValue: _expectations[i].description,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Observable standard',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) =>
                                    _expectations[i].description = v,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove expectation',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              setState(() => _expectations.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                const _Lbl('Compensation & schedule'),
                _responsiveRow([
                  DropdownButtonFormField<String>(
                    initialValue: _wageType,
                    decoration: const InputDecoration(
                      labelText: 'Wage type',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['MONTHLY', 'DAILY', 'HOURLY']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _wageType = v!),
                  ),
                  // Immutable on an existing card. Changing it would silently
                  // reprice every employee on this role who has no
                  // compensation_changes row — see
                  // resolveScorecardBaseSalaryOnSave, which enforces this on
                  // save too.
                  TextFormField(
                    controller: _baseSalary,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Base salary',
                      helperText:
                          'Set per employee under compensation, not on the '
                          'role.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _responsiveRow([
                  _field(_rangeMin, 'Range min'),
                  _field(_rangeMax, 'Range max'),
                ]),
                const SizedBox(height: 12),
                _responsiveRow([
                  _field(_hoursPerDay, 'Hours / day', required: true),
                  _field(_daysPerWeek, 'Days / week'),
                ]),
                SwitchListTile(
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _responsiveRow(List<Widget> children, {double gap = 12}) {
    if (isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
  }) => TextFormField(
    controller: c,
    decoration: InputDecoration(
      labelText: label + (required ? ' *' : ''),
      border: const OutlineInputBorder(),
    ),
    validator: required
        ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null
        : null,
  );
}

class _SkillDraft {
  String name;
  String description;
  _SkillDraft(this.name, this.description);
}

class _ExpectationDraft {
  String name;
  String description;
  _ExpectationDraft(this.name, this.description);
}

class _Lbl extends StatelessWidget {
  final String text;
  const _Lbl(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    child: InkWell(
      onTap: onTap,
      child: Text(value.toIso8601String().substring(0, 10)),
    ),
  );
}
