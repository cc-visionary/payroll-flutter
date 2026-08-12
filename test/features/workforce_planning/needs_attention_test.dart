import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart'
    show KpiAssignee;
import 'package:payroll_flutter/features/workforce_planning/needs_attention.dart';

WpPersonLoad _load(String id, {required double fixed, double cap = 160}) =>
    WpPersonLoad(
      employeeId: id,
      companyId: 'c',
      hoursFixed: fixed,
      capacityHours: cap,
    );

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

RoleScorecard _card(String id, {bool active = true, String? dept}) =>
    RoleScorecard(
      id: id,
      companyId: 'c',
      jobTitle: id,
      missionStatement: '',
      departmentId: dept,
      responsibilities: const [],
      kpis: const [],
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
  List<WpPersonLoad> loads = const [],
  List<WpTask> tasks = const [],
  List<Employee> employees = const [],
  List<RoleScorecard> cards = const [],
  List<Kpi> kpis = const [],
  Map<String, List<KpiAssignee>> assigned = const {},
  Map<String, List<WpTaskAssignment>> assignmentsByTask = const {},
  Map<String, Set<String>>? roleKpiIdsByCard,
  Map<String, Set<String>>? assignedKpiIdsByEmployee,
  Map<String, int> areaCountBySeat = const {},
  Map<String, int> holderCountBySeat = const {},
}) => buildNeedsAttention(
  loads: loads,
  tasks: tasks,
  employees: employees,
  cards: cards,
  kpis: kpis,
  kpiAssignedByKpi: assigned,
  assignmentsByTask: assignmentsByTask,
  roleKpiIdsByCard: roleKpiIdsByCard,
  assignedKpiIdsByEmployee: assignedKpiIdsByEmployee,
  areaCountBySeat: areaCountBySeat,
  holderCountBySeat: holderCountBySeat,
);

WpTaskAssignment _a(String id, String taskId, double pct) => WpTaskAssignment(
  id: id,
  companyId: 'c',
  taskId: taskId,
  allocationPct: pct,
);

AttentionItem? _find(
  List<AttentionItem> items,
  AttentionTarget target,
  AttentionSeverity sev,
) {
  final hits = items.where((i) => i.target == target && i.severity == sev);
  return hits.isEmpty ? null : hits.first;
}

