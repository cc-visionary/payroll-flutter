import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/kpi.dart';
import '../../../data/models/kpi_goal.dart';
import '../../../data/models/role_kpi.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../documents/providers.dart' show roleScorecardByIdProvider;
import '../../kpi_library/kpi_definition_form.dart';
import '../../kpi_library/kpi_measurable.dart';
import '../../kpi_library/kpi_reading.dart';
import '../removal_lifecycle.dart';
import '../tabs/role_view_tab.dart' show ownerComputedProvider;
import '../wp_providers.dart';

/// Fixed sample counts for the live preview only — never sent anywhere. They
/// exist purely so a manager editing a goal can see roughly what a reading
/// against it would look like before any real numbers exist. Chosen simply:
/// 3 out of 100, a plausible "a few things happened out of a normal-sized
/// batch" for a RATIO/PERCENT KPI; for a plain COUNT/CURRENCY/DURATION KPI
/// only the numerator (3) is used.
const _previewNumerator = 3.0;
const _previewDenominator = 100.0;

/// The third pane of the role workbench: this card's `role_scorecard_kpis`
/// links — what bar THIS role must clear on each measurable. The `kpis`
/// library row (name, unit, cadence, and the EOS definition fields) is
/// authored elsewhere (the KPI Library dialog, or inline here for a
/// brand-new KPI via [KpiDefinitionForm]); this pane only ever edits the
/// per-role goal.
///
/// `target` and `frequency` are legacy free-text columns the card PDF and
/// contract templates still read. They are DERIVED here — from the
/// structured [KpiGoal] and the KPI's cadence — and never typed into
/// directly, so they can never drift from the goal a manager actually set.
///
/// Like [ResponsibilitiesPane], this pane holds its own local mutable draft
/// list and has one `Save` button at the bottom, because
/// `saveRoleScorecardKpis` replaces a card's entire KPI-link set in one call
/// — it is not built for incremental per-row saves.
class KpisPane extends ConsumerStatefulWidget {
  const KpisPane({super.key, required this.cardId, required this.companyId});

  final String cardId;
  final String companyId;

  @override
  ConsumerState<KpisPane> createState() => _KpisPaneState();
}

class _KpisPaneState extends ConsumerState<KpisPane> {
  /// True once [_links] has been captured from `roleKpisProvider`'s first
  /// successful load in this build cycle. Reset to false right after this
  /// pane's own successful save, so the NEXT provider emission (post
  /// invalidation) re-captures fresh server state rather than trusting local
  /// optimistic state — see `ResponsibilitiesPane._captured` for the same
  /// pattern and its rationale.
  bool _captured = false;
  final List<_KpiLinkDraft> _links = [];

  bool _saving = false;
  String? _error;

  void _captureFrom(List<RoleKpi> kpis) {
    _links
      ..clear()
      ..addAll(kpis.map(_KpiLinkDraft.fromRoleKpi));
    _captured = true;
  }

