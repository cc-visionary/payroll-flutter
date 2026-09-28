import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/frequency.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/task_form_dialog.dart';

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

void main() {
  group('validateTaskForm', () {
    test('requires name, role and a duration', () {
      expect(validateTaskForm(name: '', roleId: 'r', frequency: TaskFrequency.daily, minutesText: '5'), 'Name is required.');
      expect(validateTaskForm(name: 'x', roleId: null, frequency: TaskFrequency.daily, minutesText: '5'), 'Pick the role that does this.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.daily, minutesText: ''), 'How long does it take each time?');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.custom, customHoursText: ''), 'Enter hours per month.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.perOrder, minutesText: '3'), 'Pick what the orders are counted from.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.weekly, minutesText: '30'), isNull);
    });

    test('minutesFromRate: true and blank minutes returns null', () {
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.weekly, minutesText: '', minutesFromRate: true), isNull);
    });
  });

  group('buildTaskFromForm', () {
    test('a preset writes cadence token + times + minutes, no direct hours', () {
      final t = buildTaskFromForm(companyId: 'c', name: ' Pack ', roleId: 'bh', frequency: TaskFrequency.daily, minutesText: '60');
      expect(t.name, 'Pack');
      expect(t.cadence, 'DAILY');
      expect(t.timesSource, 'manual');
      expect(t.timesManual, 26);
      expect(t.minutesManual, 60);
      expect(t.hoursPerMonth, isNull);
      expect(t.roleScorecardId, 'bh');
    });

    test('per order writes a driver, not manual times', () {
      final t = buildTaskFromForm(companyId: 'c', name: 'Pick', roleId: 'bh', frequency: TaskFrequency.perOrder, minutesText: '3', driverId: 'orders');
      expect(t.cadence, 'PER_ORDER');
      expect(t.timesSource, 'driver');
      expect(t.driverId, 'orders');
      expect(t.timesManual, isNull);
    });

    test('custom writes direct hours', () {
      final t = buildTaskFromForm(companyId: 'c', name: 'X', roleId: 'bh', frequency: TaskFrequency.custom, customHoursText: '7.5');
      expect(t.hoursPerMonth, 7.5);
      expect(t.cadence, isNull);
    });

    test('editing preserves id, owner, externalRef, sort, More fields', () {
      const existing = WpTask(id: 't1', companyId: 'c', name: 'Old', roleScorecardId: 'bh',
          ownerEmployeeId: 'e1', externalRef: 'X-1', areaSort: 2, taskSort: 5,
          skillTier: 'Managerial', risk: 'High', criticality: 'CRITICAL', notes: 'n');
      final t = buildTaskFromForm(existing: existing, companyId: 'c', name: 'New', roleId: 'om',
          frequency: TaskFrequency.monthly, minutesText: '120', more: More.of(existing));
      expect(t.id, 't1');
      expect(t.ownerEmployeeId, 'e1');
      expect(t.externalRef, 'X-1');
      expect((t.areaSort, t.taskSort), (2, 5));
      expect((t.skillTier, t.risk, t.criticality, t.notes), ('Managerial', 'High', 'CRITICAL', 'n'));
      expect(t.roleScorecardId, 'om');
    });

    test('Review Focus 4: a legacy manual task saved without edits keeps its hours', () {
      const legacy = WpTask(id: 't', companyId: 'c', name: 'L', roleScorecardId: 'bh',
          cadence: 'every other day', timesManual: 13, minutesManual: 30);
      final f = frequencyOf(legacy);
      final t = buildTaskFromForm(existing: legacy, companyId: 'c', name: 'L', roleId: 'bh',
          frequency: f, customHoursText: customHoursOf(legacy)!.toString(), more: More.of(legacy));
      expect(f, TaskFrequency.custom);
      expect(t.hoursPerMonth, closeTo(6.5, 1e-9));
    });

    test('keeps rate on a rate-sourced existing task with blank minutes', () {
      const existing = WpTask(id: 't1', companyId: 'c', name: 'Pack', roleScorecardId: 'bh',
          minutesSource: 'rate', rateId: 'r1');
      final t = buildTaskFromForm(existing: existing, companyId: 'c', name: 'Pack', roleId: 'bh',
          frequency: TaskFrequency.weekly, minutesText: '', more: More.of(existing));
      expect(t.minutesSource, 'rate');
      expect(t.rateId, 'r1');
      expect(t.minutesManual, isNull);
    });

    test('typing minutes switches to manual and clears rateId', () {
      const existing = WpTask(id: 't1', companyId: 'c', name: 'Pack', roleScorecardId: 'bh',
          minutesSource: 'rate', rateId: 'r1');
      final t = buildTaskFromForm(existing: existing, companyId: 'c', name: 'Pack', roleId: 'bh',
          frequency: TaskFrequency.weekly, minutesText: '20', more: More.of(existing));
      expect(t.minutesSource, 'manual');
      expect(t.rateId, isNull);
      expect(t.minutesManual, 20);
    });

    test('editing a task and changing its role clears responsibilityArea; keeping the role keeps it', () {
      const existing = WpTask(id: 't1', companyId: 'c', name: 'Pack', roleScorecardId: 'bh',
          responsibilityArea: 'Fulfilment');
      final changedRole = buildTaskFromForm(existing: existing, companyId: 'c', name: 'Pack', roleId: 'om',
          frequency: TaskFrequency.weekly, minutesText: '10', more: More.of(existing));
      expect(changedRole.responsibilityArea, isNull);

      final sameRole = buildTaskFromForm(existing: existing, companyId: 'c', name: 'Pack', roleId: 'bh',
          frequency: TaskFrequency.weekly, minutesText: '10', more: More.of(existing));
      expect(sameRole.responsibilityArea, 'Fulfilment');
    });
  });

  testWidgets('shows only the essentials until More details is opened', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<WpTask>(context: context, builder: (_) => TaskFormDialog(
        companyId: 'c', cards: [role('bh', 'Brand Handler')], initialRoleId: 'bh',
        holderCountByRole: const {'bh': 2})),
      child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('How often'), findsOneWidget);
    expect(find.text('Minutes each time'), findsOneWidget);
    expect(find.text('Role that does it'), findsOneWidget);
    expect(find.text('Skill tier'), findsNothing);
    expect(find.text('Owner'), findsNothing);

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Minutes each time'), '60');
    await tester.pump();
    expect(find.textContaining('≈ 26.0 h/mo'), findsOneWidget);
    expect(find.textContaining('split across 2 people'), findsOneWidget);

    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(find.text('Skill tier'), findsOneWidget);
  });
}
