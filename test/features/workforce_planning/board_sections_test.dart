import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/board/board_sections.dart';
import 'package:payroll_flutter/features/workforce_planning/role_load.dart';

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

Employee emp(String id, {String? roleId, String status = 'ACTIVE', bool deleted = false}) => Employee(
  id: id, companyId: 'c', employeeNumber: id, firstName: id, lastName: 'X',
  roleScorecardId: roleId,
  employmentType: 'FULL_TIME', employmentStatus: status,
  hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
  isNdEligible: false, isHolidayPayEligible: false,
  sssEligibilityOverride: false, philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false, taxOnFullEarnings: false,
  deletedAt: deleted ? DateTime(2026) : null,
);

Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  testWidgets('People load strip: sorts by load desc, shows no-role last, hides inactive', (tester) async {
    final busyRole = role('busy', 'Busy Role');
    final lightRole = role('light', 'Light Role');

    final busyTask = WpTask(id: 'busy-task', companyId: 'c', name: 'Heavy work', roleScorecardId: 'busy');
    final lightTask = WpTask(id: 'light-task', companyId: 'c', name: 'Light work', roleScorecardId: 'light');

    final employees = [
      emp('alice', roleId: 'busy'),      // on busy role (>50% load)
      emp('bob', roleId: 'light'),       // on light role (<50% load)
      emp('charlie', roleId: null),      // no role
      emp('deleted', roleId: 'busy', deleted: true), // deleted
      emp('inactive', roleId: 'busy', status: 'RESIGNED'), // inactive status
    ];

    final loads = buildRoleLoads(
      roles: [busyRole, lightRole],
      employees: employees,
      tasks: [busyTask, lightTask],
      hoursByTaskId: {'busy-task': 160, 'light-task': 40},
      capacityByEmployee: {'alice': 160, 'bob': 160},
      defaultCapacity: 160,
    );

    // Set wide test surface for deterministic Wrap layout
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(PeopleLoadStrip(loads: loads, employees: employees)));

    // Active employees with roles are shown
    expect(find.textContaining('alice'), findsOneWidget);
    expect(find.textContaining('bob'), findsOneWidget);

    // No-role person is shown
    expect(find.textContaining('charlie no role'), findsOneWidget);

    // Deleted and inactive employees should not be shown
    expect(find.textContaining('deleted'), findsNothing);
    expect(find.textContaining('inactive'), findsNothing);

    // Verify load percentages are shown for those with roles
    expect(find.textContaining('100%'), findsWidgets); // alice at 100% load
    expect(find.textContaining('25%'), findsWidgets);  // bob at 25% load

    // No overflow errors
    expect(tester.takeException(), isNull);
  });

  testWidgets('No role section: hidden when empty, counts and lists tasks', (tester) async {
    await tester.pumpWidget(wrap(NoRoleSection(tasks: const [], hoursById: const {}, onOpenTask: (_) {})));
    expect(find.textContaining('No role yet'), findsNothing);

    await tester.pumpWidget(wrap(NoRoleSection(
      tasks: const [WpTask(id: 'a', companyId: 'c', name: 'Orphan work')],
      hoursById: const {'a': 12}, onOpenTask: (_) {})));
    expect(find.text('No role yet (1)'), findsOneWidget);
    expect(find.text('Orphan work'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-a')), findsOneWidget);
  });

  testWidgets('Check these: shows was-note and current role; Looks right calls back', (tester) async {
    WpTask? confirmed;
    await tester.pumpWidget(wrap(FlaggedSection(
      tasks: const [WpTask(id: 'a', companyId: 'c', name: 'Split task', roleScorecardId: 'om',
          allocationReviewNote: 'was: Jeremy 60%, Brand Handler 40%')],
      rolesById: {'om': role('om', 'Ops Manager')},
      onLooksRight: (t) async => confirmed = t,
      onOpenTask: (_) {})));
    expect(find.text('Check these (1)'), findsOneWidget);
    expect(find.textContaining('now: Ops Manager'), findsOneWidget);
    expect(find.textContaining('was: Jeremy 60%'), findsOneWidget);
    await tester.tap(find.text('Looks right'));
    await tester.pump();
    expect(confirmed?.id, 'a');
  });
}
