import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:payroll_flutter/features/workforce_planning/role/role_workbench_screen.dart';

import '../../../support/supabase_stub.dart';

RoleScorecard _card() => RoleScorecard(
  id: 'card-1',
  companyId: 'co-1',
  jobTitle: 'Technical Product & Purchasing Specialist',
  missionStatement: 'Build a predictable wholesale revenue engine.',
  responsibilities: const [],
  kpis: const [],
  requiredSkills: const [],
  behavioralExpectations: const [],
  version: 2,
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

  Future<void> pump(WidgetTester tester, {RoleScorecard? card}) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleScorecardByIdProvider(
            'card-1',
          ).overrideWith((ref) async => card),
        ],
        child: const MaterialApp(
          home: RoleWorkbenchScreen(cardId: 'card-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the role title and version in the header', (tester) async {
    await pump(tester, card: _card());
    expect(
      find.text('Technical Product & Purchasing Specialist'),
      findsOneWidget,
    );
    expect(find.textContaining('Version 2'), findsOneWidget);
  });

  testWidgets('says so plainly when the card is missing', (tester) async {
    await pump(tester, card: null);
    expect(find.textContaining('not found'), findsOneWidget);
    // Never a bare spinner forever, and never an empty scaffold that reads as
    // a role with nothing in it.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
