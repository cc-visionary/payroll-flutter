import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/responsibility_cards/role_scorecard_form_screen.dart';

import '../../support/supabase_stub.dart';

/// The editor's repeating rows (skills, behavioral expectations, KPIs) are
/// built from drafts held in State and rendered with `initialValue`. Flutter
/// matches unkeyed children positionally, so removing row i used to leave the
/// surviving fields showing the text of the rows that came BEFORE the removed
/// one — on screen it looked as though the LAST row had been deleted.

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    // Tall surface so the whole ListView is laid out — the rows under test sit
    // well below a default 800x600 viewport.
    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: RoleScorecardFormScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fieldsLabelled(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );

  Future<void> addThreeRows(
    WidgetTester tester, {
    required String addLabel,
    required String fieldLabel,
  }) async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text(addLabel));
      await tester.pumpAndSettle();
    }
    for (final (i, text) in ['first', 'second', 'third'].indexed) {
      await tester.enterText(fieldsLabelled(fieldLabel).at(i), text);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('removing a skill row drops that row, not the last one', (
    tester,
  ) async {
    await pumpEditor(tester);
    await addThreeRows(
      tester,
      addLabel: 'Add skill',
      fieldLabel: 'Skill name',
    );

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).at(0));
    await tester.pumpAndSettle();

    expect(fieldsLabelled('Skill name'), findsNWidgets(2));
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
  });

  testWidgets('removing an expectation row drops that row, not the last one', (
    tester,
  ) async {
    await pumpEditor(tester);
    await addThreeRows(
      tester,
      addLabel: 'Add expectation',
      fieldLabel: 'Expectation name',
    );

    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Behavioral expectations'),
              matching: find.byType(Card),
            ),
            matching: find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .at(0),
    );
    await tester.pumpAndSettle();

    expect(fieldsLabelled('Expectation name'), findsNWidgets(2));
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
  });

  testWidgets('removing a task row drops that row, not the last one', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Add area'));
    await tester.pumpAndSettle();
    await addThreeRows(tester, addLabel: 'Add task', fieldLabel: 'Task');

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close).at(0));
    await tester.pumpAndSettle();

    expect(fieldsLabelled('Task'), findsNWidgets(2));
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
  });

  testWidgets('removing a KPI row drops that row, not the last one', (
    tester,
  ) async {
    await pumpEditor(tester);
    await addThreeRows(tester, addLabel: 'Add KPI', fieldLabel: 'KPI name');

    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('KPIs'),
              matching: find.byType(Card),
            ),
            matching: find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .at(0),
    );
    await tester.pumpAndSettle();

    expect(fieldsLabelled('KPI name'), findsNWidgets(2));
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
  });
}
