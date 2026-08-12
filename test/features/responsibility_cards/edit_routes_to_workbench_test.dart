import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/responsibility_cards/role_scorecard_detail_screen.dart';

import '../../support/supabase_stub.dart';

RoleScorecard _card() => RoleScorecard(
  id: 'card-1',
  companyId: 'co-1',
  jobTitle: 'Kiosk Sales Representative',
  missionStatement: 'Sell through the kiosk.',
  responsibilities: const [],
  kpis: const [],
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

  testWidgets('the card view sends Edit to the workbench, not the old editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final pushed = <String>[];
    final router = GoRouter(
      initialLocation: '/responsibility-cards/card-1',
      routes: [
        GoRoute(
          path: '/responsibility-cards/:id',
          builder: (c, s) =>
              RoleScorecardDetailScreen(cardId: s.pathParameters['id']!),
        ),
        // Catch every destination the button could reach, so a push to the
        // retired /edit route fails loudly here rather than silently 404ing.
        GoRoute(
          path: '/workforce-planning/roles/:id',
          builder: (c, s) {
            pushed.add('/workforce-planning/roles/${s.pathParameters['id']}');
            return const Scaffold(body: Text('workbench'));
          },
        ),
        GoRoute(
          path: '/responsibility-cards/:id/edit',
          builder: (c, s) {
            pushed.add('/responsibility-cards/${s.pathParameters['id']}/edit');
            return const Scaffold(body: Text('old editor'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The screen reads the list provider (filtering by cardId), not
          // roleScorecardByIdProvider — this is what actually feeds the body.
          roleScorecardListProvider.overrideWith((ref) async => [_card()]),
          // The Edit action is gated on isHrOrAdmin; without this override
          // userProfileProvider resolves null (no session) and the button
          // never renders, failing the test for the wrong reason.
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(
              userId: 'u1',
              email: 'hr@example.com',
              companyId: 'co-1',
              employeeId: null,
              appRole: AppRole.HR_ADMIN,
              mustChangePassword: false,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final edit = find.textContaining('Edit');
    expect(edit, findsWidgets, reason: 'the card view should offer an edit affordance');
    await tester.tap(edit.first);
    await tester.pumpAndSettle();

    expect(pushed, ['/workforce-planning/roles/card-1']);
  });
}
