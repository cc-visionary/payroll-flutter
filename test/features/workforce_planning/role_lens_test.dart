import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/role_view_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

RoleScorecard _card(String id, String title, {String? base}) => RoleScorecard(
  id: id,
  companyId: 'c',
  jobTitle: title,
  missionStatement: '',
  responsibilities: const [],
  kpis: const [],
  baseSalary: base == null ? null : Decimal.parse(base),
  wageType: 'DAILY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026, 1, 1),
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

WpPersonLoad _load(String id) => WpPersonLoad(
  employeeId: id,
  companyId: 'c',
  capacityHours: 160,
  growthMultiplier: 1,
);

Widget _host({
  required List<RoleScorecard> cards,
  required List<Employee> employees,
  required List<WpTask> tasks,
  required List<WpTaskComputed> computed,
}) => ProviderScope(
  overrides: [
    roleScorecardListProvider.overrideWith((ref) async => cards),
    wpActiveEmployeesProvider.overrideWith((ref) async => employees),
    wpTasksProvider.overrideWith((ref) async => tasks),
    wpAllTaskComputedProvider.overrideWith((ref) async => computed),
    wpPersonLoadsProvider.overrideWith(
      (ref) async => [for (final e in employees) _load(e.id)],
    ),
    wpNodesProvider.overrideWith((ref) async => const []),
    wpConfigProvider.overrideWith((ref) async => null),
  ],
  child: const MaterialApp(home: Scaffold(body: RoleViewTab())),
);

// The person/role toggle is gone: the tab IS the role lens now, because
// Balance answers the per-person question better.
Future<void> _toRoleLens(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the role rollup directly, with no person lens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        cards: [_card('rs1', 'Operations Manager', base: '1000')],
        employees: [_emp('e1', 'Jeremy', 'rs1')],
        tasks: const [],
        computed: const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Operations Manager'), findsOneWidget);
    expect(
      find.text('Owned tasks'),
      findsNothing,
      reason: 'the per-person view lives on Balance now',
    );
    expect(find.text('By role'), findsNothing, reason: 'no toggle to switch');
  });

  testWidgets('shows hours, load, cost and cost-per-hour for a costed role', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        cards: [_card('rs1', 'Operations Manager', base: '1000')],
        employees: [_emp('e1', 'Jeremy', 'rs1')],
        tasks: const [
          WpTask(
            id: 't1',
            companyId: 'c',
            name: 'Pack',
            roleScorecardId: 'rs1',
          ),
        ],
        computed: const [
          WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 80),
        ],
      ),
    );
    await _toRoleLens(tester);

    // Twice: the role row and the Total row, which is correct with one role.
    expect(find.text('80.0'), findsNWidgets(2));
    expect(find.text('50%'), findsOneWidget, reason: '80h of 160h capacity');
    // 1000/day x 26 days = 26,000; over 80h = 325/h
    expect(find.text('₱26,000'), findsWidgets);
    expect(find.text('₱325'), findsOneWidget);
  });

  testWidgets('an uncosted role shows dashes, never a confident 0%', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        cards: [_card('rs1', 'HR Manager', base: '1000')],
        employees: [_emp('e1', 'Brixter', 'rs1')],
        tasks: const [
          WpTask(id: 't1', companyId: 'c', name: 'A', roleScorecardId: 'rs1'),
          WpTask(id: 't2', companyId: 'c', name: 'B', roleScorecardId: 'rs1'),
        ],
        computed: const [],
      ),
    );
    await _toRoleLens(tester);

    expect(
      find.text('0%'),
      findsNothing,
      reason: 'an uncosted role is unknown, not idle',
    );
    expect(
      find.text('0/2'),
      findsWidgets,
      reason: 'costed/total is spelled out',
    );
    // Cost is still known even though effort is not.
    expect(find.text('₱26,000'), findsWidgets);
  });

  testWidgets('warns how many responsibilities are uncosted', (tester) async {
    await tester.pumpWidget(
      _host(
        cards: [_card('rs1', 'Ops', base: '1000')],
        employees: [_emp('e1', 'J', 'rs1')],
        tasks: const [
          WpTask(id: 't1', companyId: 'c', name: 'A', roleScorecardId: 'rs1'),
          WpTask(id: 't2', companyId: 'c', name: 'B', roleScorecardId: 'rs1'),
        ],
        computed: const [
          WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 10),
        ],
      ),
    );
    await _toRoleLens(tester);
    expect(
      find.textContaining('1 of 2 responsibilities are not costed'),
      findsOneWidget,
    );
  });

  testWidgets('a vacant role shows no capacity and no cost', (tester) async {
    await tester.pumpWidget(
      _host(
        cards: [_card('rs1', 'Vacant Role', base: '1000')],
        employees: [_emp('e1', 'Someone', null)],
        tasks: const [
          WpTask(id: 't1', companyId: 'c', name: 'A', roleScorecardId: 'rs1'),
        ],
        computed: const [
          WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 40),
        ],
      ),
    );
    await _toRoleLens(tester);

    expect(find.text('Vacant Role'), findsOneWidget);
    expect(
      find.text('40.0'),
      findsNWidgets(2),
      reason: 'the work still exists — role row plus Total row',
    );
    expect(
      find.text('₱0'),
      findsWidgets,
      reason: 'nobody is being paid for it',
    );
  });

  testWidgets('the total row does not invent a company-wide load percentage', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        cards: [
          _card('rs1', 'A', base: '1000'),
          _card('rs2', 'B', base: '500'),
        ],
        employees: [_emp('e1', 'X', 'rs1'), _emp('e2', 'Y', 'rs2')],
        tasks: const [
          WpTask(id: 't1', companyId: 'c', name: 'T', roleScorecardId: 'rs1'),
        ],
        computed: const [
          WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 80),
        ],
      ),
    );
    await _toRoleLens(tester);

    expect(find.text('Total'), findsOneWidget);
    // 26,000 + 13,000
    expect(find.text('₱39,000'), findsOneWidget);
  });
}
