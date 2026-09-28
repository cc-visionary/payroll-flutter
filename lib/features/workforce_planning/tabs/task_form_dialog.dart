import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../area_placement.dart';
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
  String? area,
  // True when [existing] is rate-sourced (minutesSource == 'rate') — a blank
  // minutes field then means "keep the rate", not "missing input".
  bool minutesFromRate = false,
}) {
  if (name.trim().isEmpty) return 'Name is required.';
  if (roleId == null) return 'Pick the role that does this.';
  if ((area ?? '').trim().isEmpty) {
    return 'Pick the area this sits under on the role card.';
  }
  if (frequency == TaskFrequency.custom) {
    return _num(customHoursText) == null ? 'Enter hours per month.' : null;
  }
  if (!minutesFromRate && _num(minutesText) == null) {
    return 'How long does it take each time?';
  }
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
  // The role's default area (see defaultAreaFor), used when no area was
  // picked and the role is new or changed.
  String defaultArea = kDefaultResponsibilityArea,
}) {
  final custom = frequency == TaskFrequency.custom;
  final perOrder = frequency == TaskFrequency.perOrder;
  String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
  // An area only means something in the context of the role that carries
  // it — changing the role orphans whatever area the old role had, so the
  // new role's default applies unless the user picked one (ruling R11: a
  // task on a role always has an area of that role).
  final roleUnchanged = existing != null && roleId == existing.roleScorecardId;
  final typedMinutes = _num(minutesText);
  // A rate-sourced task (minutes_source = 'rate') keeps its rate link when
  // the minutes field is left blank; typing a number overrides to manual.
  final keepsRate = !custom && existing?.minutesSource == 'rate' && typedMinutes == null;
  return WpTask(
    id: existing?.id ?? '',
    companyId: existing?.companyId ?? companyId,
    name: name.trim(),
    roleScorecardId: roleId,
    responsibilityArea: clean(responsibilityArea) ??
        (roleUnchanged ? clean(existing.responsibilityArea) : null) ??
        defaultArea,
    cadence: custom ? null : frequency.token,
    timesSource: perOrder ? 'driver' : 'manual',
    timesManual: (custom || perOrder) ? null : frequency.timesPerMonth,
    driverId: perOrder ? driverId : null,
    driverFactor: existing?.driverFactor ?? 1,
    minutesSource: keepsRate ? 'rate' : 'manual',
    minutesManual: (custom || keepsRate) ? null : typedMinutes,
    rateId: keepsRate ? existing?.rateId : null,
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

/// Add/edit a task: name, how often x how long, the one role that does it and
/// the area it sits under on that role's card. Everything else sits under
/// "More details" because none of it changes anyone's load or the role card.
///
/// The caller positions the saved task with `placeInArea` (area_placement.dart).
class TaskFormDialog extends StatefulWidget {
  final WpTask? existing;
  final String companyId;
  final List<RoleScorecard> cards;
  final List<WpNode> nodes;
  final List<WpDriver> drivers;

  /// Rates, so an existing rate-sourced task ([WpTask.minutesSource] ==
  /// `'rate'`) can show what minutes it's actually using while its Minutes
  /// field sits blank — see [buildTaskFromForm]'s `keepsRate`.
  final List<WpRate> rates;
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
    this.rates = const [],
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
    text: widget.existing == null
        ? ''
        : (customHoursOf(widget.existing!, rateMinutes: _linkedRate?.minutesEach)?.toString() ?? ''),
  );
  late String? _roleId = widget.existing?.roleScorecardId ?? widget.initialRoleId;

  // Area on the role card (ruling R11). Picked from the role's own areas, or
  // typed as a new one ([_typingNewArea] — always so when the role has none).
  static const _newAreaSentinel = '\u0000new-area';
  String? _area;
  bool _typingNewArea = false;
  final _newArea = TextEditingController();
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

  /// The rate [widget.existing] was sourced from, if it still exists in
  /// [widget.rates]. Non-null only drives the Minutes hint/preview fallback
  /// while the field is blank — [buildTaskFromForm] decides persistence off
  /// `existing.minutesSource`/`rateId` directly, not off this lookup.
  WpRate? get _linkedRate {
    final id = widget.existing?.rateId;
    if (id == null) return null;
    for (final r in widget.rates) {
      if (r.id == id) return r;
    }
    return null;
  }

  bool get _minutesFromRate => widget.existing?.minutesSource == 'rate';

  /// Minutes to use when the field is blank and the task is rate-sourced —
  /// what "keep the rate" actually means for the preview line.
  double? get _effectiveMinutes => _num(_minutes.text) ?? (_minutesFromRate ? _linkedRate?.minutesEach : null);

  String get _minutesHint {
    final rate = _linkedRate;
    if (_minutesFromRate && rate != null) {
      return 'Rate: ${rate.name} · ${rate.minutesEach.toStringAsFixed(0)} min';
    }
    return 'e.g. 15';
  }

  RoleScorecard? get _card {
    for (final c in widget.cards) {
      if (c.id == _roleId) return c;
    }
    return null;
  }

  /// The selected role's areas, plus the task's own area when it is being
  /// edited on its own role and that area is not (yet) on the card.
  List<String> get _areaOptions {
    final options = areaOptionsFor(_card);
    final own = _ownArea;
    if (own != null && !options.any((o) => o.toLowerCase() == own.toLowerCase())) {
      return [...options, own];
    }
    return options;
  }

  /// The edited task's current area, while the role is still its own.
  String? get _ownArea {
    final e = widget.existing;
    if (e == null || e.roleScorecardId != _roleId) return null;
    final a = e.responsibilityArea?.trim();
    return (a == null || a.isEmpty) ? null : a;
  }

  /// Keeps the task's own area on its own role; otherwise the role's default.
  void _resetArea() {
    final options = _areaOptions;
    final own = _ownArea;
    _area = own == null
        ? defaultAreaFor(_card)
        : options.firstWhere((o) => o.toLowerCase() == own.toLowerCase(), orElse: () => own);
    _typingNewArea = options.isEmpty;
    _newArea.text = options.isEmpty ? _area! : '';
  }

  String get _effectiveArea => _typingNewArea ? _newArea.text : (_area ?? '');

  @override
  void initState() {
    super.initState();
    _resetArea();
  }

  @override
  void dispose() {
    for (final c in [_name, _minutes, _customHours, _brand, _capability, _notes, _newArea]) {
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
      minutes: _effectiveMinutes,
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
      area: _effectiveArea, minutesFromRate: _minutesFromRate,
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
      roleId: _roleId!, responsibilityArea: _effectiveArea, frequency: _frequency,
      minutesText: _minutes.text, customHoursText: _customHours.text, driverId: _driverId,
      more: more, defaultArea: defaultAreaFor(_card),
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
                      : TextFormField(controller: _minutes, decoration: _dec('Minutes each time', hint: _minutesHint),
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
                onChanged: (v) => setState(() {
                  _roleId = v;
                  _resetArea();
                }),
              ),
              if (_roleId != null) ..._areaFields(),
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

  /// "Area": decides where the task appears on the role card, its PDF and
  /// the contract's Annex A — so it sits in the main form, under the role.
  List<Widget> _areaFields() {
    final options = _areaOptions;
    const helper = 'Where it appears on the role card';
    if (options.isEmpty) {
      return [
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('area-text-$_roleId'),
          controller: _newArea,
          decoration: _dec('Area').copyWith(helperText: helper),
        ),
      ];
    }
    return [
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        // Rebuilt per role so the shown value follows the role's default.
        key: ValueKey('area-$_roleId'),
        isExpanded: true,
        initialValue: _typingNewArea ? _newAreaSentinel : _area,
        decoration: _dec('Area').copyWith(helperText: helper),
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          const DropdownMenuItem(value: _newAreaSentinel, child: Text('+ New area…')),
        ],
        onChanged: (v) => setState(() {
          if (v == _newAreaSentinel) {
            _typingNewArea = true;
          } else {
            _typingNewArea = false;
            _area = v;
          }
        }),
      ),
      if (_typingNewArea) ...[
        const SizedBox(height: 12),
        TextFormField(controller: _newArea, autofocus: true, decoration: _dec('New area name')),
      ],
    ];
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
