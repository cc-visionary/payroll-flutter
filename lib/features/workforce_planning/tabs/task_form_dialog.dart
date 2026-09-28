import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../duplicate_check.dart';
import '../duplicate_warning.dart';
import '../frequency.dart';

const _tiers = ['Transactional', 'Operational', 'Managerial', 'Strategic'];
const _risks = ['Low', 'Medium', 'High'];
const _criticalities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];

String? _present(String? id, Iterable<String> ids) =>
    (id != null && ids.contains(id)) ? id : null;

double? _num(String? s) => double.tryParse((s ?? '').trim());

/// The collapsed "More details" fields. None of them affects load.
class More {
  final String? nodeId, brandScope, skillTier, risk, capability, criticality, notes;
  final bool isEssential, isExpectation;
  const More({
    this.nodeId, this.brandScope, this.skillTier, this.risk, this.capability,
    this.criticality, this.notes, this.isEssential = true, this.isExpectation = false,
  });
  factory More.of(WpTask? t) => t == null
      ? const More()
      : More(
          nodeId: t.nodeId, brandScope: t.brandScope, skillTier: t.skillTier,
          risk: t.risk, capability: t.capability, criticality: t.criticality,
          notes: t.notes, isEssential: t.isEssential, isExpectation: t.isExpectation,
        );
}

String? validateTaskForm({
  required String name,
  required String? roleId,
  required TaskFrequency frequency,
  String? minutesText,
  String? customHoursText,
  String? driverId,
}) {
  if (name.trim().isEmpty) return 'Name is required.';
  if (roleId == null) return 'Pick the role that does this.';
  if (frequency == TaskFrequency.custom) {
    return _num(customHoursText) == null ? 'Enter hours per month.' : null;
  }
  if (_num(minutesText) == null) return 'How long does it take each time?';
  if (frequency == TaskFrequency.perOrder && (driverId == null || driverId.isEmpty)) {
    return 'Pick what the orders are counted from.';
  }
  return null;
}

WpTask buildTaskFromForm({
  WpTask? existing,
  required String companyId,
  required String name,
  required String roleId,
  String? responsibilityArea,
  required TaskFrequency frequency,
  String? minutesText,
  String? customHoursText,
  String? driverId,
  More more = const More(),
}) {
  final custom = frequency == TaskFrequency.custom;
  final perOrder = frequency == TaskFrequency.perOrder;
  String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
  return WpTask(
    id: existing?.id ?? '',
    companyId: existing?.companyId ?? companyId,
    name: name.trim(),
    roleScorecardId: roleId,
    responsibilityArea: clean(responsibilityArea ?? existing?.responsibilityArea),
    cadence: custom ? null : frequency.token,
    timesSource: perOrder ? 'driver' : 'manual',
    timesManual: (custom || perOrder) ? null : frequency.timesPerMonth,
    driverId: perOrder ? driverId : null,
    driverFactor: existing?.driverFactor ?? 1,
    minutesSource: 'manual',
    minutesManual: custom ? null : _num(minutesText),
    hoursPerMonth: custom ? _num(customHoursText) : null,
    nodeId: more.nodeId,
    brandScope: clean(more.brandScope),
    skillTier: more.skillTier,
    risk: more.risk,
    capability: clean(more.capability),
    criticality: more.criticality,
    notes: clean(more.notes),
    isEssential: more.isEssential,
    isExpectation: more.isExpectation,
    // Kept, not edited here: the DB still carries them for rollback.
    ownerEmployeeId: existing?.ownerEmployeeId,
    externalRef: existing?.externalRef,
    areaSort: existing?.areaSort ?? 0,
    taskSort: existing?.taskSort ?? 0,
    status: existing?.status ?? 'ACTIVE',
  );
}

/// Add/edit a task: name, how often x how long, and the one role that does
/// it. Everything else sits under "More details" because none of it changes
/// anyone's load.
class TaskFormDialog extends StatefulWidget {
  final WpTask? existing;
  final String companyId;
  final List<RoleScorecard> cards;
  final List<WpNode> nodes;
  final List<WpDriver> drivers;
  final String? initialRoleId;
  final List<WpTask> duplicateCheckPool;

  /// Role id -> active holders, for the "split across N people" line.
  final Map<String, int> holderCountByRole;

  const TaskFormDialog({
    super.key,
    this.existing,
    required this.companyId,
    required this.cards,
    this.nodes = const [],
    this.drivers = const [],
    this.initialRoleId,
    this.duplicateCheckPool = const [],
    this.holderCountByRole = const {},
  });

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late TaskFrequency _frequency = widget.existing == null
      ? TaskFrequency.weekly
      : frequencyOf(widget.existing!);
  late final _minutes = TextEditingController(
    text: widget.existing == null ? '' : (minutesOf(widget.existing!)?.toString() ?? ''),
  );
  late final _customHours = TextEditingController(
    text: widget.existing == null ? '' : (customHoursOf(widget.existing!)?.toString() ?? ''),
  );
  late String? _roleId = widget.existing?.roleScorecardId ?? widget.initialRoleId;
  late String? _driverId = widget.existing?.driverId ??
      widget.drivers.where((d) => d.name.toLowerCase().contains('order')).firstOrNull?.id;

