import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart'
    show KpiAssignee;
import 'package:payroll_flutter/features/kpi_library/kpi_rows.dart';

Kpi _k(String id, String name,
        {String? category, String? measure, bool active = true, String? dept}) =>
    Kpi(
      id: id, companyId: 'c', name: name, category: category,
      measurementUnit: measure, isActive: active, departmentId: dept,
    );

const _deptNames = {'d1': 'Operations', 'd2': 'Human Resources'};

KpiAssignee _a(String id) => KpiAssignee(employeeId: id, name: 'Person $id');

void main() {
  final kpis = [
    _k('1', 'Order Accuracy', category: 'Quality & Accuracy', measure: 'errors ÷ orders'),
    _k('2', 'On-Time Dispatch', category: 'Timeliness & Delivery', measure: 'within cutoff'),
    _k('3', 'Loose end', measure: 'something'),
    _k('4', 'Retired metric', category: 'Quality & Accuracy', active: false),
  ];
  final assigned = {
    '1': [_a('e1'), _a('e2')],
    '2': <KpiAssignee>[],
  };

  group('categories', () {
    test('blank or missing reads as Uncategorized', () {
      expect(kpiCategoryOf(_k('x', 'n')), kUncategorized);
      expect(kpiCategoryOf(_k('x', 'n', category: '   ')), kUncategorized);
      expect(kpiCategoryOf(_k('x', 'n', category: ' Quality ')), 'Quality');
    });

    test('Uncategorized sorts LAST — it is a gap, not a category', () {
      expect(kpiCategories(kpis),
          ['Quality & Accuracy', 'Timeliness & Delivery', kUncategorized]);
    });

    test('grouping sorts KPIs by name within each category', () {
      final g = groupKpisByCategory([
        _k('a', 'Zebra', category: 'Q'),
        _k('b', 'Alpha', category: 'Q'),
      ]);
      expect(g['Q']!.map((k) => k.name), ['Alpha', 'Zebra']);
    });
  });

  group('filtering', () {
    test('deactivated KPIs are hidden unless asked for', () {
      expect(applyKpiFilter(kpis, const KpiFilter(), assigned).map((k) => k.id),
          ['1', '2', '3'],
          reason: 'a deactivated KPI cannot be picked, so it is noise by default');
      expect(
          applyKpiFilter(kpis, const KpiFilter(showInactive: true), assigned)
              .map((k) => k.id),
          ['1', '2', '3', '4']);
    });

    test('search covers name, category and measurement', () {
      List<String> ids(String q) =>
          applyKpiFilter(kpis, KpiFilter(query: q), assigned).map((k) => k.id).toList();
      expect(ids('dispatch'), ['2']);
      expect(ids('quality'), ['1'], reason: 'category is searchable');
      expect(ids('÷ orders'), ['1'], reason: 'measurement is searchable');
      expect(ids('  ORDER  '), ['1'], reason: 'case and padding ignored');
    });

    test('assignment filter separates tracked from measuring-nobody', () {
      expect(
          applyKpiFilter(kpis, const KpiFilter(assignment: true), assigned)
              .map((k) => k.id),
          ['1']);
      expect(
          applyKpiFilter(kpis, const KpiFilter(assignment: false), assigned)
              .map((k) => k.id),
          ['2', '3'],
          reason: 'an empty list and a missing key both mean nobody');
    });

    test('category filter, and filters combine', () {
      expect(
          applyKpiFilter(kpis, const KpiFilter(category: 'Quality & Accuracy'), assigned)
              .map((k) => k.id),
          ['1']);
      expect(
        applyKpiFilter(kpis,
                const KpiFilter(category: 'Quality & Accuracy', assignment: false),
                assigned)
            .map((k) => k.id),
        isEmpty,
        reason: 'AND, not OR',
      );
    });
  });

  group('stats', () {
    test('counts actives, coverage, and distinct people', () {
      final s = kpiLibraryStats(kpis, assigned);
      expect(s.total, 4);
      expect(s.active, 3, reason: 'the deactivated one is not part of coverage');
      expect(s.assigned, 1);
      expect(s.unassigned, 2);
      expect(s.uncategorized, 1);
      expect(s.categories, 2, reason: 'Uncategorized is not a category');
      expect(s.peopleTracked, 2);
      expect(s.assignedFraction, closeTo(1 / 3, 0.001));
    });

    test('an empty library does not divide by zero', () {
      final s = kpiLibraryStats(const [], const {});
      expect(s.active, 0);
      expect(s.assignedFraction, 0);
    });

    test('a person tracked on two KPIs counts once', () {
      final s = kpiLibraryStats(
        [_k('1', 'A', category: 'Q'), _k('2', 'B', category: 'Q')],
        {'1': [_a('same')], '2': [_a('same')]},
      );
      expect(s.peopleTracked, 1);
      expect(s.assigned, 2);
    });
  });

  group('departments', () {
    final withDepts = [
      _k('1', 'Order Accuracy', category: 'Quality', dept: 'd1'),
      _k('2', 'Onboarding', category: 'People', dept: 'd2'),
      _k('3', 'Homeless metric', category: 'Quality'),
      _k('4', 'Dangling ref', category: 'Quality', dept: 'gone'),
    ];

    test('a missing or unknown department id reads as "No department"', () {
      expect(kpiDepartmentOf(withDepts[0], _deptNames), 'Operations');
      expect(kpiDepartmentOf(withDepts[2], _deptNames), kNoDepartment);
      expect(kpiDepartmentOf(withDepts[3], _deptNames), kNoDepartment,
          reason: 'a deleted department must not crash or invent a name');
    });

    test('"No department" sorts last — it is a gap, not a department', () {
      expect(kpiDepartments(withDepts, _deptNames),
          ['Human Resources', 'Operations', kNoDepartment]);
    });

    test('grouping nests department -> category -> KPIs', () {
      final g = groupKpisByDepartment(withDepts, _deptNames);
      expect(g.keys, ['Human Resources', 'Operations', kNoDepartment]);
      expect(g['Operations']!.keys, ['Quality']);
      expect(g['Operations']!['Quality']!.map((k) => k.name), ['Order Accuracy']);
      expect(g[kNoDepartment]!['Quality']!.map((k) => k.name),
          ['Dangling ref', 'Homeless metric'],
          reason: 'a dangling department ref is a gap, not a department');
    });

    test('filtering by department', () {
      expect(
        applyKpiFilter(withDepts, const KpiFilter(department: 'Operations'),
                const {}, departmentNameById: _deptNames)
            .map((k) => k.id),
        ['1'],
      );
      expect(
        applyKpiFilter(withDepts, const KpiFilter(department: kNoDepartment),
                const {}, departmentNameById: _deptNames)
            .map((k) => k.id),
        ['3', '4'],
      );
    });

    test('stats count departments and the gap', () {
      final s = kpiLibraryStats(withDepts, const {},
          departmentNameById: _deptNames);
      expect(s.departments, 2, reason: '"No department" is not a department');
      expect(s.noDepartment, 2);
    });
  });
}
