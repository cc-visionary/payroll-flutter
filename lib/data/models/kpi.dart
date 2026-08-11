import 'kpi_goal.dart';

class Kpi {
  final String id;
  final String companyId;
  final String name;
  final String? category;
  final String? description;
  final String? measurementUnit;
  final bool isActive;

  /// The department that owns this measure. Organisational only — a role card
  /// in another department may still link it.
  final String? departmentId;

  // --- EOS measurable definition (20260811000001) ---------------------------
  /// COUNT | RATIO | CURRENCY | PERCENT | DURATION. See kKpiValueTypes.
  final String valueType;

  /// What is counted, and the system it is read from.
  final String? numeratorLabel;
  final String? numeratorSource;

  /// What it is counted against. RATIO only.
  final String? denominatorLabel;
  final String? denominatorSource;

  /// %, orders, days, ₱ — how the computed value reads.
  final String? unit;

  /// WEEKLY | MONTHLY | QUARTERLY. The measurable's own rhythm.
  final String cadence;

  /// REPORT_EXPORT | SCREENSHOT | SYSTEM_LINK, or null for no requirement.
  final String? proofType;

  const Kpi({
    required this.id,
    required this.companyId,
    required this.name,
    this.category,
    this.description,
    this.measurementUnit,
    this.isActive = true,
    this.departmentId,
    this.valueType = 'COUNT',
    this.numeratorLabel,
    this.numeratorSource,
    this.denominatorLabel,
    this.denominatorSource,
    this.unit,
    this.cadence = 'WEEKLY',
    this.proofType,
  });

  factory Kpi.fromRow(Map<String, dynamic> r) => Kpi(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    name: r['name'] as String,
    category: r['category'] as String?,
    description: r['description'] as String?,
    measurementUnit: r['measurement_unit'] as String?,
    isActive: r['is_active'] as bool? ?? true,
    departmentId: r['department_id'] as String?,
    // Defaulted rather than required: a select that predates the migration, or
    // one with a narrowed column list, must not throw here.
    valueType: r['value_type'] as String? ?? 'COUNT',
    numeratorLabel: r['numerator_label'] as String?,
    numeratorSource: r['numerator_source'] as String?,
    denominatorLabel: r['denominator_label'] as String?,
    denominatorSource: r['denominator_source'] as String?,
    unit: r['unit'] as String?,
    cadence: r['cadence'] as String? ?? 'WEEKLY',
    proofType: r['proof_type'] as String?,
  );

  Map<String, dynamic> toInsert(String companyId) => {
    'company_id': companyId,
    'name': name.trim(),
    'category': _blankToNull(category),
    'description': _blankToNull(description),
    'measurement_unit': _blankToNull(measurementUnit),
    'is_active': isActive,
    'department_id': departmentId,
    'value_type': valueType,
    'numerator_label': _blankToNull(numeratorLabel),
    'numerator_source': _blankToNull(numeratorSource),
    'denominator_label': _blankToNull(denominatorLabel),
    'denominator_source': _blankToNull(denominatorSource),
    'unit': _blankToNull(unit),
    'cadence': cadence,
    'proof_type': _blankToNull(proofType),
  };
}

String? _blankToNull(String? v) =>
    (v == null || v.trim().isEmpty) ? null : v.trim();

/// One KPI attached to a role card, as edited in the workbench.
class KpiLinkInput {
  final String? kpiId; // null → create the library KPI on save
  final String name;
  final String? measurementUnit;
  final String? category;

  /// Legacy free text. Ignored when [goal] is set — the repository derives the
  /// stored `target` from the goal so the two can never disagree.
  final String target;
  final String frequency;

  /// The structured goal, plus the KPI's unit and cadence. [unit] renders the
  /// goal; [cadence] derives the stored `frequency`. Both are carried on the
  /// input because the caller already has the library row on screen — without
  /// [cadence] here, a link to an EXISTING library KPI would fall back to
  /// whatever free text the old link held and the measurable's rhythm would
  /// never reach the column.
  final KpiGoal? goal;
  final String? unit;
  final String? cadence;

  const KpiLinkInput({
    this.kpiId,
    required this.name,
    this.measurementUnit,
    this.category,
    required this.target,
    required this.frequency,
    this.goal,
    this.unit,
    this.cadence,
  });
}
