import 'package:flutter/material.dart';

import '../../app/status_colors.dart';
import 'kpi_measurable.dart';

/// The mutable definition a [KpiDefinitionForm] reports upward through
/// [KpiDefinitionForm.onChanged]. The form itself never persists anything —
/// the host (the KPI Library dialog today, the workbench's KPIs pane next)
/// owns when and whether to call
/// `RoleScorecardRepository.saveLibraryKpi(..., writeDefinition: true)`.
class KpiDefinitionDraft {
  String valueType;
  String? numeratorLabel;
  String? numeratorSource;
  String? denominatorLabel;
  String? denominatorSource;
  String? unit;
  String? proofType;
  String cadence;

  KpiDefinitionDraft({
    this.valueType = 'COUNT',
    this.numeratorLabel,
    this.numeratorSource,
    this.denominatorLabel,
    this.denominatorSource,
    this.unit,
    this.proofType,
    this.cadence = 'WEEKLY',
  });
}

/// Captures how a KPI is counted: its value type, what is counted and from
/// which source, the denominator (RATIO only), the unit, cadence and proof
/// requirement. Shared by the KPI Library dialog and the workbench's KPIs
/// pane — the form knows nothing about saving, only about the current draft.
///
/// Source fields are free text with suggestions ([knownSources]), never a
/// closed list: a new sales channel must survive without a migration or a
/// release.
class KpiDefinitionForm extends StatefulWidget {
  final KpiDefinitionDraft? initial;
  final List<String> knownSources;
  final ValueChanged<KpiDefinitionDraft> onChanged;

  const KpiDefinitionForm({
    super.key,
    this.initial,
    required this.knownSources,
    required this.onChanged,
  });

  @override
  State<KpiDefinitionForm> createState() => _KpiDefinitionFormState();
}

class _KpiDefinitionFormState extends State<KpiDefinitionForm> {
  late String _valueType;
  late String _cadence;
  String? _proofType;

  late final TextEditingController _unit;
  late final TextEditingController _numeratorLabel;
  late final TextEditingController _numeratorSource;
  late final TextEditingController _denominatorLabel;
  late final TextEditingController _denominatorSource;

  // Autocomplete requires a FocusNode whenever it's given its own
  // TextEditingController (RawAutocomplete asserts the two travel together),
  // so the source fields need one each rather than sharing the framework's
  // internal default.
  final _numeratorSourceFocus = FocusNode();
  final _denominatorSourceFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _valueType = initial?.valueType ?? 'COUNT';
    _cadence = initial?.cadence ?? 'WEEKLY';
    _proofType = initial?.proofType;
    _unit = TextEditingController(text: initial?.unit ?? '');
    _numeratorLabel = TextEditingController(text: initial?.numeratorLabel ?? '');
    _numeratorSource = TextEditingController(
      text: initial?.numeratorSource ?? '',
    );
    _denominatorLabel = TextEditingController(
      text: initial?.denominatorLabel ?? '',
    );
    _denominatorSource = TextEditingController(
      text: initial?.denominatorSource ?? '',
    );
    // Report the starting draft before the user touches anything — a host
    // that saves immediately (e.g. an unedited "New KPI" dialog) must see the
    // same defaults this form is displaying, not null.
    // _report, not _emit: the first build already rendered the gaps line from
    // these same controllers, so there is nothing to refresh — only the host
    // needs telling.
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void dispose() {
    _unit.dispose();
    _numeratorLabel.dispose();
    _numeratorSource.dispose();
    _denominatorLabel.dispose();
    _denominatorSource.dispose();
    _numeratorSourceFocus.dispose();
    _denominatorSourceFocus.dispose();
    super.dispose();
  }

  String? _blank(String v) => v.trim().isEmpty ? null : v.trim();

  /// Reports the current draft AND refreshes this form's own gaps line.
  /// Use from anything backed by a [TextEditingController]; the dropdowns
  /// call [_report] directly because they already `setState`.
  void _emit() {
    _report();
    // The "Still needed" line is computed in build() from these controllers'
    // text, and a TextEditingController change does not itself rebuild this
    // widget — only the dropdowns did, via their own setState. So typing into
    // "What is counted" left the line still listing it as missing (and, once
    // the last gap was filled by typing, left the form claiming the
    // definition was incomplete when it was not).
    if (mounted) setState(() {});
  }