  // "More details" — one field per state variable so "— None —" can clear it.
  late final More _initial = More.of(widget.existing);
  late String? _nodeId = _initial.nodeId;
  late String? _tier = _initial.skillTier;
  late String? _risk = _initial.risk;
  late String? _criticality = _initial.criticality;
  late bool _essential = _initial.isEssential;
  late final _brand = TextEditingController(text: _initial.brandScope ?? '');
  late final _capability = TextEditingController(text: _initial.capability ?? '');
  late final _notes = TextEditingController(text: _initial.notes ?? '');

  bool _showMore = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _minutes, _customHours, _brand, _capability, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) =>
      InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder());

  double get _driverVolume {
    for (final d in widget.drivers) {
      if (d.id == _driverId) return d.value;
    }
    return 0;
  }

  String _previewLine() {
    final h = previewHoursPerMonth(
      frequency: _frequency,
      minutes: _num(_minutes.text),
      customHours: _num(_customHours.text),
      driverVolume: _driverVolume,
      driverFactor: widget.existing?.driverFactor ?? 1,
    );
    final n = _roleId == null ? 0 : (widget.holderCountByRole[_roleId] ?? 0);
    final who = _roleId == null
        ? ''
        : n == 0
            ? ' · nobody holds this role yet'
            : ' · split across $n ${n == 1 ? 'person' : 'people'}';
    return '≈ ${h.toStringAsFixed(1)} h/mo$who';
  }

  void _save() {
    final err = validateTaskForm(
      name: _name.text, roleId: _roleId, frequency: _frequency,
      minutesText: _minutes.text, customHoursText: _customHours.text, driverId: _driverId,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final more = More(
      nodeId: _nodeId, brandScope: _brand.text, skillTier: _tier, risk: _risk,
      capability: _capability.text, criticality: _criticality, notes: _notes.text,
      isEssential: _initial.isExpectation ? false : _essential,
      isExpectation: _initial.isExpectation,
    );
    Navigator.pop(context, buildTaskFromForm(
      existing: widget.existing, companyId: widget.companyId, name: _name.text,
      roleId: _roleId!, frequency: _frequency, minutesText: _minutes.text,
      customHoursText: _customHours.text, driverId: _driverId, more: more,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final roleIds = widget.cards.map((c) => c.id);
    final custom = _frequency == TaskFrequency.custom;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New task' : 'Edit task'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _name, decoration: _dec('Name'), onChanged: (_) => setState(() {})),
              if (widget.duplicateCheckPool.isNotEmpty)
                SimilarNameWarning(
                  matches: findSimilarAccountabilities(
                    typed: _name.text,
                    all: widget.duplicateCheckPool,
                    excludeId: widget.existing?.id,
                  ),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<TaskFrequency>(
                    isExpanded: true,
                    initialValue: _frequency,
                    decoration: _dec('How often'),
                    items: [for (final f in TaskFrequency.values) DropdownMenuItem(value: f, child: Text(f.label))],
                    onChanged: (f) => setState(() => _frequency = f ?? _frequency),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: custom
                      ? TextFormField(controller: _customHours, decoration: _dec('Hours / month', hint: 'e.g. 10'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))
                      : TextFormField(controller: _minutes, decoration: _dec('Minutes each time', hint: 'e.g. 15'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
                ),
              ]),
              if (_frequency == TaskFrequency.perOrder) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _present(_driverId, widget.drivers.map((d) => d.id)),
                  decoration: _dec('Orders counted from'),
                  items: [for (final d in widget.drivers) DropdownMenuItem(value: d.id, child: Text('${d.name} (${d.value.toStringAsFixed(0)}/mo)'))],
                  onChanged: (v) => setState(() => _driverId = v),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _present(_roleId, roleIds),
                decoration: _dec('Role that does it'),
                items: [for (final c in widget.cards) DropdownMenuItem(value: c.id, child: Text(c.jobTitle))],
                onChanged: (v) => setState(() => _roleId = v),
              ),
              const SizedBox(height: 8),
              Text(_previewLine(), style: AppTheme.mono(context)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showMore = !_showMore),
                  icon: Icon(_showMore ? Icons.expand_less : Icons.expand_more),
                  label: const Text('More details'),
                ),
              ),
              if (_showMore) ..._moreFields(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _pick(String label, String? value, List<String> options, void Function(String?) set) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<String?>(
          isExpanded: true,
          initialValue: _present(value, options),
          decoration: _dec(label),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => setState(() => set(v)),
        ),
      );

  Widget _text(TextEditingController c, String label, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(controller: c, decoration: _dec(label), maxLines: maxLines),
  );

  List<Widget> _moreFields() => [
    _text(_notes, 'Notes', maxLines: 2),
    _pick('Criticality', _criticality, _criticalities, (v) => _criticality = v),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Essential function'),
      value: _initial.isExpectation ? false : _essential,
      onChanged: _initial.isExpectation ? null : (v) => setState(() => _essential = v),
    ),
    _pick('Skill tier', _tier, _tiers, (v) => _tier = v),
    _pick('Risk', _risk, _risks, (v) => _risk = v),
    _text(_capability, 'Capability requirement'),
    _text(_brand, 'Brand / scope'),
    if (widget.nodes.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<String?>(
          isExpanded: true,
          initialValue: _present(_nodeId, widget.nodes.map((n) => n.id)),
          decoration: _dec('Value-chain node'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
            for (final n in widget.nodes) DropdownMenuItem(value: n.id, child: Text(n.name)),
          ],
          onChanged: (v) => setState(() => _nodeId = v),
        ),
      ),
  ];
}
