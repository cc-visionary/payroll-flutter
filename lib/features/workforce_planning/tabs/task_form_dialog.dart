import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';

const _tiers = ['Transactional', 'Operational', 'Managerial', 'Strategic'];
const _risks = ['Low', 'Medium', 'High'];

/// Guards a `DropdownButtonFormField`'s `initialValue` against an id that
/// isn't among its current `items` (e.g. a task owned by a now-separated
/// employee, absent from the active roster passed in) — the widget asserts
/// if `initialValue` isn't found among `items`, which would otherwise crash
/// the dialog on open. The underlying state field keeps the original value
/// regardless, so an untouched Save still preserves it.
String? _present(String? id, Iterable<String> ids) =>
    (id != null && ids.contains(id)) ? id : null;

/// Validates the task form. Returns an error message, or null when OK.
String? validateTaskForm({
  required String name,
  required String timesSource,
  String? driverId,
  required String minutesSource,
  String? rateId,
}) {
  if (name.trim().isEmpty) return 'Name is required.';
  if (timesSource == 'driver' && (driverId == null || driverId.isEmpty)) {
    return 'Pick a driver (or switch Times to Manual).';
  }
  if (minutesSource == 'rate' && (rateId == null || rateId.isEmpty)) {
    return 'Pick a rate (or switch Minutes to Manual).';
  }
  return null;
}

/// Builds the WpTask to persist from the raw form values. Pure + testable:
/// nulls the unused times/minutes source field, and preserves the columns the
/// dialog genuinely does not edit (id/companyId/externalRef/notes) from
/// [existing].
///
/// [roleScorecardId] and [responsibilityArea] ARE form-driven — a task IS a role
/// card responsibility, so this dialog can link one to a card + area (or unlink
/// it by passing nulls). They are not preserved from [existing]; pass the
/// existing values through when the form didn't change them.
WpTask buildTaskFromForm({
  WpTask? existing,
  required String companyId,
  required String name,
  String? roleScorecardId,
  String? responsibilityArea,
  String? nodeId,
  String? brandScope,
  String? cadence,
  required String timesSource,
  String? timesManualText,
  String? driverId,
  String? driverFactorText,
  required String minutesSource,
  String? minutesManualText,
  String? rateId,
  String? skillTier,
  String? risk,
  String? capability,
  String? ownerEmployeeId,
  String? hoursPerMonthText,
}) {
  String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
  final direct = double.tryParse((hoursPerMonthText ?? '').trim());
  return WpTask(
    id: existing?.id ?? '',
    companyId: existing?.companyId ?? companyId,
    name: name.trim(),
    nodeId: nodeId,
    brandScope: clean(brandScope),
    cadence: clean(cadence),
    timesSource: direct != null ? 'manual' : timesSource,
    timesManual: direct != null
        ? null
        : (timesSource == 'manual' ? double.tryParse((timesManualText ?? '').trim()) : null),
    driverId: direct != null ? null : (timesSource == 'driver' ? driverId : null),
    driverFactor: double.tryParse((driverFactorText ?? '').trim()) ?? 1,
    minutesSource: direct != null ? 'manual' : minutesSource,
    minutesManual: direct != null
        ? null
        : (minutesSource == 'manual' ? double.tryParse((minutesManualText ?? '').trim()) : null),
    rateId: direct != null ? null : (minutesSource == 'rate' ? rateId : null),
    hoursPerMonth: direct,
    skillTier: skillTier,
    risk: risk,
    capability: clean(capability),
    ownerEmployeeId: ownerEmployeeId,
    externalRef: existing?.externalRef,
    // An area only means something in the context of a card — clearing the card
    // clears the area too, so a task can never carry an orphan area string.
    roleScorecardId: roleScorecardId,
    responsibilityArea: roleScorecardId == null ? null : clean(responsibilityArea),
    notes: existing?.notes,
  );
}

/// Create/edit dialog for a `wp_tasks` row. Caller supplies the dropdown data
/// (nodes/drivers/rates/employees) and persists the returned [WpTask] via
/// `WorkforcePlanningRepository.saveTask`, then invalidates the read providers.
class TaskFormDialog extends StatefulWidget {
  final WpTask? existing;
  final String companyId;
  final List<WpNode> nodes;
  final List<WpDriver> drivers;
  final List<WpRate> rates;
  final List<Employee> employees;

