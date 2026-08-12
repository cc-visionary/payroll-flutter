import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/workforce_planning/role/new_role_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../support/supabase_stub.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  /// Pumps a host whose only job is to open the dialog under test.
  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showNewRoleDialog(context, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('refuses to create a role with no job title', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Still open, with a complaint — never a card with a blank title.
    expect(find.text('Create'), findsOneWidget);
    expect(find.textContaining('title'), findsWidgets);
  });

  testWidgets('refuses to create a role with no mission', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextFormField).first, 'Kiosk Rep');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Create'), findsOneWidget);
    expect(find.textContaining('ission'), findsWidgets);
  });

  testWidgets(
    'shows a visible complaint and stays open when the profile has not '
    'loaded yet, instead of silently doing nothing',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // A Future that never completes — userProfileProvider stays
            // AsyncLoading for the whole test. This is reachable in the real
            // app: the /workforce-planning router guard's every check is
            // nested inside `if (profile != null)` (router.dart:85-114), so
            // an unresolved profile is free passage to this screen, not a
            // barrier — a slow network right after login, or a deep link
            // straight into /workforce-planning/roles/:id, lands here before
            // the profile has resolved. Deliberately NOT warmed, unlike the
            // defaults test below.
            userProfileProvider.overrideWith(
              (ref) => Completer<UserProfile?>().future,
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => showNewRoleDialog(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Kiosk Rep',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Sell through the kiosk.',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Still open — no card was silently skipped — with a complaint the
      // manager can act on, not nothing.
      expect(find.text('Create'), findsOneWidget);
      expect(find.textContaining('profile'), findsWidgets);
    },
  );

  testWidgets(
    'creates a role carrying the old editor\'s new-card defaults',
    (tester) async {
      // A recording MockClient over a second, independent SupabaseClient —
      // same technique as role_scorecard_kpi_links_test.dart — stands in for
      // roleScorecardRepositoryProvider so the dialog's actual upsert() can
      // be exercised and inspected.
      Map<String, dynamic>? insertedBody;
      final mock = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/role_scorecards')) {
          // The id-existence check inside upsert(): no row yet -> insert path.
          return http.Response('[]', 200, request: request);
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/role_scorecards')) {
          insertedBody = jsonDecode(request.body) as Map<String, dynamic>;
          // .select().single() expects a single JSON object back, not a list.
          return http.Response(
            jsonEncode(insertedBody),
            201,
            request: request,
          );
        }
        return http.Response('[]', 200, request: request);
      });
      final client = SupabaseClient(
        'https://stub.supabase.co',
        'stub-anon-key',
        httpClient: mock,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = RoleScorecardRepository(client);

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? createdId;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScorecardRepositoryProvider.overrideWithValue(repo),
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
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                // Warms up userProfileProvider before the dialog needs it.
                // In the real app it is already resolved well before a
                // manager reaches this tab — the router's own redirect
                // guard on /workforce-planning reads it first — but nothing
                // else in this narrow widget tree touches it, so without
                // this watch the dialog's synchronous `.read()` would see
                // AsyncLoading and silently do nothing.
                ref.watch(userProfileProvider);
                return Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      createdId = await showNewRoleDialog(context, ref);
                    },
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Kiosk Sales Representative',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Sell through the kiosk.',
      );
      await tester.enterText(find.byType(TextFormField).at(2), '32500');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(createdId, isNotNull, reason: 'dialog should return the new id');
      expect(insertedBody, isNotNull);
      expect(insertedBody!['id'], createdId);
      expect(insertedBody!['company_id'], 'co-1');
      expect(insertedBody!['job_title'], 'Kiosk Sales Representative');
      expect(insertedBody!['mission_statement'], 'Sell through the kiosk.');
      expect(insertedBody!['wage_type'], 'MONTHLY');
      expect(insertedBody!['work_hours_per_day'], 8);
      expect(insertedBody!['work_days_per_week'], 'Monday to Saturday');
      expect(insertedBody!['is_active'], true);
      expect(
        insertedBody!['effective_date'],
        DateTime.now().toIso8601String().substring(0, 10),
      );
      // The ONLY surface that can set a role's base salary. Payroll falls
      // back to it for every holder with no compensation_changes row
      // (compute_service.dart), so a role created without it and staffed
      // before HR files a compensation record pays basic ₱0.
      expect(insertedBody!['base_salary'], '32500');
    },
  );

  testWidgets('leaving base salary blank saves a null, not a zero', (
    tester,
  ) async {
    Map<String, dynamic>? insertedBody;
    final mock = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/role_scorecards')) {
        return http.Response('[]', 200, request: request);
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/role_scorecards')) {
        insertedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(insertedBody), 201, request: request);
      }
      return http.Response('[]', 200, request: request);
    });
    final client = SupabaseClient(
      'https://stub.supabase.co',
      'stub-anon-key',
      httpClient: mock,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final repo = RoleScorecardRepository(client);

    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleScorecardRepositoryProvider.overrideWithValue(repo),
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
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(userProfileProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () => showNewRoleDialog(context, ref),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Kiosk Rep');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Sell through the kiosk.',
    );
    // Base salary deliberately untouched.
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(insertedBody, isNotNull, reason: 'the role should still save');
    // Null, never '0': a 0 here would read as "this role is unpaid" to the
    // Roles tab's Cost/mo column and to payroll's fallback, where an absent
    // value reads as "not set yet" and shows an em dash.
    expect(insertedBody!['base_salary'], isNull);
  });
}
