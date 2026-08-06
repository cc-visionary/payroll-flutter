import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/features/workforce_planning/org_chart_view.dart';

Employee _e(String id, String f, String l, String? mgr) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: f,
  lastName: l,
  jobTitle: 'Role $id',
  reportsToId: mgr,
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

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders the reporting hierarchy (manager + report)', (
    tester,
  ) async {
    final emps = {
      'ceo': _e('ceo', 'Cy', 'Oh', null),
      'coo': _e('coo', 'Coo', 'Boss', 'ceo'),
    };
    await tester.pumpWidget(
      _host(
        OrgChartView(
          people: const [
            (id: 'ceo', parentId: null),
            (id: 'coo', parentId: 'ceo'),
          ],
          empById: emps,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cy Oh'), findsOneWidget);
    expect(find.text('Coo Boss'), findsOneWidget);
  });

  // Guards the reason this tracks `_collapsed` instead of `_expanded`: the old
  // widget seeded its expanded set once in initState, so a subtree that only
  // became non-empty after a later data load stayed shut.
  testWidgets('descendants are visible by default, at every depth', (
    tester,
  ) async {
    final emps = {
      'a': _e('a', 'A', 'One', null),
      'b': _e('b', 'B', 'Two', 'a'),
      'c': _e('c', 'C', 'Three', 'b'),
    };
    await tester.pumpWidget(
      _host(
        OrgChartView(
          people: const [
            (id: 'a', parentId: null),
            (id: 'b', parentId: 'a'),
            (id: 'c', parentId: 'b'),
          ],
          empById: emps,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('C Three'),
      findsOneWidget,
      reason: 'grandchild must not start collapsed',
    );
  });

  testWidgets('collapsing a manager hides their subtree', (tester) async {
    final emps = {
      'a': _e('a', 'A', 'One', null),
      'b': _e('b', 'B', 'Two', 'a'),
    };
    await tester.pumpWidget(
      _host(
        OrgChartView(
          people: const [(id: 'a', parentId: null), (id: 'b', parentId: 'a')],
          empById: emps,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('B Two'), findsOneWidget);

    await tester.tap(find.text('1 report'));
    await tester.pumpAndSettle();
    expect(find.text('B Two'), findsNothing);

    await tester.tap(find.text('1 report'));
    await tester.pumpAndSettle();
    expect(find.text('B Two'), findsOneWidget);
  });

  testWidgets('multiple roots all render side by side', (tester) async {
    final emps = {
      'r1': _e('r1', 'One', 'Root', null),
      'r2': _e('r2', 'Two', 'Root', null),
      'r3': _e('r3', 'Three', 'Root', null),
    };
    await tester.pumpWidget(
      _host(
        OrgChartView(
          people: const [
            (id: 'r1', parentId: null),
            (id: 'r2', parentId: null),
            (id: 'r3', parentId: null),
          ],
          empById: emps,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final n in ['One Root', 'Two Root', 'Three Root']) {
      expect(find.text(n), findsOneWidget);
    }
  });

  testWidgets('the trailing hook renders beside the name', (tester) async {
    final emps = {'a': _e('a', 'A', 'One', null)};
    await tester.pumpWidget(
      _host(
        OrgChartView(
          people: const [(id: 'a', parentId: null)],
          empById: emps,
          trailing: (_) => const Text('Under'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Under'), findsOneWidget);
  });

  testWidgets('a person with no employee record still renders as its id', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const OrgChartView(
          people: [(id: 'ghost', parentId: null)],
          empById: {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ghost'), findsOneWidget);
  });
}
