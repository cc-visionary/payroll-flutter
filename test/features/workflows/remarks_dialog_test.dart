import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workflows/remarks_dialog.dart';

/// Pumps a button that opens the dialog and records what it returned.
Future<void> _open(
  WidgetTester tester, {
  required bool requireNonEmpty,
  required void Function(String?) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              onResult(
                await showRemarksDialog(
                  context,
                  'Cancel this workflow?',
                  'Cancellation reason (required)',
                  requireNonEmpty: requireNonEmpty,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FilledButton _confirm(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'));

void main() {
  testWidgets('required reason: Confirm is disabled until text is entered', (
    tester,
  ) async {
    String? result;
    var returned = false;
    await _open(
      tester,
      requireNonEmpty: true,
      onResult: (r) {
        result = r;
        returned = true;
      },
    );

    // The regression: Confirm used to be tappable with an empty reason and
    // silently do nothing, so cancelling a workflow appeared broken.
    expect(_confirm(tester).onPressed, isNull);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(returned, isFalse, reason: 'dialog must stay open');
    expect(find.text('Cancel this workflow?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Recorded in error');
    await tester.pump();
    expect(_confirm(tester).onPressed, isNotNull);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result, 'Recorded in error');
  });

  testWidgets('required reason: whitespace alone does not enable Confirm', (
    tester,
  ) async {
    await _open(tester, requireNonEmpty: true, onResult: (_) {});
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(_confirm(tester).onPressed, isNull);
  });

  testWidgets('optional reason: Confirm is enabled while empty', (
    tester,
  ) async {
    String? result;
    await _open(tester, requireNonEmpty: false, onResult: (r) => result = r);
    expect(_confirm(tester).onPressed, isNotNull);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result, '');
  });

  testWidgets('dismissing returns null, not an empty string', (tester) async {
    String? result = 'sentinel';
    await _open(tester, requireNonEmpty: true, onResult: (r) => result = r);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
