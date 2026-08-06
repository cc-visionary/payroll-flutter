double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
String? _s(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

class WpNode {
  final String id, companyId, code, name;
  final int sortOrder;
  const WpNode({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.sortOrder = 0,
  });
  factory WpNode.fromRow(Map<String, dynamic> r) => WpNode(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    code: r['code'] as String,
    name: r['name'] as String,
    sortOrder: _i(r['sort_order']),
  );
}

class WpDriver {
  final String id, companyId, name;
  final double value;
  final bool grows;
  final String? note;
  final int sortOrder;
  const WpDriver({
    required this.id,
    required this.companyId,
    required this.name,
    this.value = 0,
    this.grows = false,
    this.note,
    this.sortOrder = 0,
  });
  factory WpDriver.fromRow(Map<String, dynamic> r) => WpDriver(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    name: r['name'] as String,
    value: _d(r['value']),
    grows: r['grows'] as bool? ?? false,
    note: r['note'] as String?,
    sortOrder: _i(r['sort_order']),
  );
  Map<String, dynamic> toUpsert(String companyId) => {
    'company_id': companyId,
    'name': name.trim(),
    'value': value,
    'grows': grows,
    'note': _s(note),
    'sort_order': sortOrder,
  };
}

class WpRate {
  final String id, companyId, name;
  final double minutesEach;
  final String? note;
  const WpRate({
    required this.id,
    required this.companyId,
    required this.name,
    this.minutesEach = 0,
    this.note,
  });
  factory WpRate.fromRow(Map<String, dynamic> r) => WpRate(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    name: r['name'] as String,
    minutesEach: _d(r['minutes_each']),
    note: r['note'] as String?,
  );
  Map<String, dynamic> toUpsert(String companyId) => {
    'company_id': companyId,
    'name': name.trim(),
    'minutes_each': minutesEach,
    'note': _s(note),
  };
}

class WpConfig {
  final String companyId;
  final double growthMultiplier, defaultCapacityHours;
  const WpConfig({
    required this.companyId,
    this.growthMultiplier = 1,
    this.defaultCapacityHours = 160,
  });
  factory WpConfig.fromRow(Map<String, dynamic> r) => WpConfig(
    companyId: r['company_id'] as String,
    growthMultiplier: _dn(r['growth_multiplier']) ?? 1,
    defaultCapacityHours: _dn(r['default_capacity_hours']) ?? 160,
  );
}

class WpTask {
  final String id, companyId, name;
  final String? nodeId,
      brandScope,
      cadence,
      driverId,
      rateId,
      skillTier,
      risk,
      capability,
      ownerEmployeeId,
      roleScorecardId,
      responsibilityArea,
      notes,
      externalRef;
  final String timesSource, minutesSource;
  final double? timesManual, minutesManual;
  final double driverFactor;
  final int areaSort, taskSort;

  /// A behavioural expectation from the job description rather than costable
  /// monthly workload ("participate in training", "take broader ownership").
  /// Excluded from the costing queue and the understated-load warning; still a
  /// real responsibility on the card and in the contract annex.
  final bool isExpectation;

  /// Business criticality LOW/MEDIUM/HIGH/CRITICAL (nullable = unset). The ADA
  /// essential-function test's "importance" leg.
  final String? criticality;

  /// ADA essential-function flag. An expectation is always non-essential; the
  /// DB constraint and [toUpsert] keep the two consistent.
  final bool isEssential;

  /// Lifecycle: 'ACTIVE' or 'ARCHIVED'. ARCHIVED work leaves load and the
  /// derived lists (via wp_task_computed) but is retained and restorable.
  final String status;

  /// Direct monthly-hours figure. When non-null it IS the workload and wins
  /// over the times x minutes driver calc (mirrors wp_task_computed). A
  /// direct-hours task never responds to the growth multiplier.
  final double? hoursPerMonth;
  const WpTask({
    required this.id,
    required this.companyId,
    required this.name,
    this.nodeId,
    this.brandScope,
    this.cadence,
    this.timesSource = 'manual',
    this.timesManual,
    this.driverId,
    this.driverFactor = 1,
    this.minutesSource = 'manual',
    this.minutesManual,
    this.rateId,
    this.skillTier,
    this.risk,
    this.capability,
    this.ownerEmployeeId,
    this.roleScorecardId,
    this.responsibilityArea,
    this.notes,
    this.externalRef,
    this.areaSort = 0,
    this.taskSort = 0,
    this.isExpectation = false,
    this.criticality,
    this.isEssential = true,
    this.status = 'ACTIVE',
    this.hoursPerMonth,
  });
  factory WpTask.fromRow(Map<String, dynamic> r) => WpTask(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    name: r['name'] as String,
    nodeId: r['node_id'] as String?,
    brandScope: r['brand_scope'] as String?,
    cadence: r['cadence'] as String?,
    timesSource: r['times_source'] as String? ?? 'manual',
    timesManual: _dn(r['times_manual']),
    driverId: r['driver_id'] as String?,
    driverFactor: _dn(r['driver_factor']) ?? 1,
    minutesSource: r['minutes_source'] as String? ?? 'manual',
    minutesManual: _dn(r['minutes_manual']),
    rateId: r['rate_id'] as String?,
    skillTier: r['skill_tier'] as String?,
    risk: r['risk'] as String?,
    capability: r['capability'] as String?,
    ownerEmployeeId: r['owner_employee_id'] as String?,
    roleScorecardId: r['role_scorecard_id'] as String?,
    responsibilityArea: r['responsibility_area'] as String?,
    notes: r['notes'] as String?,
    externalRef: r['external_ref'] as String?,
    areaSort: _i(r['area_sort']),
    taskSort: _i(r['task_sort']),
    isExpectation: r['is_expectation'] as bool? ?? false,
    criticality: r['criticality'] as String?,
    isEssential: r['is_essential'] as bool? ?? true,
    status: r['status'] as String? ?? 'ACTIVE',
    hoursPerMonth: _dn(r['hours_per_month']),
  );

  /// Same task at a new position in its card/area. Used when a responsibility
  /// is created or moved, so it lands at the END of its area.
  WpTask copyWithSort({required int areaSort, required int taskSort}) => WpTask(
    id: id,
    companyId: companyId,
    name: name,
    nodeId: nodeId,
    brandScope: brandScope,
    cadence: cadence,
    timesSource: timesSource,
    timesManual: timesManual,
    driverId: driverId,
    driverFactor: driverFactor,
    minutesSource: minutesSource,
    minutesManual: minutesManual,
    rateId: rateId,
    skillTier: skillTier,
    risk: risk,
    capability: capability,
    ownerEmployeeId: ownerEmployeeId,
    roleScorecardId: roleScorecardId,
    responsibilityArea: responsibilityArea,
    notes: notes,
    externalRef: externalRef,
    areaSort: areaSort,
    taskSort: taskSort,
    isExpectation: isExpectation,
    criticality: criticality,
    isEssential: isEssential,
    status: status,
    hoursPerMonth: hoursPerMonth,
  );

  Map<String, dynamic> toUpsert(String companyId) {
    final direct = hoursPerMonth != null;
    return {
      'company_id': companyId, 'name': name.trim(), 'node_id': nodeId,
      'brand_scope': _s(brandScope), 'cadence': _s(cadence),
      'times_source': direct ? 'manual' : timesSource,
      'times_manual': direct
          ? null
          : (timesSource == 'driver' ? null : timesManual),
      'driver_id': direct ? null : (timesSource == 'driver' ? driverId : null),
      'driver_factor': driverFactor,
      'minutes_source': direct ? 'manual' : minutesSource,
      'minutes_manual': direct
          ? null
          : (minutesSource == 'rate' ? null : minutesManual),
      'rate_id': direct ? null : (minutesSource == 'rate' ? rateId : null),
      'hours_per_month': hoursPerMonth,
      'skill_tier': _s(skillTier),
      'risk': _s(risk),
      'capability': _s(capability),
      'owner_employee_id': ownerEmployeeId,
      'role_scorecard_id': roleScorecardId,
      'responsibility_area': _s(responsibilityArea), 'notes': _s(notes),
      'is_expectation': isExpectation,
      'criticality': _s(criticality),
      // An expectation is by definition non-essential — enforce it here so no
      // saveTask path can violate the wp_tasks_expectation_non_essential CHECK.
      'is_essential': isExpectation ? false : isEssential,
      'status': status,
      // Position is load-bearing: the role-card PDF and contract Annex A render
      // responsibilities in this order. Omitting these left every row created
      // from the Tasks tab at 0/0 — jumping ahead of the card's first
      // responsibility.
      'area_sort': areaSort, 'task_sort': taskSort,
    };
  }
}

class WpTaskAssignment {
  final String id, companyId, taskId;
  final String? roleScorecardId, employeeId;
  final String assignmentRole; // 'PRIMARY' | 'CONTRIBUTOR'
  final double allocationPct;
  const WpTaskAssignment({
    required this.id,
    required this.companyId,
    required this.taskId,
    this.roleScorecardId,
    this.employeeId,
    this.assignmentRole = 'CONTRIBUTOR',
    this.allocationPct = 0,
  });
  factory WpTaskAssignment.fromRow(Map<String, dynamic> r) => WpTaskAssignment(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    taskId: r['task_id'] as String,
    roleScorecardId: r['role_scorecard_id'] as String?,
    employeeId: r['employee_id'] as String?,
    assignmentRole: r['assignment_role'] as String? ?? 'CONTRIBUTOR',
    allocationPct: _d(r['allocation_pct']),
  );
  Map<String, dynamic> toUpsert(String companyId) => {
    'company_id': companyId,
    'task_id': taskId,
    'role_scorecard_id': roleScorecardId,
    'employee_id': employeeId,
    'assignment_role': assignmentRole,
    'allocation_pct': allocationPct,
  };
}

class WpTaskComputed {
  final String taskId, companyId;
  final String? ownerEmployeeId, nodeId, skillTier, risk;
  final bool isGrowing;
  final double timesPerMonthBase, minutesEach, hoursPerMonthBase;
  const WpTaskComputed({
    required this.taskId,
    required this.companyId,
    this.ownerEmployeeId,
    this.nodeId,
    this.skillTier,
    this.risk,
    this.isGrowing = false,
    this.timesPerMonthBase = 0,
    this.minutesEach = 0,
    this.hoursPerMonthBase = 0,
  });
  factory WpTaskComputed.fromRow(Map<String, dynamic> r) => WpTaskComputed(
    taskId: r['task_id'] as String,
    companyId: r['company_id'] as String,
    ownerEmployeeId: r['owner_employee_id'] as String?,
    nodeId: r['node_id'] as String?,
    skillTier: r['skill_tier'] as String?,
    risk: r['risk'] as String?,
    isGrowing: r['is_growing'] as bool? ?? false,
    timesPerMonthBase: _d(r['times_per_month_base']),
    minutesEach: _d(r['minutes_each']),
    hoursPerMonthBase: _d(r['hours_per_month_base']),
  );
}

class WpPersonLoad {
  final String employeeId, companyId;
  final int tasksOwned;
  final double hoursFixed, hoursGrowingBase, capacityHours, growthMultiplier;
  const WpPersonLoad({
    required this.employeeId,
    required this.companyId,
    this.tasksOwned = 0,
    this.hoursFixed = 0,
    this.hoursGrowingBase = 0,
    this.capacityHours = 160,
    this.growthMultiplier = 1,
  });
  factory WpPersonLoad.fromRow(Map<String, dynamic> r) => WpPersonLoad(
    employeeId: r['employee_id'] as String,
    companyId: r['company_id'] as String,
    tasksOwned: _i(r['tasks_owned']),
    hoursFixed: _d(r['hours_fixed']),
    hoursGrowingBase: _d(r['hours_growing_base']),
    capacityHours: _dn(r['capacity_hours']) ?? 160,
    growthMultiplier: _dn(r['growth_multiplier']) ?? 1,
  );
}
