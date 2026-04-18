import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/breakpoints.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';

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
  DateTime _effectiveDate = DateTime.now();
  bool _isActive = true;
  bool _loading = false;
  String? _error;
  RoleScorecard? _existing;

  final List<_AreaDraft> _areas = [];
  final List<_KpiDraft> _kpis = [];
  List<Map<String, dynamic>> _departments = const [];

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
      final depts = await client.from('departments').select('id, code, name').order('name');
      _departments = depts.cast<Map<String, dynamic>>();

      if (_isEdit) {
        final e = await ref.read(roleScorecardRepositoryProvider).byId(widget.cardId!);
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
        _effectiveDate = e.effectiveDate;
        _isActive = e.isActive;
        _areas.clear();
        for (final a in e.responsibilities) {
          _areas.add(_AreaDraft(a.area, a.tasks.toList()));
        }
        _kpis.clear();
        for (final k in e.kpis) {
          _kpis.add(_KpiDraft(k.metric, k.frequency));
        }
      }
      setState(() {});
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    Decimal? dec(String s) => s.trim().isEmpty ? null : Decimal.tryParse(s.trim());
    setState(() { _loading = true; _error = null; });
    try {
      final card = RoleScorecard(
        id: _existing?.id ?? _uuid(),
        companyId: _existing?.companyId ?? profile.companyId,
        jobTitle: _jobTitle.text.trim(),
        departmentId: _departmentId,
        missionStatement: _mission.text.trim(),
        responsibilities: [
          for (final a in _areas)
            if (a.area.trim().isNotEmpty)
              ResponsibilityArea(area: a.area.trim(), tasks: a.tasks.where((t) => t.trim().isNotEmpty).toList()),
        ],
        kpis: [
          for (final k in _kpis)
            if (k.metric.trim().isNotEmpty)
              KpiItem(metric: k.metric.trim(), frequency: k.frequency.trim().isEmpty ? 'Monthly' : k.frequency.trim()),
        ],
        salaryRangeMin: dec(_rangeMin.text),
        salaryRangeMax: dec(_rangeMax.text),
        baseSalary: dec(_baseSalary.text),
        wageType: _wageType,
        workHoursPerDay: int.tryParse(_hoursPerDay.text.trim()) ?? 8,
        workDaysPerWeek: _daysPerWeek.text.trim(),
        isActive: _isActive,
        effectiveDate: _effectiveDate,
      );
      await ref.read(roleScorecardRepositoryProvider).upsert(card);
      ref.invalidate(roleScorecardListProvider);
      ref.invalidate(scorecardEmployeeCountProvider);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Responsibility Card' : 'New Responsibility Card')),
      body: _loading && _existing == null && _isEdit
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _card([
                    const _Lbl('Identity'),
                    _field(_jobTitle, 'Job title', required: true),
                    const SizedBox(height: 12),
                    _responsiveRow([
                      DropdownButtonFormField<String?>(
                        initialValue: _departmentId,
                        decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('(none)')),
                          for (final d in _departments)
                            DropdownMenuItem<String?>(value: d['id'] as String, child: Text('${d['code']} — ${d['name']}')),
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
                    TextFormField(
                      controller: _mission,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Mission statement *', border: OutlineInputBorder()),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _card([
                    const _Lbl('Compensation & schedule'),
                    _responsiveRow([
                      DropdownButtonFormField<String>(
                        initialValue: _wageType,
                        decoration: const InputDecoration(labelText: 'Wage type', border: OutlineInputBorder()),
                        items: const ['MONTHLY', 'DAILY', 'HOURLY']
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) => setState(() => _wageType = v!),
                      ),
                      _field(_baseSalary, 'Base salary (PHP)'),
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
                    Row(children: [
                      const _Lbl('Responsibilities'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() => _areas.add(_AreaDraft('', []))),
                        icon: const Icon(Icons.add),
                        label: const Text('Add area'),
                      ),
                    ]),
                    for (int i = 0; i < _areas.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: _areas[i].area,
                                  decoration: const InputDecoration(labelText: 'Area', border: OutlineInputBorder()),
                                  onChanged: (v) => _areas[i].area = v,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setState(() => _areas.removeAt(i)),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            for (int j = 0; j < _areas[i].tasks.length; j++)
                              Padding(
                                padding: const EdgeInsets.only(left: 16, top: 4),
                                child: Row(children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: _areas[i].tasks[j],
                                      decoration: const InputDecoration(labelText: 'Task', border: OutlineInputBorder(), isDense: true),
                                      onChanged: (v) => _areas[i].tasks[j] = v,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => _areas[i].tasks.removeAt(j)),
                                  ),
                                ]),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(left: 16, top: 4),
                              child: TextButton.icon(
                                onPressed: () => setState(() => _areas[i].tasks.add('')),
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
                    Row(children: [
                      const _Lbl('KPIs'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() => _kpis.add(_KpiDraft('', 'Monthly'))),
                        icon: const Icon(Icons.add),
                        label: const Text('Add KPI'),
                      ),
                    ]),
                    for (int i = 0; i < _kpis.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: _kpis[i].metric,
                              decoration: const InputDecoration(labelText: 'Metric', border: OutlineInputBorder(), isDense: true),
                              onChanged: (v) => _kpis[i].metric = v,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: _kpis[i].frequency,
                              decoration: const InputDecoration(labelText: 'Frequency', border: OutlineInputBorder(), isDense: true),
                              onChanged: (v) => _kpis[i].frequency = v,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _kpis.removeAt(i)),
                          ),
                        ]),
                      ),
                  ]),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading ? null : _save,
                      child: _loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save'),
                    ),
                  ]),
                ],
              ),
            ),
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
    return Row(children: [
      for (int i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        Expanded(child: children[i]),
      ],
    ]);
  }

  Widget _card(List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  Widget _field(TextEditingController c, String label, {bool required = false}) => TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label + (required ? ' *' : ''), border: const OutlineInputBorder()),
        validator: required ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null : null,
      );
}

class _AreaDraft {
  String area;
  List<String> tasks;
  _AreaDraft(this.area, this.tasks);
}

class _KpiDraft {
  String metric;
  String frequency;
  _KpiDraft(this.metric, this.frequency);
}

class _Lbl extends StatelessWidget {
  final String text;
  const _Lbl(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      );
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  const _DatePickerField({required this.label, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: InkWell(onTap: onTap, child: Text(value.toIso8601String().substring(0, 10))),
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
