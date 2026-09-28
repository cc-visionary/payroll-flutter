import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/employees/profile/widgets/new_hire_workflow_action.dart';

const _confirm = 'I made the checklist and sent it to the new hire';

void main() {
  late List<String>? result;
  late bool closed;

  Future<void> open(WidgetTester tester) async {
    result = null;
    closed = false;
    // The dialog is taller than the default 800x600 test surface.
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              result = await showNewHireDialog(c);
              closed = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  FilledButton start(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Start workflow'),
  );

  testWidgets('Start stays disabled until the Lark checklist is confirmed '
      'sent', (tester) async {
    await open(tester);
    expect(find.text('Open checklist template in Lark'), findsOneWidget);
    expect(start(tester).onPressed, isNull);

    await tester.tap(find.text(_confirm));
    await tester.pump();
    expect(start(tester).onPressed, isNotNull);
  });

  testWidgets('optional documents start unticked', (tester) async {
    await open(tester);
    final waiver = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Liability Waiver'),
    );
    expect(waiver.value, isFalse);

    await tester.tap(find.text(_confirm));
    await tester.pump();
    await tester.tap(find.text('Start workflow'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isEmpty);
  });

  testWidgets('a ticked optional document is returned', (tester) async {
    await open(tester);
    await tester.tap(find.text('Liability Waiver'));
    await tester.tap(find.text(_confirm));
    await tester.pump();
    await tester.tap(find.text('Start workflow'));
    await tester.pumpAndSettle();
    expect(result, ['LIABILITY_WAIVER']);
  });
}
