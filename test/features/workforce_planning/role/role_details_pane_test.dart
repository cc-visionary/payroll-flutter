import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/role/role_details_pane.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../support/supabase_stub.dart';

class _CapturingRepository extends RoleScorecardRepository {
  _CapturingRepository() : super(Supabase.instance.client);

  RoleScorecard? saved;

  @override
  Future<RoleScorecard> upsert(RoleScorecard card) async => saved = card;
}

RoleScorecard _card({
  String? departmentId,
  String? hiringEntityId,
  String? shiftTemplateId,
}) => RoleScorecard(
  id: 'card-1',
  departmentId: departmentId,
  hiringEntityId: hiringEntityId,
  shiftTemplateId: shiftTemplateId,
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

  Future<void> pump(
    WidgetTester tester, {
    RoleScorecard? card,
    _CapturingRepository? repo,
  }) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (repo != null)
            roleScorecardRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoleDetailsPane(card: card ?? _card()),
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

  testWidgets('base salary is read-only; it changes only through the '
      'effective-dated Update base rate action', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Role details'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      fieldsLabelled('Base salary').first,
    );
    expect(field.enabled, isFalse);
    expect(find.textContaining('own pay keep it'), findsOneWidget);
    expect(find.text('Update base rate'), findsOneWidget);
  });

  testWidgets('starts collapsed so the panes below are reachable', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Role details'), findsOneWidget);
    expect(fieldsLabelled('Skill name'), findsNothing);
  });

  testWidgets(
    'a dangling department/brand id is saved as it is shown — cleared, not '
    'silently written back',
    (tester) async {
      // _present hides an id that is not among the loaded items, so a card
      // pointing at a since-deleted department renders "(none)". _save read
      // the raw field, so the pane showed one thing and persisted another and
      // the stale link could never be cleared from here. (The stub answers
      // every query with [], so both dropdown lists are LOADED and empty —
      // which is exactly the dangling case.)
      final repo = _CapturingRepository();
      await pump(
        tester,
        card: _card(departmentId: 'gone-dept', hiringEntityId: 'gone-brand'),
        repo: repo,
      );
      await tester.tap(find.text('Role details'));
      await tester.pumpAndSettle();

      expect(
        find.text('(none)'),
        findsNWidgets(2),
        reason: 'both dropdowns display (none) for an id they cannot resolve',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.saved, isNotNull);
      expect(repo.saved!.departmentId, isNull);
      expect(repo.saved!.hiringEntityId, isNull);
    },
  );

  testWidgets('a resolvable department id survives a save', (tester) async {
    // The other half: only an id the dropdown could not show may be dropped.
    // Guarding this stops the fix above from degenerating into "always clear".
    final repo = _CapturingRepository();
    await pump(tester, card: _card(), repo: repo);
    await tester.tap(find.text('Role details'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.saved, isNotNull);
    expect(repo.saved!.jobTitle, 'Kiosk Sales Representative');
  });

  testWidgets(
    'an ordinary save carries a field the pane cannot edit forward unchanged',
    (tester) async {
      // The pane has no control for shift_template_id. _save() reconstructs
      // the card field-by-field, so any field it forgets to carry forward
      // silently reverts to the constructor's null default on every save.
      // That has genuinely happened here before, to a different field, and
      // the model test cannot catch it: fromRow/toUpsertPayload round-trip
      // correctly in isolation while the CALLER drops the value.
      final repo = _CapturingRepository();
      await pump(
        tester,
        card: _card(shiftTemplateId: 'shift-1'),
        repo: repo,
      );
      await tester.tap(find.text('Role details'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.saved, isNotNull);
      expect(repo.saved!.shiftTemplateId, 'shift-1');
    },
  );
}
