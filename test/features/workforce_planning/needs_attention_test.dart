import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart' show KpiAssignee;
import 'package:payroll_flutter/features/workforce_planning/needs_attention.dart';

WpPersonLoad _load(String id, {required double fixed, double cap = 160}) =>
    WpPersonLoad(employeeId: id, companyId: 'c', hoursFixed: fixed, capacityHours: cap);

WpTask _t(String id, {String? card, String? owner, String? crit,
        bool essential = true, bool expectation = false}) =>
    WpTask(id: id, companyId: 'c', name: id, roleScorecardId: card,
        ownerEmployeeId: owner, criticality: crit, isEssential: essential,
        isExpectation: expectation);

RoleScorecard _card(String id, {bool active = true, String? dept}) => RoleScorecard(
      id: id, companyId: 'c', jobTitle: id, missionStatement: '', departmentId: dept,
      responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
      workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: active,
      effectiveDate: DateTime(2026));

Kpi _kpi(String id, {bool active = true, String? unit, String? dept}) => Kpi(
      id: id, companyId: 'c', name: id, isActive: active,
      measurementUnit: unit, departmentId: dept);

List<AttentionItem> _run({
  List<WpPersonLoad> loads = const [], List<WpTask> tasks = const [],
  List<Employee> employees = const [], List<RoleScorecard> cards = const [],
  List<Kpi> kpis = const [], Map<String, List<KpiAssignee>> assigned = const {},
  Map<String, List<WpTaskAssignment>> assignmentsByTask = const {},
}) =>
    buildNeedsAttention(loads: loads, tasks: tasks, employees: employees,
        cards: cards, kpis: kpis, kpiAssignedByKpi: assigned,
        assignmentsByTask: assignmentsByTask);

WpTaskAssignment _a(String id, String taskId, double pct) => WpTaskAssignment(
    id: id, companyId: 'c', taskId: taskId, allocationPct: pct);

AttentionItem? _find(List<AttentionItem> items, AttentionTarget target, AttentionSeverity sev) {
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
      tasks: [_t('o1', crit: 'CRITICAL'), _t('o2')], // both unowned, no card -> orphans
    );
    final crit = _find(items, AttentionTarget.unassigned, AttentionSeverity.high)!;
    expect(crit.count, 1);
    final all = _find(items, AttentionTarget.unassigned, AttentionSeverity.medium)!;
    expect(all.count, 2);
  });

  test('uncosted essential (not expectation) is a Process/tasks item', () {
    final items = _run(tasks: [
      _t('u1', owner: 'x'), // essential, no hours, owned so NOT an orphan
      _t('u2', owner: 'x', expectation: true, essential: false), // expectation, excluded
    ]);
    final proc = _find(items, AttentionTarget.tasks, AttentionSeverity.medium)!;
    expect(proc.count, 1); // only u1
  });

  test('shares that don\'t total 100% are a Process/tasks item; exact 100 is not', () {
    final short = _run(
      tasks: [_t('s1', owner: 'x')],
      assignmentsByTask: {'s1': [_a('a1', 's1', 40), _a('a2', 's1', 30)]}, // totals 70
    );
    final proc = short.where((i) => i.label.contains("don't total 100%")).toList();
    expect(proc.length, 1);
    expect(proc.single.count, 1);
    expect(proc.single.severity, AttentionSeverity.medium);
    expect(proc.single.target, AttentionTarget.tasks);

    final exact = _run(
      tasks: [_t('s2', owner: 'x')],
      assignmentsByTask: {'s2': [_a('a3', 's2', 60), _a('a4', 's2', 40)]}, // totals 100
    );
    expect(exact.where((i) => i.label.contains("don't total 100%")), isEmpty);
  });

  test('KPI signals: measuring nobody, no measurement, no department', () {
    final items = _run(
      kpis: [_kpi('k1', unit: 'orders', dept: 'd1')], // assigned below -> only... see asserts
      assigned: {'k1': [const KpiAssignee(employeeId: 'e', name: 'E')]},
    );
    // k1 is assigned, has a unit and a dept -> no KPI signals at all
    expect(items.where((i) => i.target == AttentionTarget.kpiLibrary), isEmpty);

    final bad = _run(kpis: [_kpi('k2')]); // unassigned, no unit, no dept
    final lib = bad.where((i) => i.target == AttentionTarget.kpiLibrary).toList();
    expect(lib.length, 3); // measuring-nobody + no-measurement + no-department
  });

  test('unstaffed card with CRITICAL work, and card with no department', () {
    final items = _run(
      cards: [_card('rs1'), _card('rs2', dept: 'd1')],
      tasks: [_t('t1', card: 'rs1', crit: 'CRITICAL')], // rs1 has no holders
      employees: const [], // nobody staffs rs1
    );
    final struct = items.where((i) =>
        i.category == AttentionCategory.structure && i.target == AttentionTarget.roles);
    // unstaffed-critical (rs1) + no-department (rs1 only; rs2 has a dept)
    expect(struct.any((i) => i.count == 1), isTrue);
    expect(struct.length, 2);
  });

  test('high-severity items rank before medium', () {
    final items = _run(
      loads: [_load('a', fixed: 200)],          // high
      tasks: [_t('u1', owner: 'x')],            // medium (uncosted essential)
    );
    expect(items.first.severity, AttentionSeverity.high);
  });
}
