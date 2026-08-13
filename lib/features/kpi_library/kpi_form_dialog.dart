import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/kpi.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import 'kpi_definition_form.dart';
import 'kpi_parentage.dart';

/// Create/edit dialog for a KPI library entry. Mirrors the layout of
/// `RolesSettingsScreen`'s `_RoleForm` — an `AlertDialog` with a small set of
/// text fields, an inline error, and Cancel/Save actions. Returns the built
/// [Kpi] via `Navigator.pop`; the caller persists it through
/// `RoleScorecardRepository.saveLibraryKpi` and invalidates
/// `kpiLibraryProvider`.
///
/// Below the name/category/description fields sits a [KpiDefinitionForm] so
/// this dialog is where a KPI actually becomes measurable — how it's
/// counted, from which source, at what rhythm.
///
/// Above that sits the KPI cascade section — level, parent, roll-up type and
/// data method (20260814000001) — where a KPI states its place in the
/// Company → Department → Role → Person chain and, optionally, which
/// higher-level measure it serves. Every field this dialog collects is
/// threaded from [widget.existing] on open AND back into the [Kpi] this
/// dialog returns on save; dropping any of them on either end would silently
/// reset an edited KPI's cascade fields to their constructor defaults the
/// next time somebody just renamed it.
class KpiFormDialog extends ConsumerStatefulWidget {
  final Kpi? existing;
  const KpiFormDialog({super.key, this.existing});

  @override
  ConsumerState<KpiFormDialog> createState() => _KpiFormDialogState();
}

