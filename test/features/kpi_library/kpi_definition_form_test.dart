import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_definition_form.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    KpiDefinitionDraft? initial,
    List<String> sources = const ['BigSeller', 'Lark'],
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KpiDefinitionForm(
              initial: initial,
              knownSources: sources,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a COUNT hides the denominator fields', (tester) async {
    await pump(tester, initial: KpiDefinitionDraft(valueType: 'COUNT'));
    expect(find.text('Counted against'), findsNothing);
  });

  testWidgets('a RATIO reveals them', (tester) async {
    await pump(tester, initial: KpiDefinitionDraft(valueType: 'RATIO'));
    expect(find.text('Counted against'), findsOneWidget);
  });

  testWidgets('names what is still missing', (tester) async {
    await pump(tester, initial: KpiDefinitionDraft(valueType: 'COUNT'));
    expect(find.textContaining('unit'), findsWidgets);
    expect(find.textContaining('what is counted'), findsWidgets);
  });

  testWidgets('suggests sources already in use without forcing them', (
    tester,
  ) async {
    await pump(tester, initial: KpiDefinitionDraft(valueType: 'COUNT'));
    final source = find.ancestor(
      of: find.text('Source'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(source.first, 'Big');
    await tester.pumpAndSettle();
    expect(find.text('BigSeller'), findsWidgets);

    // Free text must still be accepted — a new channel should not need a
    // migration or a code change.
    await tester.enterText(source.first, 'Temu');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
