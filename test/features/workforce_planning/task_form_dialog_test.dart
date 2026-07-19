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