  void _report() {
    widget.onChanged(
      KpiDefinitionDraft(
        valueType: _valueType,
        numeratorLabel: _blank(_numeratorLabel.text),
        numeratorSource: _blank(_numeratorSource.text),
        // Never reported for a non-RATIO type, even if stale text is still
        // sitting in the (hidden) controllers — see _setValueType, which
        // clears them the moment RATIO is left, so this is belt-and-braces.
        denominatorLabel: _valueType == 'RATIO'
            ? _blank(_denominatorLabel.text)
            : null,
        denominatorSource: _valueType == 'RATIO'
            ? _blank(_denominatorSource.text)
            : null,
        unit: _blank(_unit.text),
        proofType: _proofType,
        cadence: _cadence,
      ),
    );
  }

  void _setValueType(String? v) {
    if (v == null || v == _valueType) return;
    setState(() {
      _valueType = v;
      if (v != 'RATIO') {
        // Switching away from RATIO must not leave an orphaned denominator
        // definition sitting in state ready to be silently written the next
        // time the form saves — the fields are hidden, so the values behind
        // them must actually be gone, not just invisible.
        _denominatorLabel.clear();
        _denominatorSource.clear();
      }
    });
    // The setState above already schedules the rebuild _emit would add.
    _report();
  }

  @override
  Widget build(BuildContext context) {
    final gaps = kpiDefinitionGaps(
      valueType: _valueType,
      unit: _unit.text,
      numeratorLabel: _numeratorLabel.text,
      numeratorSource: _numeratorSource.text,
      denominatorLabel: _denominatorLabel.text,
      denominatorSource: _denominatorSource.text,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Measurable definition',
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
                initialValue: _valueType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Value type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final v in kKpiValueTypes)
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: _setValueType,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _cadence,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Cadence',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final c in kKpiCadences)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _cadence = v);
                  _report();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _numeratorLabel,
                decoration: const InputDecoration(
                  labelText: 'What is counted',
                  hintText: 'e.g. Returns',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _sourceField(
                label: 'Source',
                controller: _numeratorSource,
                focusNode: _numeratorSourceFocus,
              ),
            ),
          ],
        ),
        if (_valueType == 'RATIO') ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _denominatorLabel,
                  decoration: const InputDecoration(
                    labelText: 'Counted against',
                    hintText: 'e.g. Orders',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _emit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _sourceField(
                  label: 'Denominator source',
                  controller: _denominatorSource,
                  focusNode: _denominatorSourceFocus,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _unit,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  hintText: 'e.g. %',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _proofType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Proof type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No proof required'),
                  ),
                  for (final p in kKpiProofTypes)
                    DropdownMenuItem<String?>(value: p, child: Text(p)),
                ],
                onChanged: (v) {
                  setState(() => _proofType = v);
                  _report();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _gapsLine(context, gaps),
      ],
    );
  }

  Widget _sourceField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return Autocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) {
        if (value.text.isEmpty) return widget.knownSources;
        final q = value.text.toLowerCase();
        return widget.knownSources.where((s) => s.toLowerCase().contains(q));
      },
      // Selecting a suggestion updates the controller directly (see
      // RawAutocomplete's _select), which does not itself invoke the field's
      // onChanged — emit explicitly here so a picked suggestion is reported
      // just as reliably as free text is.
      onSelected: (_) => _emit(),
      fieldViewBuilder: (context, textController, node, onFieldSubmitted) =>
          TextFormField(
            controller: textController,
            focusNode: node,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _emit(),
          ),
    );
  }

  Widget _gapsLine(BuildContext context, List<String> gaps) {
    if (gaps.isEmpty) return _completeLine(context);
    final tone = StatusPalette.of(context, StatusTone.warning).foreground;
    return Text(
      'Still needed: ${gaps.join(', ')}',
      style: TextStyle(fontSize: 12, color: tone),
    );
  }

  /// Wrapped in [Flexible] rather than sized naturally: the sentence is longer
  /// than the 640px-wide Add-KPI dialog this form also lives in, so an
  /// unconstrained Text beside the icon overflows the Row the moment the
  /// definition becomes complete.
  Widget _completeLine(BuildContext context) {
    final tone = StatusPalette.of(context, StatusTone.success).foreground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.check_circle_outline, size: 14, color: tone),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Definition complete — a number can be produced for this KPI.',
            style: TextStyle(fontSize: 12, color: tone),
          ),
        ),
      ],
    );
  }
}