  /// Role cards, for linking this task to a card + responsibility area. A task
  /// IS a card responsibility, so this is what makes the Tasks tab a peer of the
  /// card editor rather than a read-mostly view.
  final List<RoleScorecard> cards;
  const TaskFormDialog({
    super.key,
    this.existing,
    required this.companyId,
    required this.nodes,
    required this.drivers,
    required this.rates,
    required this.employees,
    this.cards = const [],
  });

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _brand = TextEditingController(text: widget.existing?.brandScope ?? '');
  late final _cadence = TextEditingController(text: widget.existing?.cadence ?? '');
  late final _capability = TextEditingController(text: widget.existing?.capability ?? '');
  late final _timesManual = TextEditingController(
      text: widget.existing?.timesManual?.toString() ?? '');
  late final _driverFactor = TextEditingController(
      text: (widget.existing?.driverFactor ?? 1).toString());
  late final _minutesManual = TextEditingController(
      text: widget.existing?.minutesManual?.toString() ?? '');
  late final _hoursCtl = TextEditingController(
      text: widget.existing?.hoursPerMonth?.toString() ?? '');

  late String _timesSource = widget.existing?.timesSource ?? 'manual';
  late String _minutesSource = widget.existing?.minutesSource ?? 'manual';
  late String? _nodeId = widget.existing?.nodeId;
  late String? _driverId = widget.existing?.driverId;
  late String? _rateId = widget.existing?.rateId;
  late String? _tier = widget.existing?.skillTier;
  late String? _risk = widget.existing?.risk;
  late String? _ownerId = widget.existing?.ownerEmployeeId;
  late String? _cardId = widget.existing?.roleScorecardId;
  late String? _area = widget.existing?.responsibilityArea;

  /// The selected card's responsibility areas, in authored order.
  List<String> get _areasForCard {
    if (_cardId == null) return const [];
    for (final c in widget.cards) {
      if (c.id == _cardId) return [for (final a in c.responsibilities) a.area];
    }
    return const [];
  }
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _brand, _cadence, _capability, _timesManual, _driverFactor, _minutesManual, _hoursCtl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final err = validateTaskForm(
      name: _name.text,
      timesSource: _timesSource,
      driverId: _driverId,
      minutesSource: _minutesSource,
      rateId: _rateId,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final task = buildTaskFromForm(
      existing: widget.existing,
      companyId: widget.companyId,
      name: _name.text,
      roleScorecardId: _cardId,
      responsibilityArea: _area,
      nodeId: _nodeId,
      brandScope: _brand.text,
      cadence: _cadence.text,
      timesSource: _timesSource,
      timesManualText: _timesManual.text,
      driverId: _driverId,
      driverFactorText: _driverFactor.text,
      minutesSource: _minutesSource,
      minutesManualText: _minutesManual.text,
      rateId: _rateId,
      skillTier: _tier,
      risk: _risk,
      capability: _capability.text,
      ownerEmployeeId: _ownerId,
      hoursPerMonthText: _hoursCtl.text,
    );
    Navigator.pop(context, task);
  }

