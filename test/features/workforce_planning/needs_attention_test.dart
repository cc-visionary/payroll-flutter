import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart'
    show KpiAssignee;
import 'package:payroll_flutter/features/workforce_planning/needs_attention.dart';
import 'package:payroll_flutter/features/workforce_planning/role_load.dart';

WpTask _t(
  String id, {
  String? card,
  String? owner,
  String? crit,
  bool essential = true,
  bool expectation = false,
}) => WpTask(
  id: id,
  companyId: 'c',
  name: id,
  roleScorecardId: card,
  ownerEmployeeId: owner,
  criticality: crit,
  isEssential: essential,
  isExpectation: expectation,
);

RoleScorecard _card(
  String id, {
  bool active = true,
  String? dept,
  List<KpiItem> kpis = const [],
}) => RoleScorecard(
  id: id,
  companyId: 'c',
  jobTitle: id,
  missionStatement: '',
  departmentId: dept,
  responsibilities: const [],
  kpis: kpis,
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: active,
  effectiveDate: DateTime(2026),
);

Kpi _kpi(
  String id, {
  bool active = true,
  String? unit, // legacy measurementUnit — NOT the definition's unit column
  String? dept,
  String valueType = 'COUNT',
  String? definitionUnit,
  String? numeratorLabel,
  String? numeratorSource,
  String? denominatorLabel,
  String? denominatorSource,
}) => Kpi(
  id: id,
  companyId: 'c',
  name: id,
  isActive: active,
  measurementUnit: unit,
  departmentId: dept,
  valueType: valueType,
  unit: definitionUnit,
  numeratorLabel: numeratorLabel,
  numeratorSource: numeratorSource,
  denominatorLabel: denominatorLabel,
  denominatorSource: denominatorSource,
);

Employee _emp(String id, String name, String? cardId) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: name,
  lastName: 'X',
  roleScorecardId: cardId,
  employmentType: 'FULL_TIME',
  employmentStatus: 'ACTIVE',
  hireDate: DateTime(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  sssEligibilityOverride: false,
  philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false,
  taxOnFullEarnings: false,
);

List<AttentionItem> _run({
  List<RoleLoad> roleLoads = const [],
  List<WpTask> tasks = const [],
  List<Employee> employees = const [],
  List<RoleScorecard> cards = const [],
  List<Kpi> kpis = const [],
  Map<String, List<KpiAssignee>> assigned = const {},
}) => buildNeedsAttention(
  roleLoads: roleLoads,
  tasks: tasks,
  employees: employees,
  cards: cards,
  kpis: kpis,
  kpiAssignedByKpi: assigned,
);

/// Role loads for [cards]/[employees] with no task hours.
List<RoleLoad> _loads(List<RoleScorecard> cards, List<Employee> employees) =>
    buildRoleLoads(
      roles: cards,
      employees: employees,
      tasks: const [],
      hoursByTaskId: const {},
      capacityByEmployee: const {},
      defaultCapacity: 160,
    );

