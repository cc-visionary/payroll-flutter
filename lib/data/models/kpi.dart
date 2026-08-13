import 'kpi_goal.dart';

const kKpiLevels = ['PERSONAL', 'DEPARTMENT', 'COMPANY'];
const kKpiRollupTypes = ['DIRECT', 'SHARED', 'ALIGNED', 'INDEPENDENT'];
const kKpiDataMethods = [
  'AUTOMATIC',
  'HYBRID',
  'MANUAL_EXCEPTION',
  'MANUAL_PERIODIC',
];

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

  // --- KPI cascade definition (20260814000001) ----------------------------------
  /// PERSONAL | DEPARTMENT | COMPANY — the scope this measure is designed for.
  final String level;

  /// The higher-level measure this one serves. Null at the top.
  final String? parentKpiId;

  /// DIRECT | SHARED | ALIGNED | INDEPENDENT. Governs whether the results
  /// engine may recompute this KPI at a wider scope.
  final String rollupType;

  /// AUTOMATIC | HYBRID | MANUAL_EXCEPTION | MANUAL_PERIODIC.
  final String dataMethod;

  /// HIGHER | LOWER, and the number that counts as healthy. The DEFAULT
  /// target: `role_scorecard_kpis.goal_*` overrides it for one role, and a
  /// DEPARTMENT or COMPANY scope has no role link so it uses this.
  final String? targetDirection;
  final num? targetValue;

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
    this.level = 'PERSONAL',
    this.parentKpiId,
    this.rollupType = 'INDEPENDENT',
    this.dataMethod = 'MANUAL_PERIODIC',
    this.targetDirection,
    this.targetValue,
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
    level: r['level'] as String? ?? 'PERSONAL',
    parentKpiId: r['parent_kpi_id'] as String?,
    rollupType: r['rollup_type'] as String? ?? 'INDEPENDENT',
    dataMethod: r['data_method'] as String? ?? 'MANUAL_PERIODIC',
    targetDirection: r['target_direction'] as String?,
    targetValue: r['target_value'] as num?,
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
    'level': level,
    'parent_kpi_id': parentKpiId,
    'rollup_type': rollupType,
    'data_method': dataMethod,
    'target_direction': targetDirection,
    'target_value': targetValue,
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

  /// Whether this caller OWNS the structured goal, i.e. it renders a goal
  /// editor and submits whatever that editor currently says.
  ///
  /// Distinguishes the two things a null [goal] can mean:
  ///
  /// * `writeGoal: true`  → "this role has no goal for this KPI". The
  ///   repository writes `goal_direction`/`goal_value`/`goal_value_max` as
  ///   NULL unconditionally. `target` is NULL too, but only when [target]
  ///   is also empty — a caller may still pass a link's legacy free text
  ///   through [target] here, and the repository preserves it (see
  ///   `goalColumns`). `KpisPane` relies on exactly that: it saves every
  ///   link on the card in one call, `writeGoal: true` throughout, and
  ///   forwards a link's stored prose in [target] for any link that never
  ///   had a structured goal to begin with, so that prose survives instead
  ///   of being wiped. Only a link whose goal WAS stored and has since been
  ///   cleared sends an empty [target] — that is the case that actually
  ///   nulls the column.
  /// * `writeGoal: false` (the default) → "I have no opinion". The repository
  ///   leaves those four columns alone. This is what the old responsibility-
  ///   card editor (deleted once the workbench became the only place a role
  ///   is authored) needed: it built every link with no goal on every save,
  ///   so without this it would have wiped every structured goal the
  ///   workbench had authored — and `target`, which the role-card PDF and
  ///   the employment contract's Annex A render, would have reverted to
  ///   free text on a signed document.
  ///
  /// Ignored when [goal] is non-null: a caller that supplies a goal has an
  /// opinion by definition.
  final bool writeGoal;

  /// The `role_outcomes` row this link proves — see role_outcomes
  /// (20260814000002). Null means "no outcome picked yet", which is a legal,
  /// permanent state, not merely a transient one: a KPI with no outcome must
  /// stay valid.
  ///
  /// Always written on save, the same way [frequency]/[kpiId] are: `KpisPane`
  /// saves the whole card's link set on every call, and there is no separate
  /// "no opinion" mode for this field the way [writeGoal] gives one for the
  /// goal columns — so a null here is read as "this role has no outcome for
  /// this KPI" and clears the column, not as "leave whatever is stored
  /// alone".
  final String? outcomeId;

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
    this.writeGoal = false,
    this.outcomeId,
  });

  /// True when the repository must write the four goal columns for this link.
  bool get ownsGoal => writeGoal || goal != null;
}
