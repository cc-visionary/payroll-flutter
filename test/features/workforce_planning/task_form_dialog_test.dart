import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/task_form_dialog.dart';

void main() {
  test('validateTaskForm requires a name', () {
    expect(validateTaskForm(name: '', timesSource: 'manual', minutesSource: 'manual'),
        'Name is required.');
  });
  test('validateTaskForm requires a driver when times source is driver', () {
    expect(
        validateTaskForm(name: 'x', timesSource: 'driver', driverId: null, minutesSource: 'manual'),
        'Pick a driver (or switch Times to Manual).');
  });
  test('validateTaskForm requires a rate when minutes source is rate', () {
    expect(
        validateTaskForm(name: 'x', timesSource: 'manual', minutesSource: 'rate', rateId: null),
        'Pick a rate (or switch Minutes to Manual).');
  });
  test('validateTaskForm passes when complete', () {
    expect(
        validateTaskForm(name: 'x', timesSource: 'driver', driverId: 'd1', minutesSource: 'rate', rateId: 'r1'),
        isNull);
  });

  test('buildTaskFromForm nulls the unused source fields', () {
    final t = buildTaskFromForm(companyId: 'c', name: 'x',
        timesSource: 'driver', timesManualText: '99', driverId: 'd1', driverFactorText: '2',
        minutesSource: 'manual', minutesManualText: '12', rateId: 'r1');
    expect(t.timesManual, isNull);
    expect(t.driverId, 'd1');
    expect(t.driverFactor, 2);
    expect(t.rateId, isNull);
    expect(t.minutesManual, 12);
  });
  test('buildTaskFromForm preserves read-only columns on edit', () {
    const existing = WpTask(id: 't1', companyId: 'c', name: 'old', externalRef: 'T5',
        roleScorecardId: 'rs1', responsibilityArea: 'Area', notes: 'keep me');
    final t = buildTaskFromForm(existing: existing, companyId: 'c', name: 'new',
        timesSource: 'manual', minutesSource: 'manual');
    expect(t.id, 't1');
    expect(t.externalRef, 'T5');
    expect(t.notes, 'keep me');
  });

  // The card link is form-driven, not carried over from `existing`: the Tasks
  // tab now edits the same (card, area) placement the role-card editor does.
  test('buildTaskFromForm takes the card link from the form, not from existing', () {
    const existing = WpTask(id: 't1', companyId: 'c', name: 'old',
        roleScorecardId: 'rs1', responsibilityArea: 'Area');
    final moved = buildTaskFromForm(existing: existing, companyId: 'c', name: 'new',
        timesSource: 'manual', minutesSource: 'manual',
        roleScorecardId: 'rs2', responsibilityArea: 'Other');
    expect(moved.roleScorecardId, 'rs2');
    expect(moved.responsibilityArea, 'Other');

    final unlinked = buildTaskFromForm(existing: existing, companyId: 'c', name: 'new',
        timesSource: 'manual', minutesSource: 'manual');
    expect(unlinked.roleScorecardId, isNull);
    expect(unlinked.responsibilityArea, isNull,
        reason: 'clearing the card must clear the area too');
  });

  test('buildTaskFromForm drops a blank area and trims a real one', () {
    final blank = buildTaskFromForm(companyId: 'c', name: 'n',
        timesSource: 'manual', minutesSource: 'manual',
        roleScorecardId: 'rs1', responsibilityArea: '   ');
    expect(blank.responsibilityArea, isNull);

    final padded = buildTaskFromForm(companyId: 'c', name: 'n',
        timesSource: 'manual', minutesSource: 'manual',
        roleScorecardId: 'rs1', responsibilityArea: '  Area  ');
    expect(padded.responsibilityArea, 'Area');
  });

  testWidgets('dialog shows the name-required error on empty Save', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showDialog<WpTask>(
            context: context,
            builder: (_) => const TaskFormDialog(
                companyId: 'c', nodes: [], drivers: [], rates: [], employees: []),
          ),
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Name is required.'), findsOneWidget);
  });
}
