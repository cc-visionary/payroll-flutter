import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/assignment_panel.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final List<Map<String, double>> allocationCalls = [];
  final List<String> deleted = [];
  final List<WpTaskAssignment> upserted = [];

  @override
  Future<void> setAllocations(Map<String, double> pctById) async {
    allocationCalls.add(pctById);
  }

  @override
  Future<void> deleteAssignment(String id) async {
    deleted.add(id);
  }

  @override
  Future<void> upsertAssignment(WpTaskAssignment a) async {
    upserted.add(a);
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _card = RoleScorecard(
  id: 'rs1',
  companyId: 'c',
  jobTitle: 'Sales & Ops Assistant',
  missionStatement: '',
  responsibilities: const [],
  kpis: const [],
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026, 1, 1),
);

final _employee = Employee(
  id: 'e1',
  companyId: 'c',
  employeeNumber: 'E1',
  firstName: 'Evander',
  lastName: 'Cruz',
  employmentType: 'REGULAR',
  employmentStatus: 'ACTIVE',
  hireDate: DateTime(2026, 1, 1),
  isRankAndFile: false,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  taxOnFullEarnings: false,
  accruedThirteenthMonthBasis: Decimal.zero,
);

const _primaryRow = WpTaskAssignment(
  id: 'a1',
  companyId: 'c',
  taskId: 't1',
  roleScorecardId: 'rs1',
  assignmentRole: 'PRIMARY',
  allocationPct: 60,
);

const _contributorRow = WpTaskAssignment(
  id: 'a2',
  companyId: 'c',
  taskId: 't1',
  employeeId: 'e1',
  assignmentRole: 'CONTRIBUTOR',
  allocationPct: 40,
);

Widget _host(_FakeRepo repo, List<WpTaskAssignment> rows) {
  return ProviderScope(
    overrides: [
      wpAssignmentsByTaskProvider.overrideWith((ref) async => {'t1': rows}),
      workforcePlanningRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: AssignmentPanel(
            taskId: 't1',
            companyId: 'c',
            taskHours: 100,
            cards: [_card],
            employees: [_employee],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('total chip reads = 100% when rows sum to 100', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_FakeRepo(), [_primaryRow, _contributorRow]));
    await tester.pumpAndSettle();

    expect(find.text('= 100%'), findsOneWidget);
  });

  testWidgets('Split equally calls setAllocations with both ids at 50', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo, [_primaryRow, _contributorRow]));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Split equally'));
    await tester.pumpAndSettle();

    expect(repo.allocationCalls, hasLength(1));
    expect(repo.allocationCalls.single, {'a1': 50.0, 'a2': 50.0});
  });

  testWidgets('a lone 60% row reads a warning chip', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_FakeRepo(), [_primaryRow]));
    await tester.pumpAndSettle();

    expect(find.text('⚠ 60%'), findsOneWidget);
  });

  testWidgets(
      'editing a % field back to its first-rendered value still writes '
      '(C1 regression: the focus-loss listener must resolve the CURRENT row, '
      'not the one captured when the FocusNode was first created)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    // Mirrors what a real invalidate+refetch returns after a write: the row
    // reflects the LAST successful commit, not the first-rendered value. A
    // provider override that always returns the same fixed row can't tell
    // the stale-closure bug apart from the fix — both would read the same
    // object either way — so this has to track the fake repo's writes.
    WpTaskAssignment currentA1() => repo.upserted.isEmpty
        ? _primaryRow
        : WpTaskAssignment(
            id: 'a1',
            companyId: 'c',
            taskId: 't1',
            roleScorecardId: 'rs1',
            assignmentRole: 'PRIMARY',
            allocationPct: repo.upserted.last.allocationPct,
          );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Override the SOURCE provider, not the derived wpAssignmentsByTaskProvider
        // — _invalidate() invalidates wpTaskAssignmentsProvider, and
        // wpAssignmentsByTaskProvider only recomputes because it `ref.watch`es
        // that provider's `.future`. Overriding the derived provider directly
        // would sever that dependency and the invalidation would never arrive.
        wpTaskAssignmentsProvider.overrideWith((ref) async => [currentA1()]),
        workforcePlanningRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: AssignmentPanel(
              taskId: 't1',
              companyId: 'c',
              taskHours: 100,
              cards: [_card],
              employees: [_employee],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('pct-a1'));

    await tester.enterText(field, '50');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.enterText(field, '60');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(repo.upserted.map((a) => a.allocationPct).toList(), [50.0, 60.0]);
  });
}