void main() {
  test('no signals -> empty', () {
    expect(_run(), isEmpty);
  });

  test('role-first signals', () {
    final bh = _card('bh');
    final k = _card('k');
    final loads = buildRoleLoads(
      roles: [bh, k],
      employees: [_emp('ana', 'Ana', 'bh')],
      tasks: const [
        WpTask(id: 't1', companyId: 'c', name: 'a', roleScorecardId: 'bh'),
        WpTask(id: 't2', companyId: 'c', name: 'b', roleScorecardId: 'k'),
        WpTask(id: 't3', companyId: 'c', name: 'orphan'),
        WpTask(id: 't4', companyId: 'c', name: 'legacy', externalRef: 'X'),
        WpTask(id: 't5', companyId: 'c', name: 'flag', roleScorecardId: 'bh', allocationReviewNote: 'was: x'),
      ],
      hoursByTaskId: const {'t1': 200, 't2': 10},
      capacityByEmployee: const {'ana': 160},
      defaultCapacity: 160,
    );
    final items = buildNeedsAttention(
      roleLoads: loads,
      tasks: loads.expand((l) => l.tasks).toList() + const [
        WpTask(id: 't3', companyId: 'c', name: 'orphan'),
        WpTask(id: 't4', companyId: 'c', name: 'legacy', externalRef: 'X'),
      ],
      employees: [_emp('ana', 'Ana', 'bh')],
      cards: [bh, k],
      kpis: const [],
      kpiAssignedByKpi: const {},
    );
    String? label(String contains) => items.map((i) => i.label).where((l) => l.contains(contains)).firstOrNull;
    expect(label('over capacity'), '1 role over capacity');
    expect(label('no role'), '1 task with no role', reason: 'legacy excluded');
    expect(label('nobody holds'), '1 role nobody holds');
    expect(label('check'), '1 task to check');
  });

  test('uncosted essential (not expectation) is a Process/tasks item', () {
    final items = _run(
      tasks: [
        _t('u1', owner: 'x'), // essential, no hours, owned so NOT an orphan
        _t(
          'u2',
          owner: 'x',
          expectation: true,
          essential: false,
        ), // expectation, excluded
      ],
    );
    final proc = items.firstWhere((i) => i.label.contains('uncosted'));
    expect(proc.count, 1); // only u1
  });

  test('KPI signals: measuring nobody, no measurement, no department', () {
    final items = _run(
      kpis: [
        // Assigned, has a legacy unit and a dept, AND fully defined at the
        // library level -> must trip none of the four KPI-library signals.
        _kpi(
          'k1',
          unit: 'orders',
          dept: 'd1',
          definitionUnit: 'orders',
          numeratorLabel: 'Orders shipped',
          numeratorSource: 'BigSeller',
        ),
      ], // assigned below -> only... see asserts
      assigned: {
        'k1': [const KpiAssignee(employeeId: 'e', name: 'E')],
      },
    );
    // k1 is assigned, has a unit, a dept, and a complete definition -> no
    // KPI signals at all.
    expect(items.where((i) => i.target == AttentionTarget.kpiLibrary), isEmpty);

    final bad = _run(kpis: [_kpi('k2')]); // unassigned, no unit, no dept, undefined
    final lib = bad
        .where((i) => i.target == AttentionTarget.kpiLibrary)
        .toList();
    expect(lib.length, 4); // measuring-nobody + no-measurement + no-department
    // + incomplete-definition
  });

  test('counts active library KPIs with an incomplete definition', () {
    final items = _run(
      kpis: [
        // Complete: a RATIO with both halves and a unit.
        _kpi('k1', valueType: 'RATIO', definitionUnit: '%',
            numeratorLabel: 'Returns', numeratorSource: 'BigSeller',
            denominatorLabel: 'Orders', denominatorSource: 'BigSeller'),
        // A RATIO missing its denominator.
        _kpi('k2', valueType: 'RATIO', definitionUnit: '%',
            numeratorLabel: 'Returns', numeratorSource: 'BigSeller'),
        // A legacy row with nothing but a name.
        _kpi('k3'),
        // Inactive rows are not a gap to close.
        _kpi('k4', active: false),
      ],
    );

    // "incomplete definition", not "not measurable yet": the latter is the
    // KPIs pane's phrase for the per-role GOAL gap, which this does NOT count.
    final item = items.singleWhere(
      (i) => i.label.contains('incomplete definition'),
    );
    expect(item.count, 2);
    expect(item.target, AttentionTarget.kpiLibrary);
  });

  test('unstaffed card with CRITICAL work, and card with no department', () {
    final items = _run(
      cards: [
        _card('rs1'),
        _card('rs2', dept: 'd1'),
      ],
      tasks: [_t('t1', card: 'rs1', crit: 'CRITICAL')], // rs1 has no holders
      employees: const [], // nobody staffs rs1
    );
    final struct = items.where(
      (i) =>
          i.category == AttentionCategory.structure &&
          i.target == AttentionTarget.roles,
    );
    // unstaffed-critical (rs1) + no-department (rs1 only; rs2 has a dept)
    expect(struct.any((i) => i.count == 1), isTrue);
    expect(struct.length, 2);
  });

  // Pure inheritance retired the per-employee "no KPI set" signal: an
  // employee's KPIs are their role's KPIs, so there is no stored subset left
  // to be absent or off-role. The rule that survives is the same shape one
  // level up — a gap the app must still flag, just on the ROLE now.
  test('a role with no KPIs is flagged; one with a KPI is not', () {
    const returnRate = KpiItem(
      name: 'Return Rate',
      measurement: '%',
      target: '',
      frequency: 'Weekly',
    );
    final items = _run(
      cards: [_card('card-1'), _card('card-2', kpis: const [returnRate])],
    );
    final item = items.singleWhere((i) => i.label.contains('with no KPI'));
    expect(item.count, 1);
    expect(item.target, AttentionTarget.roles);
    expect(item.category, AttentionCategory.people);
  });

  test('says nothing when every active role has a KPI', () {
    const returnRate = KpiItem(
      name: 'Return Rate',
      measurement: '%',
      target: '',
      frequency: 'Weekly',
    );
    final items = _run(cards: [_card('card-1', kpis: const [returnRate])]);
    expect(items.where((i) => i.label.contains('with no KPI')), isEmpty);
  });

  test('an inactive role with no KPI does not count', () {
    final items = _run(cards: [_card('card-1', active: false)]);
    expect(items.where((i) => i.label.contains('with no KPI')), isEmpty);
  });

  test('a role with no KPIs is flagged once, not once per holder', () {
    final items = _run(
      employees: [_emp('e1', 'One', 'card-1'), _emp('e2', 'Two', 'card-1')],
      cards: [_card('card-1')],
    );
    final item = items.singleWhere((i) => i.label.contains('with no KPI'));
    expect(item.count, 1);
  });

  test('an unfilled role is flagged once, not once per missing holder', () {
    final cards = [_card('rs1'), _card('rs2'), _card('rs3')];
    final items = _run(
      roleLoads: _loads(cards, [
        _emp('e1', 'One', 'rs2'),
        _emp('e2', 'Two', 'rs2'),
      ]),
    );
    final item = items.singleWhere((i) => i.label.contains('nobody holds'));
    expect(item.count, 2); // rs1 and rs3 — rs2 has holders
    expect(item.category, AttentionCategory.structure);
    expect(item.target, AttentionTarget.roles);
  });

  test('every role held -> the signal does not appear', () {
    final items = _run(
      roleLoads: _loads(
        [_card('rs1'), _card('rs2')],
        [_emp('e1', 'One', 'rs1'), _emp('e2', 'Two', 'rs2')],
      ),
    );
    expect(items.where((i) => i.label.contains('nobody holds')), isEmpty);
  });

  test('high-severity items rank before medium', () {
    final items = _run(
      // One holder, 200h of work on 160h -> over capacity (high).
      roleLoads: buildRoleLoads(
        roles: [_card('rs1', dept: 'd1')],
        employees: [_emp('a', 'A', 'rs1')],
        tasks: [_t('h1', card: 'rs1')],
        hoursByTaskId: const {'h1': 200},
        capacityByEmployee: const {},
        defaultCapacity: 160,
      ),
      tasks: [_t('u1', owner: 'x')], // medium (uncosted essential)
    );
    expect(items.first.severity, AttentionSeverity.high);
  });
}
