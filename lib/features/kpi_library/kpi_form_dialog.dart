import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/kpi.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import 'kpi_definition_form.dart';

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

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _measurementUnit.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
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
      valueType: _definition.valueType,
      numeratorLabel: _definition.numeratorLabel,
      numeratorSource: _definition.numeratorSource,
      denominatorLabel: _definition.denominatorLabel,
      denominatorSource: _definition.denominatorSource,
      unit: _definition.unit,
      cadence: _definition.cadence,
      proofType: _definition.proofType,
    );
    Navigator.pop(context, kpi);
  }

  @override
  Widget build(BuildContext context) {
    final knownSources =
        ref.watch(kpiSourcesProvider).asData?.value ?? const <String>[];
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
              KpiDefinitionForm(
                initial: _definition,
                knownSources: knownSources,
                onChanged: (draft) => _definition = draft,
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