class _KpiFormDialogState extends ConsumerState<KpiFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _category = TextEditingController(
    text: widget.existing?.category ?? '',
  );
  late final _measurementUnit = TextEditingController(
    text: widget.existing?.measurementUnit ?? '',
  );
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  String? _error;

  late KpiDefinitionDraft _definition = KpiDefinitionDraft(
    valueType: widget.existing?.valueType ?? 'COUNT',
    numeratorLabel: widget.existing?.numeratorLabel,
    numeratorSource: widget.existing?.numeratorSource,
    denominatorLabel: widget.existing?.denominatorLabel,
    denominatorSource: widget.existing?.denominatorSource,
    unit: widget.existing?.unit,
    proofType: widget.existing?.proofType,
    cadence: widget.existing?.cadence ?? 'WEEKLY',
  );

  // --- KPI cascade (20260814000001) ----------------------------------------
  // Seeded from widget.existing so an edit that never touches these controls
  // still round-trips them on save — see the class doc comment.
  late String _level = widget.existing?.level ?? 'PERSONAL';
  late String? _parentKpiId = widget.existing?.parentKpiId;
  late String _rollupType = widget.existing?.rollupType ?? 'INDEPENDENT';
  late String _dataMethod = widget.existing?.dataMethod ?? 'MANUAL_PERIODIC';
  late String? _targetDirection = widget.existing?.targetDirection;
  late final _targetValue = TextEditingController(
    text: _formatTargetValue(widget.existing?.targetValue),
  );

  /// The company's KPI list as of the last build — cached so [_save], which
  /// runs outside `build()`, can re-check the parent selection against the
  /// same graph the inline message beneath the picker was just computed
  /// from, rather than trusting a message that might be a frame stale.
  List<Kpi> _allKpis = const [];

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _measurementUnit.dispose();
    _description.dispose();
    _targetValue.dispose();
    super.dispose();
  }

  /// `kpiParentError`'s verdict on the current [_parentKpiId] selection,
  /// reused verbatim from Task 2 — this dialog does not re-implement the
  /// sideways/downward/self/loop/unrecognised-level rules, only assembles
  /// the graph the shared function reasons over.
  String? _parentError(List<Kpi> allKpis) {
    final parentId = _parentKpiId;
    if (parentId == null) return null;
    // A brand-new KPI has no id yet. A placeholder that cannot collide with
    // a real id keeps the self-reference and cycle checks meaningful without
    // requiring a saved row first.
    final myId = widget.existing?.id ?? '__unsaved_kpi__';
    final levelById = <String, String>{
      for (final k in allKpis)
        if (k.id != myId) k.id: k.level,
      myId: _level,
    };
    final edges = <({String id, String? parentId})>[
      for (final k in allKpis)
        if (k.id != myId) (id: k.id, parentId: k.parentKpiId),
      // This KPI's CURRENTLY STORED parent, not the pending selection — the
      // cycle guard walks the graph as it exists today to decide whether the
      // move being proposed would close a loop.
      (id: myId, parentId: widget.existing?.parentKpiId),
    ];
    return kpiParentError(
      kpiId: myId,
      newParentId: parentId,
      kpis: edges,
      levelOf: (id) => levelById[id] ?? '__UNRECOGNISED__',
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (_parentKpiId != null && _parentError(_allKpis) != null) {
      // The message is already shown inline beside the Parent KPI field —
      // refuse to save rather than repeating it in the general error area.
      return;
    }
    num? targetValue;
    final targetText = _targetValue.text.trim();
    if (targetText.isNotEmpty) {
      targetValue = num.tryParse(targetText);
      if (targetValue == null) {
        setState(() => _error = 'Target value must be a number.');
        return;
      }
    }
    final kpi = Kpi(
      id: widget.existing?.id ?? '',
      companyId: widget.existing?.companyId ?? '',
      name: name,
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      measurementUnit: _measurementUnit.text.trim().isEmpty
          ? null
          : _measurementUnit.text.trim(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      isActive: widget.existing?.isActive ?? true,
      departmentId: widget.existing?.departmentId,
      valueType: _definition.valueType,
      numeratorLabel: _definition.numeratorLabel,
      numeratorSource: _definition.numeratorSource,
      denominatorLabel: _definition.denominatorLabel,
      denominatorSource: _definition.denominatorSource,
      unit: _definition.unit,
      cadence: _definition.cadence,
      proofType: _definition.proofType,
      level: _level,
      parentKpiId: _parentKpiId,
      rollupType: _rollupType,
      dataMethod: _dataMethod,
      targetDirection: _targetDirection,
      targetValue: targetValue,
    );
    Navigator.pop(context, kpi);
  }

  @override
  Widget build(BuildContext context) {
    final knownSources =
        ref.watch(kpiSourcesProvider).asData?.value ?? const <String>[];
    final allKpis = ref.watch(kpiLibraryProvider).asData?.value ?? const <Kpi>[];
    _allKpis = allKpis;
    final parentError = _parentError(allKpis);
    // A KPI can't serve itself — leave it out of its own parent picker
    // rather than relying solely on kpiParentError to catch a self-pick.
    final parentCandidates = [
      for (final k in allKpis)
        if (k.id != widget.existing?.id) k,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return AlertDialog(
      title: Text(widget.existing == null ? 'New KPI' : 'Edit KPI'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _category,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        hintText: 'e.g. Sales',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _measurementUnit,
                      decoration: const InputDecoration(
                        labelText: 'Measurement unit',
                        hintText: 'e.g. %',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Cascade',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _level,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Level',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final l in kKpiLevels)
                          DropdownMenuItem(value: l, child: Text(l)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _level = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _rollupType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Roll-up type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final r in kKpiRollupTypes)
                          DropdownMenuItem(value: r, child: Text(r)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _rollupType = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _dataMethod,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Data method',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final d in kKpiDataMethods)
                    DropdownMenuItem(value: d, child: Text(d)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _dataMethod = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownMenu<String?>(
                initialSelection: _parentKpiId,
                enableFilter: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                menuHeight: 320,
                label: const Text('Parent KPI'),
                inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                dropdownMenuEntries: [
                  const DropdownMenuEntry<String?>(
                    value: null,
                    label: 'No parent',
                  ),
                  for (final k in parentCandidates)
                    DropdownMenuEntry<String?>(
                      value: k.id,
                      label: '${k.name} (${k.level})',
                    ),
                ],
                onSelected: (v) => setState(() => _parentKpiId = v),
              ),
              if (parentError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    parentError,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              KpiDefinitionForm(
                initial: _definition,
                knownSources: knownSources,
                onChanged: (draft) => _definition = draft,
              ),
              const SizedBox(height: 16),
              Text(
                'Default target',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'What role_scorecard_kpis falls back to when a role sets no '
                'goal of its own — the only bar a DEPARTMENT or COMPANY KPI '
                'has, since neither has a role card to hang one on.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _targetDirection,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Direction',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No default target'),
                        ),
                        for (final d in kKpiTargetDirections)
                          DropdownMenuItem<String?>(
                            value: d,
                            child: Text(d),
                          ),
                      ],
                      onChanged: (v) => setState(() => _targetDirection = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _targetValue,
                      decoration: const InputDecoration(
                        labelText: 'Value',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// `95.0` reads as a typo in a target; `95` is what a person wrote. Mirrors
/// `kpi_goal.dart`'s `_trimNumber`, which is private to that library.
String _formatTargetValue(num? v) {
  if (v == null) return '';
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}
