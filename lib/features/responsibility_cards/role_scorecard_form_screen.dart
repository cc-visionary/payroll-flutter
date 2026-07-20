import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/breakpoints.dart';
import '../../data/models/kpi.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';
import '../documents/providers.dart';
import '../workforce_planning/wp_providers.dart';
import 'responsibility_rows.dart';
import 'scorecard_base_salary.dart';

class RoleScorecardFormScreen extends ConsumerStatefulWidget {
  final String? cardId;
  const RoleScorecardFormScreen({super.key, this.cardId});
  @override
  ConsumerState<RoleScorecardFormScreen> createState() => _State();
}

class _State extends ConsumerState<RoleScorecardFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _jobTitle = TextEditingController();
  final _mission = TextEditingController();
  final _baseSalary = TextEditingController();
  final _rangeMin = TextEditingController();
  final _rangeMax = TextEditingController();
  final _hoursPerDay = TextEditingController(text: '8');
  final _daysPerWeek = TextEditingController(text: 'Monday to Saturday');
  String _wageType = 'MONTHLY';
  String? _departmentId;
  String? _hiringEntityId;
  DateTime _effectiveDate = DateTime.now();
  bool _isActive = true;
  bool _loading = false;
  String? _error;
  RoleScorecard? _existing;

  final List<_AreaDraft> _areas = [];
  final List<_KpiDraft> _kpis = [];
  final List<_SkillDraft> _skills = [];
  final List<_ExpectationDraft> _expectations = [];
  List<Map<String, dynamic>> _departments = const [];
  // The card's own wp_tasks responsibility rows (id, name, responsibility_area,
  // area_sort, task_sort), captured on load so diffResponsibilities can turn a
  // rename into an UPDATE (never delete+insert, which would drop the row's
  // cadence/minutes/owner) and a removed line into a delete. Never trust
  // upsert()'s return for this — its select has no wp_tasks embed.
  List<Map<String, dynamic>> _existingResponsibilityRows = const [];

  bool get _isEdit => widget.cardId != null;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final depts = await client
          .from('departments')
          .select('id, code, name')
          .order('name');
      _departments = depts.cast<Map<String, dynamic>>();

      if (_isEdit) {
        final e = await ref
            .read(roleScorecardRepositoryProvider)
            .byId(widget.cardId!);
        if (e == null) {
          setState(() => _error = 'Card not found');
          return;
        }
        _existing = e;
        _jobTitle.text = e.jobTitle;
        _mission.text = e.missionStatement;
        _baseSalary.text = e.baseSalary?.toString() ?? '';
        _rangeMin.text = e.salaryRangeMin?.toString() ?? '';
        _rangeMax.text = e.salaryRangeMax?.toString() ?? '';
        _hoursPerDay.text = e.workHoursPerDay.toString();
        _daysPerWeek.text = e.workDaysPerWeek;
        _wageType = e.wageType;
        _departmentId = e.departmentId;
        _hiringEntityId = e.hiringEntityId;
        _effectiveDate = e.effectiveDate;
        _isActive = e.isActive;

        // Raw wp_tasks rows carry the row id — RoleScorecard.responsibilities
        // (built via responsibilitiesFromTaskRows) does not, so it can't be
        // diffed against on save. Query directly rather than through byId(),
        // whose embed is consumed into the id-less grouped shape.
        await _loadResponsibilityRows(widget.cardId!);

        _kpis.clear();
        for (final k in e.kpis) {
          _kpis.add(_KpiDraft(k.name, k.measurement, k.target, k.frequency));
        }
        _skills
          ..clear()
          ..addAll(
            e.requiredSkills.map((s) => _SkillDraft(s.name, s.description)),
          );
        _expectations
          ..clear()
          ..addAll(
            e.behavioralExpectations.map(
              (e) => _ExpectationDraft(e.name, e.description),
            ),
          );
      }
      setState(() {});
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Fetches [cardId]'s wp_tasks responsibility rows and rebuilds BOTH
  /// `_existingResponsibilityRows` (raw) and `_areas` (editable) from them.
  /// Used on initial load, and to resync after a failed saveResponsibilities
  /// call (see `_save()`) — a retry must diff against what the server
  /// actually holds, not against drafts whose ids may already be stale
  /// because the failed call partially inserted some of them.
  Future<void> _loadResponsibilityRows(String cardId) async {
    final rows = await Supabase.instance.client
        .from('wp_tasks')
        .select('id, name, responsibility_area, area_sort, task_sort')
        .eq('role_scorecard_id', cardId)
        .not('responsibility_area', 'is', null)
        .order('area_sort')
        .order('task_sort');
    // Blank-safe, not just NULL-safe: responsibility_area has no NOT-NULL/
    // CHECK constraint, so an empty-string area would pass the `.not(...,
    // 'is', null)` filter above. Left in _existingResponsibilityRows, such a
    // row would never be grouped into _areas (below skips blank areas) and so
    // would never be "kept" by diffResponsibilities — silently DELETED on the
    // next save. Excluding it here means it can never become a delete
    // candidate in the first place.
    _existingResponsibilityRows = [
      for (final r in rows.cast<Map<String, dynamic>>())
        if (((r['responsibility_area'] as String?) ?? '').trim().isNotEmpty)
          r,
    ];
    _areas.clear();
    final areaOrder = <String>[];
    final grouped = <String, List<RespDraft>>{};
    for (final r in _existingResponsibilityRows) {
      final area = (r['responsibility_area'] as String).trim();
      final name = (r['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final tasks = grouped.putIfAbsent(area, () {
        areaOrder.add(area);
        return [];
      });
      tasks.add(RespDraft(id: r['id'] as String, name: name));
    }
    for (final area in areaOrder) {
      _areas.add(_AreaDraft(area, grouped[area]!));
    }
  }

  /// Refreshes every provider a role-card save can affect. Shared by both the
  /// success path and the responsibilities-partial-failure path in `_save()`
  /// — a partial failure can still have changed server state (some rows may
  /// have been inserted/updated/deleted before the failure), so downstream
  /// views need refreshing either way.
  void _invalidateAfterSave(String cardId) {
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(scorecardEmployeeCountProvider);
    ref.invalidate(kpiLibraryProvider);
    // Keep the ephemeral PDF preview (RoleCardPdfScreen) fresh after an edit.
    ref.invalidate(roleScorecardByIdProvider(cardId));
    // Responsibilities are now tasks — refresh the workforce planning views.
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    Decimal? dec(String s) =>
        s.trim().isEmpty ? null : Decimal.tryParse(s.trim());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final card = RoleScorecard(
        id: _existing?.id ?? _uuid(),
        companyId: _existing?.companyId ?? profile.companyId,
        jobTitle: _jobTitle.text.trim(),
        departmentId: _departmentId,
        hiringEntityId: _hiringEntityId,
        missionStatement: _mission.text.trim(),
        // Responsibilities now persist as wp_tasks rows (see saveResponsibilities
        // below) — toUpsertPayload writes key_responsibilities: const [] itself,
        // so this value is never read for persistence. Kept as [] to satisfy the
        // required constructor param.
        responsibilities: const [],
        // KPIs are no longer part of the jsonb payload — persisted separately
        // via saveRoleScorecardKpis below.
        kpis: const [],
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
        version: _existing?.version ?? 1,
        salaryRangeMin: dec(_rangeMin.text),
        salaryRangeMax: dec(_rangeMax.text),
        // Immutable on edit — see resolveScorecardBaseSalaryOnSave. Editing it
        // would silently reprice every employee on this role who has no
        // compensation_changes record.
        baseSalary: resolveScorecardBaseSalaryOnSave(
          isEdit: _isEdit,
          existingBaseSalary: _existing?.baseSalary,
          typedText: _baseSalary.text,
        ),
        wageType: _wageType,
        workHoursPerDay: int.tryParse(_hoursPerDay.text.trim()) ?? 8,
        workDaysPerWeek: _daysPerWeek.text.trim(),
        isActive: _isActive,
        effectiveDate: _effectiveDate,
      );
      final saved = await ref.read(roleScorecardRepositoryProvider).upsert(card);
      await ref.read(roleScorecardRepositoryProvider).saveRoleScorecardKpis(
        saved.id,
        saved.companyId,
        [
          for (final k in _kpis)
            if (k.name.trim().isNotEmpty)
              KpiLinkInput(
                kpiId: k.kpiId,
                name: k.name.trim(),
                measurementUnit: k.measurement.trim(),
                category: k.category,
                target: k.target.trim(),
                frequency: k.frequency.trim(),
              ),
        ],
      );

      try {
        // Diff against the raw rows captured on load (never against
        // upsert()'s return — its select has no wp_tasks embed, so it always
        // reports responsibilities: [] and would misread every existing line
        // as new).
        final diff = diffResponsibilities(
          draft: [for (final a in _areas) (area: a.area, tasks: a.tasks)],
          existingRows: _existingResponsibilityRows,
          cardId: saved.id,
          companyId: saved.companyId,
        );
        await ref.read(roleScorecardRepositoryProvider).saveResponsibilities(
          cardId: saved.id,
          inserts: diff.inserts,
          updates: diff.updates,
          deleteIds: diff.deleteIds,
        );
      } catch (_) {
        // saveResponsibilities is multi-statement and non-transactional
        // (insert -> per-row update -> delete -> legacy-column clear). A
        // partial failure can leave some drafted lines — still id == null in
        // _areas — already INSERTED server-side. Simply reloading
        // _existingResponsibilityRows would NOT fix this: the drafts
        // themselves would still have null ids and diffResponsibilities
        // would insert them a SECOND time on retry, duplicating hours/load.
        // Resync BOTH _existingResponsibilityRows and _areas from the server
        // so a retry diffs against what's actually there — this discards the
        // user's unsaved responsibility edits, which is the correct
        // trade-off (a duplicated responsibility silently inflates load and
        // is hard to spot; re-applying edits is visible and recoverable).
        await _loadResponsibilityRows(saved.id);
        _invalidateAfterSave(saved.id);
        if (mounted) {
          setState(() {
            _error =
                'Some responsibility changes may not have saved. The list '
                'was refreshed from the server — please re-apply your '
                'changes and save again.';
          });
        }
        return;
      }

      _invalidateAfterSave(saved.id);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kpiLibrary = ref.watch(kpiLibraryProvider).asData?.value ?? const <Kpi>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Edit Responsibility Card' : 'New Responsibility Card',
        ),
      ),
      body: _loading && _existing == null && _isEdit
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.all(isMobile(context) ? 16 : 24),
                children: [
                  _card([
                    const _Lbl('Identity'),
                    _field(_jobTitle, 'Job title', required: true),
                    const SizedBox(height: 12),
                    _responsiveRow([
                      DropdownButtonFormField<String?>(
                        initialValue: _departmentId,
                        decoration: const InputDecoration(
                          labelText: 'Department',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('(none)'),
                          ),
                          for (final d in _departments)
                            DropdownMenuItem<String?>(
                              value: d['id'] as String,
                              child: Text('${d['code']} — ${d['name']}'),
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
                    Builder(
                      builder: (context) {
                        final entities =
                            ref.watch(hiringEntityListProvider).asData?.value ??
                            const [];
                        return DropdownButtonFormField<String?>(
                          initialValue: _hiringEntityId,
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
                        );
                      },
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
                  ]),
                  const SizedBox(height: 16),
                  _card([
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
                      'Describe the skills this role requires. These values are snapshotted into each review.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _skills.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _responsiveRow([
                          TextFormField(
                            initialValue: _skills[i].name,
                            decoration: const InputDecoration(
                              labelText: 'Skill name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => _skills[i].name = v,
                          ),
                          TextFormField(
                            initialValue: _skills[i].description,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              hintText:
                                  'Describe how this skill is demonstrated in the role',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => _skills[i].description = v,
                          ),
                          IconButton(
                            tooltip: 'Remove skill',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                setState(() => _skills.removeAt(i)),
                          ),
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  _card([
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
                                    initialValue: _expectations[i].name,
                                    decoration: const InputDecoration(
                                      labelText: 'Expectation name',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => _expectations[i].name = v,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
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
                  ]),
                  const SizedBox(height: 16),
                  _card([
                    const _Lbl('Compensation & schedule'),
                    _responsiveRow([
                      DropdownButtonFormField<String>(
                        initialValue: _wageType,
                        decoration: const InputDecoration(
                          labelText: 'Wage type',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['MONTHLY', 'DAILY', 'HOURLY']
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _wageType = v!),
                      ),
                      _baseSalaryField(),
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
                  ]),
                  const SizedBox(height: 16),
                  _card([
                    Row(
                      children: [
                        const _Lbl('Responsibilities'),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _areas.add(_AreaDraft('', []))),
                          icon: const Icon(Icons.add),
                          label: const Text('Add area'),
                        ),
                      ],
                    ),
                    for (int i = 0; i < _areas.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: _areas[i].area,
                                    decoration: const InputDecoration(
                                      labelText: 'Area',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (v) => _areas[i].area = v,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      setState(() => _areas.removeAt(i)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (int j = 0; j < _areas[i].tasks.length; j++)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  top: 4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: _areas[i].tasks[j].name,
                                        decoration: const InputDecoration(
                                          labelText: 'Task',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        onChanged: (v) =>
                                            _areas[i].tasks[j].name = v,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => setState(
                                        () => _areas[i].tasks.removeAt(j),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(left: 16, top: 4),
                              child: TextButton.icon(
                                onPressed: () => setState(
                                  () => _areas[i].tasks.add(
                                    RespDraft(id: null, name: ''),
                                  ),
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add task'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  _card([
                    Row(
                      children: [
                        const _Lbl('KPIs'),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _kpis.add(_KpiDraft('', '', '', 'Monthly')),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Add KPI'),
                        ),
                      ],
                    ),
                    for (int i = 0; i < _kpis.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _kpiEditor(i, kpiLibrary),
                      ),
                  ]),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _loading ? null : _save,
                        child: _loading
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
    );
  }

  Widget _kpiEditor(int index, List<Kpi> kpiLibrary) {
    final fields = [
      Autocomplete<Kpi>(
        initialValue: TextEditingValue(text: _kpis[index].name),
        optionsBuilder: (v) => v.text.isEmpty
            ? kpiLibrary
            : kpiLibrary.where(
                (k) => k.name.toLowerCase().contains(v.text.toLowerCase()),
              ),
        displayStringForOption: (k) => k.name,
        onSelected: (k) async {
          setState(() {
            _kpis[index]
              ..kpiId = k.id
              ..name = k.name
              ..measurement = k.measurementUnit ?? _kpis[index].measurement
              ..category = k.category;
          });
          // Target/frequency are per-role, so the library KPI has none — pull
          // the values it's typically used with on other role cards.
          final d = await ref
              .read(roleScorecardRepositoryProvider)
              .kpiDefaultsFromUsage(k.id);
          if (!mounted) return;
          setState(() {
            if ((d.target ?? '').isNotEmpty) _kpis[index].target = d.target!;
            if ((d.frequency ?? '').isNotEmpty) {
              _kpis[index].frequency = d.frequency!;
            }
          });
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
            TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'KPI name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() {
                _kpis[index].name = value;
                _kpis[index].kpiId = null; // typing a fresh name = new library KPI
              }),
            ),
      ),
      TextFormField(
        // Keyed on the value so a programmatic auto-fill (onSelected) re-inits
        // the field; unchanged during typing (onChanged doesn't setState).
        key: ValueKey('kpi-measure-$index-${_kpis[index].measurement}'),
        initialValue: _kpis[index].measurement,
        enabled: _kpis[index].kpiId == null,
        decoration: const InputDecoration(
          labelText: 'Measurement',
          hintText: 'How the KPI is measured',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => _kpis[index].measurement = value,
      ),
      TextFormField(
        key: ValueKey('kpi-target-$index-${_kpis[index].target}'),
        initialValue: _kpis[index].target,
        decoration: const InputDecoration(
          labelText: 'Target',
          hintText: 'Expected result',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => _kpis[index].target = value,
      ),
      TextFormField(
        key: ValueKey('kpi-freq-$index-${_kpis[index].frequency}'),
        initialValue: _kpis[index].frequency,
        decoration: const InputDecoration(
          labelText: 'Check frequency',
          hintText: 'Monthly',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => _kpis[index].frequency = value,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                fields[i],
              ],
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Remove KPI',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _kpis.removeAt(index)),
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: fields[0]),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: fields[1]),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: fields[2]),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: fields[3]),
            IconButton(
              tooltip: 'Remove KPI',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _kpis.removeAt(index)),
            ),
          ],
        );
      },
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

  Widget _card(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  /// Settable only when creating a scorecard; locked afterwards. Payroll falls
  /// back to this value for employees with no compensation record, so editing
  /// it would silently reprice them with no effective date or notice.
  Widget _baseSalaryField() => TextFormField(
    controller: _baseSalary,
    readOnly: _isEdit,
    enabled: !_isEdit,
    decoration: InputDecoration(
      labelText: 'Base salary (PHP)',
      border: const OutlineInputBorder(),
      helperMaxLines: 3,
      helperText: _isEdit
          ? 'Locked. Change pay via "Adjust Compensation" on the employee — '
                'that records an effective date and generates the notice.'
          : "The role's default pay. Used by offer letters, and by any "
                'employee who has no compensation record yet.',
    ),
  );

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

class _AreaDraft {
  String area;
  // Each line's wp_tasks row id (null for a new, unsaved line) — carried so a
  // rename diffs as an UPDATE, not a delete+insert (see RespDraft).
  List<RespDraft> tasks;
  _AreaDraft(this.area, this.tasks);
}

class _KpiDraft {
  String? kpiId; // null until picked from / saved to the library
  String name;
  String measurement;
  String? category;
  String target;
  String frequency;
  _KpiDraft(this.name, this.measurement, this.target, this.frequency);
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

String _uuid() {
  // Short pseudo-UUID for new rows — server will accept since we store client-generated UUIDs
  // across the schema. Collisions astronomically unlikely.
  final now = DateTime.now().microsecondsSinceEpoch;
  final rnd = now.toRadixString(16).padLeft(12, '0');
  return '${rnd.substring(0, 8)}-${rnd.substring(8, 12)}-4xxx-yxxx-xxxxxxxxxxxx'
      .replaceAllMapped(RegExp(r'[xy]'), (m) {
        final r = (DateTime.now().microsecond + m.start) & 0xf;
        return (m.group(0) == 'x' ? r : (r & 0x3) | 0x8).toRadixString(16);
      });
}
