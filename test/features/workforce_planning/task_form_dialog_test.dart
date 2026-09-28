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
      expect(validateTaskForm(name: '', roleId: 'r', frequency: TaskFrequency.daily, minutesText: '5', area: 'A'), 'Name is required.');
      expect(validateTaskForm(name: 'x', roleId: null, frequency: TaskFrequency.daily, minutesText: '5', area: 'A'), 'Pick the role that does this.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.daily, minutesText: '', area: 'A'), 'How long does it take each time?');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.custom, customHoursText: '', area: 'A'), 'Enter hours per month.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.perOrder, minutesText: '3', area: 'A'), 'Pick what the orders are counted from.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.weekly, minutesText: '30', area: 'A'), isNull);
    });

    test('R11: an area is required once a role is set', () {
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.weekly, minutesText: '30', area: '  '),
          'Pick the area this sits under on the role card.');
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.weekly, minutesText: '30'),
          'Pick the area this sits under on the role card.');
    });

    test('minutesFromRate: true and blank minutes returns null', () {
      expect(validateTaskForm(name: 'x', roleId: 'r', frequency: TaskFrequency.weekly, minutesText: '', minutesFromRate: true, area: 'A'), isNull);
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

    test('R3/R11: changing role without picking an area takes the new role\'s default; keeping the role keeps it', () {
      const existing = WpTask(id: 't1', companyId: 'c', name: 'Pack', roleScorecardId: 'bh',
          responsibilityArea: 'Fulfilment');
      final changedRole = buildTaskFromForm(existing: existing, companyId: 'c', name: 'Pack', roleId: 'om',
          frequency: TaskFrequency.weekly, minutesText: '10', more: More.of(existing), defaultArea: 'Reporting');
      expect(changedRole.responsibilityArea, 'Reporting', reason: 'never the old role\'s area');

      final picked = buildTaskFromForm(existing: existing, companyId: 'c', name: 'Pack', roleId: 'om',
          responsibilityArea: 'Audits', frequency: TaskFrequency.weekly, minutesText: '10',
          more: More.of(existing), defaultArea: 'Reporting');
      expect(picked.responsibilityArea, 'Audits');

      final sameRole = buildTaskFromForm(existing: existing, companyId: 'c', name: 'Pack', roleId: 'bh',
          frequency: TaskFrequency.weekly, minutesText: '10', more: More.of(existing));
      expect(sameRole.responsibilityArea, 'Fulfilment');

      final fresh = buildTaskFromForm(companyId: 'c', name: 'New', roleId: 'om',
          frequency: TaskFrequency.weekly, minutesText: '10');
      expect(fresh.responsibilityArea, 'Responsibilities');
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

  group('Area (ruling R11)', () {
    final cards = [roleWith('bh', 'Brand Handler', ['Fulfilment', 'Customer care']), role('om', 'Ops Manager')];

    testWidgets('a new task on a role with areas defaults to its first area', (tester) async {
      final result = await openDialog(tester, TaskFormDialog(companyId: 'c', cards: cards, initialRoleId: 'bh'));
      expect(find.text('Area'), findsOneWidget, reason: 'in the main form, not under More details');
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Count stock');
      await tester.enterText(find.widgetWithText(TextFormField, 'Minutes each time'), '10');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result()!.responsibilityArea, 'Fulfilment');
    });

    testWidgets('a role with no areas yet defaults to "Responsibilities"', (tester) async {
      final result = await openDialog(tester, TaskFormDialog(companyId: 'c', cards: cards, initialRoleId: 'om'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Weekly report');
      await tester.enterText(find.widgetWithText(TextFormField, 'Minutes each time'), '30');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result()!.responsibilityArea, 'Responsibilities');
    });

    testWidgets('changing the role re-defaults the area to the new role\'s', (tester) async {
      const existing = WpTask(id: 't1', companyId: 'c', name: 'Report', roleScorecardId: 'om',
          responsibilityArea: 'Responsibilities', cadence: 'WEEKLY', timesManual: 52 / 12, minutesManual: 30);
      final result = await openDialog(tester, TaskFormDialog(existing: existing, companyId: 'c', cards: cards));
      await tester.tap(find.text('Ops Manager'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brand Handler').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result()!.roleScorecardId, 'bh');
      expect(result()!.responsibilityArea, 'Fulfilment');
    });

    testWidgets('editing without changing role keeps the existing area', (tester) async {
      const existing = WpTask(id: 't1', companyId: 'c', name: 'Reply', roleScorecardId: 'bh',
          responsibilityArea: 'Customer care', cadence: 'DAILY', timesManual: 26, minutesManual: 5);
      final result = await openDialog(tester, TaskFormDialog(existing: existing, companyId: 'c', cards: cards));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result()!.responsibilityArea, 'Customer care');
    });

    testWidgets('a new area can be typed', (tester) async {
      final result = await openDialog(tester, TaskFormDialog(companyId: 'c', cards: cards, initialRoleId: 'bh'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Count stock');
      await tester.enterText(find.widgetWithText(TextFormField, 'Minutes each time'), '10');
      await tester.tap(find.text('Fulfilment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ New area…').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'New area name'), 'Inventory');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result()!.responsibilityArea, 'Inventory');
    });
  });

  testWidgets('F5: manual times + rate minutes + free-text cadence prefills Custom hours and saves unchanged', (tester) async {
    const legacy = WpTask(id: 't1', companyId: 'c', name: 'Pack', roleScorecardId: 'bh',
        responsibilityArea: 'Fulfilment', cadence: 'twice a week', timesManual: 8,
        minutesSource: 'rate', rateId: 'r1');
    final result = await openDialog(tester, TaskFormDialog(
      existing: legacy, companyId: 'c', cards: [role('bh', 'Brand Handler')],
      rates: const [WpRate(id: 'r1', companyId: 'c', name: 'Pack rate', minutesEach: 45)],
    ));
    final field = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Hours / month'));
    expect(double.parse(field.controller!.text), closeTo(6, 1e-9), reason: '8 x 45 min / 60');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result(), isNotNull, reason: 'Save must not be blocked');
    expect(result()!.hoursPerMonth, closeTo(6, 1e-9));
  });
}

RoleScorecard roleWith(String id, String title, List<String> areas) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: [for (final a in areas) ResponsibilityArea(area: a, tasks: const ['x'])],
  kpis: const [], wageType: 'MONTHLY', workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI',
  isActive: true, effectiveDate: DateTime(2026),
);

/// Opens [dialog] and returns a getter for what it popped with.
Future<WpTask? Function()> openDialog(WidgetTester tester, Widget dialog) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  WpTask? popped;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
    onPressed: () async => popped = await showDialog<WpTask>(context: context, builder: (_) => dialog),
    child: const Text('open')))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => popped;
}
