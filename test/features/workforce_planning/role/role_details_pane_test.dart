import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/workforce_planning/role/role_details_pane.dart';

import '../../../support/supabase_stub.dart';

RoleScorecard _card() => RoleScorecard(
  id: 'card-1',
  companyId: 'co-1',
  jobTitle: 'Kiosk Sales Representative',
  missionStatement: 'Sell through the kiosk.',
  responsibilities: const [],
  kpis: const [],
  requiredSkills: const [
    RequiredSkill(name: 'Product knowledge', description: 'Knows the range'),
    RequiredSkill(name: 'Cash handling', description: 'Accurate float'),
    RequiredSkill(name: 'Upselling', description: 'Suggests add-ons'),
  ],
  behavioralExpectations: const [],
  version: 1,
  wageType: 'DAILY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'Monday to Saturday',
  isActive: true,
  effectiveDate: DateTime(2025, 1, 1),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoleDetailsPane(card: _card()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fieldsLabelled(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );

  testWidgets('removing a skill drops that row, not the last one', (
    tester,
  ) async {
    // The card editor shipped this bug for months (fixed in 6ae6c9b): unkeyed
    // fields are matched positionally, so the surviving rows kept the text of
    // the rows before them and the LAST row appeared to vanish.
    await pump(tester);
    await tester.tap(find.text('Role details'));
    await tester.pumpAndSettle();

    expect(fieldsLabelled('Skill name'), findsNWidgets(3));
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.delete_outline).first,
    );
    await tester.pumpAndSettle();

    expect(fieldsLabelled('Skill name'), findsNWidgets(2));
    expect(find.text('Product knowledge'), findsNothing);
    expect(find.text('Cash handling'), findsOneWidget);
    expect(find.text('Upselling'), findsOneWidget);
  });

  testWidgets('base salary is read-only on an existing card', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Role details'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      fieldsLabelled('Base salary').first,
    );
    expect(field.enabled, isFalse);
    expect(find.textContaining('compensation'), findsOneWidget);
  });

  testWidgets('starts collapsed so the panes below are reachable', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Role details'), findsOneWidget);
    expect(fieldsLabelled('Skill name'), findsNothing);
  });
}