  void _invalidateAfterSave() {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(ownerComputedProvider);
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(wpTaskAssignmentsProvider);
    ref.invalidate(roleScorecardByIdProvider(widget.cardId));
    ref.invalidate(roleKpisProvider(widget.cardId));
    // Force a resync from the next successful load rather than trust local
    // state, which a partially-failed save could have left disagreeing with
    // the server.
    _captured = false;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // A row with neither a picked/created kpiId nor a name typed into it
      // describes nothing yet — skip it rather than send a link the
      // repository can't resolve.
      final saveable = _links.where((d) => d.name.trim().isNotEmpty).toList();
      final links = [
        for (final d in saveable)
          KpiLinkInput(
            kpiId: d.kpiId,
            name: d.name.trim(),
            target: d.legacyTarget ?? '',
            frequency: d.legacyFrequency ?? '',
            goal: d.goal,
            unit: d.unit,
            // Required. The repository's saveRoleScorecardKpis deliberately
            // does NOT fall back to `kpi.cadence` for an existing library KPI
            // (see that method's comment) because it previously silently
            // rewrote every link's frequency to "Weekly" on any card save.
            // This pane is the caller that must supply the real value on
            // every link — sourced from the picked library KPI, or from the
            // KpiDefinitionForm draft for a brand-new one, never a bare
            // 'WEEKLY' default written by this pane itself.
            cadence: d.cadence,
          ),
      ];
      await ref
          .read(roleScorecardRepositoryProvider)
          .saveRoleScorecardKpis(widget.cardId, widget.companyId, links);
      _invalidateAfterSave();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('KPIs saved.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addExisting(Kpi kpi) {
    setState(() {
      _links.add(
        _KpiLinkDraft(
          kpiId: kpi.id,
          name: kpi.name,
          unit: kpi.unit,
          cadence: kpi.cadence,
          valueType: kpi.valueType,
          numeratorLabel: kpi.numeratorLabel,
          numeratorSource: kpi.numeratorSource,
          denominatorLabel: kpi.denominatorLabel,
          denominatorSource: kpi.denominatorSource,
        ),
      );
    });
  }

  void _remove(_KpiLinkDraft draft) {
    setState(() => _links.remove(draft));
  }

  /// Explicit resync: `roleKpisProvider` is watched, but [_captured] only
  /// flips false right after THIS pane's own save (see its doc comment), so
  /// another screen invalidating the same provider — e.g. the KPI Library
  /// dialog editing this KPI's unit, or a different workbench tab touching
  /// the card — would otherwise leave [_links] silently stale beside a
  /// provider that has already moved on (the exact gap Task 4's
  /// `ResponsibilitiesPane` was flagged for and never closed). This discards
  /// any unsaved local edits, same trade-off `_invalidateAfterSave` already
  /// makes after a successful save.
  void _resync() {
    ref.invalidate(roleKpisProvider(widget.cardId));
    setState(() => _captured = false);
  }

  @override
  Widget build(BuildContext context) {
    final kpisAsync = ref.watch(roleKpisProvider(widget.cardId));
    final library =
        ref.watch(kpiLibraryProvider).asData?.value ?? const <Kpi>[];
    final libraryById = {for (final k in library) k.id: k};

    return kpisAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load KPIs: $e'),
      ),
      data: (kpis) {
        if (!_captured) _captureFrom(kpis);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'KPIs',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (_saving) ...[
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    IconButton(
                      key: const ValueKey('kpis-pane-resync'),
                      tooltip:
                          'Reload from the server — discards unsaved changes '
                          'on this pane',
                      onPressed: _saving ? null : _resync,
                      icon: const Icon(Icons.refresh),
                    ),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _showAddDialog(context, library),
                      icon: const Icon(Icons.add),
                      label: const Text('Add KPI'),
                    ),
                  ],
                ),
                if (_links.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No KPIs are tracked on this role yet.'),
                  )
                else
                  for (final draft in _links)
                    _buildRow(context, draft, libraryById),
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
        );
      },
    );
  }

  /// Whether [draft] is "defined" for measurability purposes. An existing
  /// library KPI's definition fields aren't carried on the `RoleKpi` row (its
  /// embed only selects name/unit/cadence), so they're cross-referenced
  /// against the full library list here. A brand-new draft carries its own
  /// definition fields directly (from the [KpiDefinitionForm] the manager
  /// just filled in). Either way, a library row that can't be found (still
  /// loading, or not in the active list) is treated as not-defined — a safe
  /// default, never a crash.
  bool _isDefined(_KpiLinkDraft draft, Map<String, Kpi> libraryById) {
    final lib = draft.kpiId == null ? null : libraryById[draft.kpiId];
    final valueType = lib?.valueType ?? draft.valueType;
    final unit = lib?.unit ?? draft.unit;
    final numeratorLabel = lib?.numeratorLabel ?? draft.numeratorLabel;
    final numeratorSource = lib?.numeratorSource ?? draft.numeratorSource;
    final denominatorLabel = lib?.denominatorLabel ?? draft.denominatorLabel;
    final denominatorSource =
        lib?.denominatorSource ?? draft.denominatorSource;
    return isKpiDefined(
      valueType: valueType,
      unit: unit,
      numeratorLabel: numeratorLabel,
      numeratorSource: numeratorSource,
      denominatorLabel: denominatorLabel,
      denominatorSource: denominatorSource,
    );
  }

  Widget _buildRow(
    BuildContext context,
    _KpiLinkDraft draft,
    Map<String, Kpi> libraryById,
  ) {
    final key = identityHashCode(draft);
    // goal == null short-circuits isMeasurableForRole to false either way, so
    // the defined lookup can be skipped for those rows.
    final defined = draft.goal == null ? false : _isDefined(draft, libraryById);
    final measurable = isMeasurableForRole(defined: defined, goal: draft.goal);
    final suggestion = draft.goal == null && (draft.legacyTarget ?? '').isNotEmpty
        ? parseLegacyTarget(draft.legacyTarget)
        : null;

    double? previewValue;
    if (draft.goal != null) {
      previewValue = computeReadingValue(
        valueType: draft.valueType,
        unit: draft.unit,
        numerator: _previewNumerator,
        denominator: _previewDenominator,
      );
    }
    final onTrack = isOnTrack(previewValue, draft.goal);

    return Padding(
      key: ValueKey('kpi-row-$key'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.name.isEmpty ? '(unnamed KPI)' : draft.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (draft.cadence != null) ...[
                Text(
                  frequencyLabelFromCadence(draft.cadence) ?? draft.cadence!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                key: ValueKey('kpi-remove-$key'),
                tooltip: 'Remove KPI',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  // removalActionForKpiLink always returns delete today
                  // (Spec B, not yet built, is what would ever flip
                  // hasLogs to true) — wired in now so that future flip is
                  // a one-line change.
                  final action = removalActionForKpiLink(hasLogs: false);
                  if (action == RemovalAction.delete) _remove(draft);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _goalEditor(context, draft, key),
          const SizedBox(height: 6),
          if (draft.goal != null)
            Text(
              'Goal: ${formatGoal(draft.goal!, draft.unit)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          if (!measurable)
            _hint(
              context,
              StatusTone.warning,
              'This KPI is not measurable yet — set a goal.',
            ),
          if (suggestion != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _hint(
                    context,
                    StatusTone.info,
                    'Suggested: ${formatGoal(suggestion, draft.unit)}',
                  ),
                ),
                TextButton(
                  key: ValueKey('kpi-accept-suggestion-$key'),
                  onPressed: () => setState(() {
                    draft.direction = suggestion.direction;
                    draft.value = suggestion.value.toString();
                    draft.valueMax = suggestion.valueMax?.toString() ?? '';
                  }),
                  child: const Text('Use suggestion'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Preview (sample ${_previewNumerator.toInt()}/'
            '${_previewDenominator.toInt()}): '
            '${previewValue == null ? '—' : previewValue.toStringAsFixed(1)}'
            ' · ${onTrack == null ? '—' : (onTrack ? 'on track' : 'off track')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, StatusTone tone, String text) {
    final color = StatusPalette.of(context, tone).foreground;
    return Text(text, style: TextStyle(fontSize: 12, color: color));
  }

  Widget _goalEditor(BuildContext context, _KpiLinkDraft draft, int key) {
    final isBetween = draft.direction == GoalDirection.between;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<GoalDirection?>(
            key: ValueKey('kpi-direction-$key'),
            initialValue: draft.direction,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Goal',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('(none)')),
              DropdownMenuItem(value: GoalDirection.gte, child: Text('≥')),
              DropdownMenuItem(value: GoalDirection.lte, child: Text('≤')),
              DropdownMenuItem(value: GoalDirection.eq, child: Text('=')),
              DropdownMenuItem(
                value: GoalDirection.between,
                child: Text('between'),
              ),
            ],
            onChanged: (v) => setState(() => draft.direction = v),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: TextFormField(
            key: ValueKey('kpi-value-$key'),
            initialValue: draft.value,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: isBetween ? 'From' : 'Value',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => draft.value = v),
          ),
        ),
        if (isBetween) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: ValueKey('kpi-value-max-$key'),
              initialValue: draft.valueMax,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'To',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => draft.valueMax = v),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            (draft.unit == null || draft.unit!.trim().isEmpty)
                ? '(no unit)'
                : draft.unit!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Future<void> _showAddDialog(BuildContext context, List<Kpi> library) async {
    final result = await showDialog<_AddKpiResult>(
      context: context,
      builder: (_) => _AddKpiDialog(companyId: widget.companyId, library: library),
    );
    if (result == null) return;
    if (result.existing != null) {
      _addExisting(result.existing!);
    } else if (result.newDraft != null) {
      setState(() {
        final d = _KpiLinkDraft(
          kpiId: null,
          name: result.newName!,
          unit: result.newDraft!.unit,
          // Seeded from the KpiDefinitionForm's emitted draft — that form
          // defaults its own cadence to 'WEEKLY' until the manager changes
          // it. This pane must never hardcode a bare 'WEEKLY' itself.
          cadence: result.newDraft!.cadence,
          valueType: result.newDraft!.valueType,
          numeratorLabel: result.newDraft!.numeratorLabel,
          numeratorSource: result.newDraft!.numeratorSource,
          denominatorLabel: result.newDraft!.denominatorLabel,
          denominatorSource: result.newDraft!.denominatorSource,
        );
        _links.add(d);
      });
    }
  }
}

/// A local, not-yet-persisted draft of one `role_scorecard_kpis` link. Direct
/// text fields ([value], [valueMax]) back the goal editor; [goal] derives
/// from them for the preview and the eventual save.
class _KpiLinkDraft {
  String? kpiId;
  String name;
  String? unit;
  String? cadence;

  // Definition fields, only meaningful for a brand-new (kpiId == null) draft
  // — an existing library KPI's definition is looked up by kpiId instead.
  String? valueType;
  String? numeratorLabel;
  String? numeratorSource;
  String? denominatorLabel;
  String? denominatorSource;

  String? legacyTarget;
  String? legacyFrequency;

  GoalDirection? direction;
  String value;
  String valueMax;

  _KpiLinkDraft({
    required this.kpiId,
    required this.name,
    this.unit,
    this.cadence,
    this.valueType,
    this.numeratorLabel,
    this.numeratorSource,
    this.denominatorLabel,
    this.denominatorSource,
    this.legacyTarget,
    this.legacyFrequency,
    this.direction,
    String? initialValue,
    String? initialValueMax,
  }) : value = initialValue ?? '',
       valueMax = initialValueMax ?? '';

  factory _KpiLinkDraft.fromRoleKpi(RoleKpi kpi) => _KpiLinkDraft(
    kpiId: kpi.kpiId,
    name: kpi.name,
    unit: kpi.unit,
    cadence: kpi.cadence,
    legacyTarget: kpi.target,
    legacyFrequency: kpi.frequency,
    direction: kpi.goal?.direction,
    initialValue: kpi.goal == null ? '' : _trim(kpi.goal!.value),
    initialValueMax: kpi.goal?.valueMax == null
        ? ''
        : _trim(kpi.goal!.valueMax!),
  );

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// The structured goal this draft currently describes, or null if the
  /// manager hasn't picked a direction/value yet.
  KpiGoal? get goal {
    final d = direction;
    if (d == null) return null;
    final v = double.tryParse(value.trim());
    if (v == null) return null;
    if (d == GoalDirection.between) {
      final vMax = double.tryParse(valueMax.trim());
      if (vMax == null || vMax <= v) return null;
      return KpiGoal(direction: d, value: v, valueMax: vMax);
    }
    return KpiGoal(direction: d, value: v);
  }
}

class _AddKpiResult {
  final Kpi? existing;
  final String? newName;
  final KpiDefinitionDraft? newDraft;
  _AddKpiResult.existing(this.existing) : newName = null, newDraft = null;
  _AddKpiResult.newKpi(this.newName, this.newDraft) : existing = null;
}

/// "Add KPI": pick an existing library KPI by name, or define a brand-new
/// one inline via [KpiDefinitionForm] when the typed name doesn't match.
/// Mirrors `role_scorecard_form_screen.dart`'s `_kpiEditor` Autocomplete
/// pattern, minus its free-text target/frequency fields — this pane derives
/// those, it never collects them directly.
class _AddKpiDialog extends ConsumerStatefulWidget {
  const _AddKpiDialog({required this.companyId, required this.library});

  final String companyId;
  final List<Kpi> library;

  @override
  ConsumerState<_AddKpiDialog> createState() => _AddKpiDialogState();
}

class _AddKpiDialogState extends ConsumerState<_AddKpiDialog> {
  final _nameCtl = TextEditingController();
  Kpi? _picked;
  KpiDefinitionDraft _newDraft = KpiDefinitionDraft();

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources =
        ref.watch(kpiSourcesProvider).asData?.value ?? const <String>[];
    final typedMatchesExisting = _picked != null;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add KPI', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Autocomplete<Kpi>(
                initialValue: TextEditingValue(text: _nameCtl.text),
                optionsBuilder: (v) => v.text.isEmpty
                    ? widget.library
                    : widget.library.where(
                        (k) => k.name.toLowerCase().contains(
                          v.text.toLowerCase(),
                        ),
                      ),
                displayStringForOption: (k) => k.name,
                onSelected: (k) => setState(() {
                  _picked = k;
                  _nameCtl.text = k.name;
                }),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'KPI name',
                      helperText:
                          'Pick an existing KPI, or type a new name to '
                          'define one.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      _nameCtl.text = v;
                      _picked = null;
                    }),
                  );
                },
              ),
              if (!typedMatchesExisting && _nameCtl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                KpiDefinitionForm(
                  knownSources: sources,
                  onChanged: (d) => _newDraft = d,
                ),
              ] else if (_picked != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Unit: ${_picked!.unit ?? '(none)'} · '
                  'Cadence: ${_picked!.cadence}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final name = _nameCtl.text.trim();
                      if (name.isEmpty) return;
                      if (_picked != null) {
                        Navigator.pop(context, _AddKpiResult.existing(_picked));
                      } else {
                        Navigator.pop(
                          context,
                          _AddKpiResult.newKpi(name, _newDraft),
                        );
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