void main() {
  test('no signals -> empty', () {
    expect(_run(), isEmpty);
  });

  test('over-capacity person is a high People/balance item', () {
    final items = _run(loads: [_load('a', fixed: 200), _load('b', fixed: 80)]);
    final over = _find(items, AttentionTarget.balance, AttentionSeverity.high)!;
    expect(over.category, AttentionCategory.people);
    expect(over.count, 1);
  });

  test('a CRITICAL orphan is high; all orphans are a medium item', () {
    final items = _run(
      tasks: [
        _t('o1', crit: 'CRITICAL'),
        _t('o2'),
      ], // both unowned, no card -> orphans
    );
    final crit = _find(
      items,
      AttentionTarget.unassigned,
      AttentionSeverity.high,
    )!;
    expect(crit.count, 1);
    final all = _find(
      items,
      AttentionTarget.unassigned,
      AttentionSeverity.medium,
    )!;
    expect(all.count, 2);
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
    // Match on the label, not (target, severity) alone: the "shares don't
    // total 100%" item shares (process, tasks, medium) with this one, so
    // picking `.first` off that pair would be insertion-order dependent.
    final proc = items.firstWhere((i) => i.label.contains('uncosted'));
    expect(proc.count, 1); // only u1
  });

  test(
    'shares that don\'t total 100% are a Process/tasks item; exact 100 is not',
    () {
      final short = _run(
        tasks: [_t('s1', owner: 'x')],
        assignmentsByTask: {
          's1': [_a('a1', 's1', 40), _a('a2', 's1', 30)],
        }, // totals 70
      );
      final proc = short
          .where((i) => i.label.contains("don't total 100%"))
          .toList();
      expect(proc.length, 1);
      expect(proc.single.count, 1);
      expect(proc.single.severity, AttentionSeverity.medium);
      expect(proc.single.target, AttentionTarget.tasks);

      final exact = _run(
        tasks: [_t('s2', owner: 'x')],
        assignmentsByTask: {
          's2': [_a('a3', 's2', 60), _a('a4', 's2', 40)],
        }, // totals 100
      );
      expect(exact.where((i) => i.label.contains("don't total 100%")), isEmpty);
    },
  );

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

  test('flags only holders whose ON-ROLE set is empty', () {
    // e1 tracks one of its role's KPIs -> fine.
    // e2 stores only an id that is NOT on its role -> reads as absent.
    // e3 stores nothing -> absent.
    // e4 holds no role card at all -> not this signal's business.
    final items = _run(
      employees: [
        _emp('e1', 'One', 'card-1'),
        _emp('e2', 'Two', 'card-1'),
        _emp('e3', 'Three', 'card-1'),
        _emp('e4', 'Four', null),
      ],
      cards: [_card('card-1')],
      roleKpiIdsByCard: const {
        'card-1': {'k1', 'k2'},
      },
      assignedKpiIdsByEmployee: const {
        'e1': {'k1'},
        'e2': {'zz'},
        'e3': <String>{},
      },
    );

    final item = items.singleWhere((i) => i.label.contains('no KPI set'));
    expect(item.count, 2);
    expect(item.target, AttentionTarget.roles);
  });

  test('says nothing while the assignment maps are still absent', () {
    // Absent is not empty. Empty maps make every holder's on-role set empty,
    // so defaulting an unresolved provider to {} would flag EVERY active
    // holder — the maximum, not zero.
    final absent = _run(
      employees: [_emp('e1', 'One', 'card-1'), _emp('e2', 'Two', 'card-1')],
      cards: [_card('card-1')],
    );
    expect(absent.where((i) => i.label.contains('no KPI set')), isEmpty);

    // Same inputs, maps now loaded and genuinely empty -> both are flagged.
    final loaded = _run(
      employees: [_emp('e1', 'One', 'card-1'), _emp('e2', 'Two', 'card-1')],
      cards: [_card('card-1')],
      roleKpiIdsByCard: const {
        'card-1': {'k1'},
      },
      assignedKpiIdsByEmployee: const {},
    );
    expect(
      loaded.singleWhere((i) => i.label.contains('no KPI set')).count,
      2,
    );
  });

  test('says nothing when every holder has an on-role set', () {
    final items = _run(
      employees: [_emp('e1', 'One', 'card-1')],
      cards: [_card('card-1')],
      roleKpiIdsByCard: const {
        'card-1': {'k1'},
      },
      assignedKpiIdsByEmployee: const {
        'e1': {'k1'},
      },
    );
    expect(items.where((i) => i.label.contains('no KPI set')), isEmpty);
  });

  test('a seat with more than five roles is flagged; exactly five is not', () {
    final over = _run(areaCountBySeat: const {'rs1': 6, 'rs2': 5});
    final item = over.singleWhere((i) => i.label.contains('more than five'));
    expect(item.count, 1); // only rs1 — rs2's exactly-5 does not qualify
    expect(item.category, AttentionCategory.structure);
    expect(item.target, AttentionTarget.roles);

    final atFive = _run(areaCountBySeat: const {'rs2': 5});
    expect(atFive.where((i) => i.label.contains('more than five')), isEmpty);
  });

  test('an open seat is flagged once, not once per missing holder', () {
    final items = _run(
      holderCountBySeat: const {'rs1': 0, 'rs2': 2, 'rs3': 0},
    );
    final item = items.singleWhere((i) => i.label.contains('open seat'));
    expect(item.count, 2); // rs1 and rs3 — rs2 has holders
    expect(item.category, AttentionCategory.structure);
    expect(item.target, AttentionTarget.roles);
  });

  test('no open/oversized seats -> neither structure signal appears', () {
    final items = _run(
      areaCountBySeat: const {'rs1': 3},
      holderCountBySeat: const {'rs1': 1},
    );
    expect(items.where((i) => i.label.contains('more than five')), isEmpty);
    expect(items.where((i) => i.label.contains('open seat')), isEmpty);
  });

  test('high-severity items rank before medium', () {
    final items = _run(
      loads: [_load('a', fixed: 200)], // high
      tasks: [_t('u1', owner: 'x')], // medium (uncosted essential)
    );
    expect(items.first.severity, AttentionSeverity.high);
  });
}
