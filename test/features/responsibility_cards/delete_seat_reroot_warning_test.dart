import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/responsibility_cards/responsibility_cards_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/supabase_stub.dart';

RoleScorecard _seat(String id, String title, {String? parentId}) =>
    RoleScorecard(
      id: id,
      companyId: 'c',
      jobTitle: title,
      missionStatement: '',
      responsibilities: const [],
      kpis: const [],
      wageType: 'DAILY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'MON_FRI',
      isActive: true,
      effectiveDate: DateTime(2026, 1, 1),
      parentId: parentId,
    );

/// Never touches the network — same shape as `_CapturingRepository` in
/// `accountability_chart_screen_test.dart`.
class _CapturingRepository extends RoleScorecardRepository {
  _CapturingRepository() : super(Supabase.instance.client);
  final deleted = <String>[];

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<RoleScorecard> seats,
    required RoleScorecardRepository repo,
  }) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleScorecardListProvider.overrideWith((ref) async => seats),
          scorecardEmployeeCountProvider.overrideWith((ref) async => const {}),
          roleScorecardRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(
              userId: 'u1',
              email: 'admin@example.com',
              companyId: 'c',
              employeeId: null,
              appRole: AppRole.SUPER_ADMIN,
              mustChangePassword: false,
            ),
          ),
        ],
        child: const MaterialApp(home: ResponsibilityCardsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'deleting a seat with children warns how many will move to the top level',
    (tester) async {
      final repo = _CapturingRepository();
      await pump(
        tester,
        seats: [
          _seat('root', 'Visionary'),
          _seat('child1', 'Sourcing', parentId: 'root'),
          _seat('child2', 'Sales', parentId: 'root'),
        ],
        repo: repo,
      );

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('2 seats'),
        findsOneWidget,
        reason:
            'the confirm dialog already has the full seat list in scope, '
            'so it can say how many children will re-root without a fetch',
      );
      expect(find.textContaining('top level'), findsOneWidget);
    },
  );

  testWidgets('deleting a childless seat shows no re-root warning', (
    tester,
  ) async {
    final repo = _CapturingRepository();
    await pump(tester, seats: [_seat('lonely', 'Marketing')], repo: repo);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('top level'), findsNothing);
  });
}
