import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/board/board_sections.dart';

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
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