  InputDecoration _dec(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New task' : 'Edit task'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _name, autofocus: true, decoration: _dec('Name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _present(_nodeId, widget.nodes.map((n) => n.id)),
              isExpanded: true,
              decoration: _dec('Value-chain node'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                ...widget.nodes.map((n) => DropdownMenuItem<String?>(value: n.id, child: Text(n.name))),
              ],
              onChanged: (v) => setState(() => _nodeId = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _brand, decoration: _dec('Brand / scope'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _cadence, decoration: _dec('Cadence (label)'))),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _hoursCtl,
              decoration: const InputDecoration(
                labelText: 'Workload (hours / month)',
                hintText: 'e.g. 10',
                helperText: 'One number. Leave blank to drive by volume below.',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: _hoursCtl.text.trim().isEmpty &&
                  (widget.existing?.timesSource == 'driver' ||
                      widget.existing?.minutesSource == 'rate'),
              title: const Text('Advanced: scales with volume'),
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Times source
                  Text('Times per month', style: Theme.of(context).textTheme.labelLarge),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'manual', label: Text('Manual')),
                      ButtonSegment(value: 'driver', label: Text('Driver')),
                    ],
                    selected: {_timesSource},
                    onSelectionChanged: (s) => setState(() => _timesSource = s.first),
                  ),
                  const SizedBox(height: 8),
                  if (_timesSource == 'manual')
                    TextField(controller: _timesManual, keyboardType: TextInputType.number, style: AppTheme.mono(context), decoration: _dec('Times / month'))
                  else
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue:
                              _present(_driverId, widget.drivers.map((d) => d.id)),
                          isExpanded: true,
                          decoration: _dec('Driver'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('— Pick —')),
                            ...widget.drivers.map((d) => DropdownMenuItem<String?>(value: d.id, child: Text(d.name))),
                          ],
                          onChanged: (v) => setState(() => _driverId = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(width: 110, child: TextField(controller: _driverFactor, keyboardType: TextInputType.number, style: AppTheme.mono(context), decoration: _dec('× factor'))),
                    ]),
                  const SizedBox(height: 16),
                  // Minutes source
                  Text('Minutes each', style: Theme.of(context).textTheme.labelLarge),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'manual', label: Text('Manual')),
                      ButtonSegment(value: 'rate', label: Text('Rate')),
                    ],
                    selected: {_minutesSource},
                    onSelectionChanged: (s) => setState(() => _minutesSource = s.first),
                  ),
                  const SizedBox(height: 8),
                  if (_minutesSource == 'manual')
                    TextField(controller: _minutesManual, keyboardType: TextInputType.number, style: AppTheme.mono(context), decoration: _dec('Minutes each'))
                  else
                    DropdownButtonFormField<String?>(
                      initialValue: _present(_rateId, widget.rates.map((r) => r.id)),
                      isExpanded: true,
                      decoration: _dec('Rate'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('— Pick —')),
                        ...widget.rates.map((r) => DropdownMenuItem<String?>(value: r.id, child: Text(r.name))),
                      ],
                      onChanged: (v) => setState(() => _rateId = v),
                    ),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _present(_tier, _tiers),
                  isExpanded: true,
                  decoration: _dec('Skill tier'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                    ..._tiers.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                  ],
                  onChanged: (v) => setState(() => _tier = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _present(_risk, _risks),
                  isExpanded: true,
                  decoration: _dec('Risk'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                    ..._risks.map((r) => DropdownMenuItem<String?>(value: r, child: Text(r))),
                  ],
                  onChanged: (v) => setState(() => _risk = v),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _capability, decoration: _dec('Capability requirement')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue:
                  _present(_ownerId, widget.employees.map((e) => e.id)),
              isExpanded: true,
              decoration: _dec('Owner'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— Unassigned —')),
                ...widget.employees.map((e) =>
                    DropdownMenuItem<String?>(value: e.id, child: Text('${e.firstName} ${e.lastName}'))),
              ],
              onChanged: (v) => setState(() => _ownerId = v),
            ),
            if (widget.cards.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Responsibility', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _present(_cardId, widget.cards.map((c) => c.id)),
                isExpanded: true,
                decoration: _dec('Role card'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('— Not a card responsibility —')),
                  ...widget.cards.map((c) => DropdownMenuItem<String?>(
                      value: c.id, child: Text(c.jobTitle))),
                ],
                // Areas belong to a card, so changing the card invalidates the
                // area — clear it rather than carry a stale one across.
                onChanged: (v) => setState(() {
                  _cardId = v;
                  _area = null;
                }),
              ),
              if (_cardId != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _present(_area, _areasForCard),
                  isExpanded: true,
                  decoration: _dec('Responsibility area'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— None —')),
                    ..._areasForCard.map((a) =>
                        DropdownMenuItem<String?>(value: a, child: Text(a))),
                  ],
                  onChanged: (v) => setState(() => _area = v),
                ),
              ],
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
