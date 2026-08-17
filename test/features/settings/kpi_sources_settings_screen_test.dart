import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/kpi_source_config.dart';
import 'package:payroll_flutter/data/repositories/kpi_source_config_repository.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart'
    show kpiLibraryProvider;
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/settings/kpi_sources/kpi_sources_settings_screen.dart';
import 'package:payroll_flutter/widgets/pending_migration_notice.dart';

import '../../support/supabase_stub.dart';

Kpi _kpi({String id = 'kpi-1', String name = 'Order Accuracy'}) =>
    Kpi(id: id, companyId: 'c1', name: name);

KpiConnection _conn({
  String? id = 'conn-1',
  String name = 'Cashflow Postgres',
  bool isActive = true,
}) => KpiConnection(
  id: id,
  companyId: 'c1',
  name: name,
  kind: 'POSTGRES',
  host: 'db.cashflow.internal',
  port: 5432,
  database: 'cashflow',
  dbSchema: 'public',
  dbUser: 'ro_reader',
  credentialKind: 'ENV',
  credentialRef: 'CASHFLOW_DB_PASSWORD',
  isActive: isActive,
);

KpiSourceBinding _binding({
  String id = 'b-1',
  String kpiId = 'kpi-1',
  String connectionId = 'conn-1',
  String? denominatorColumn,
  bool isActive = true,
}) => KpiSourceBinding(
  id: id,
  companyId: 'c1',
  kpiId: kpiId,
  connectionId: connectionId,
  objectName: 'v_fulfilment',
  periodColumn: 'period',
  subjectColumn: 'staff_email',
  numeratorColumn: 'correct_orders',
  denominatorColumn: denominatorColumn,
  subjectKind: SubjectKind.employee,
  isActive: isActive,
);

UserProfile _profile() => const UserProfile(
  userId: 'u1',
  email: 'admin@luxium.test',
  companyId: 'c1',
  employeeId: null,
  appRole: AppRole.ADMIN,
  mustChangePassword: false,
);

/// Records every call this screen could make against the three config
/// tables -- [calls] is a flat, ordered log of method names so a test can
/// assert nothing OTHER than the expected narrow calls happened, not just
/// that the expected ones did.
class _FakeRepo implements KpiSourceConfigRepository {
  List<KpiConnection> connections = [];
  List<KpiSourceBinding> bindings = [];
  Map<String, List<KpiSubjectMap>> subjectMaps = {};

  final calls = <String>[];
  final upsertConnectionCalls = <KpiConnection>[];
  final upsertBindingCalls = <KpiSourceBinding>[];
  final deleteBindingCalls = <String>[];
  final numeratorSourceCalls = <({String kpiId, String? source})>[];
  final upsertSubjectMapCalls = <KpiSubjectMap>[];
  final deleteSubjectMapCalls = <String>[];

  @override
  Future<List<KpiConnection>> listConnections() async {
    calls.add('listConnections');
    return connections;
  }

  @override
  Future<void> upsertConnection(KpiConnection c) async {
    calls.add('upsertConnection');
    upsertConnectionCalls.add(c);
  }

  @override
  Future<List<KpiSourceBinding>> listBindings() async {
    calls.add('listBindings');
    return bindings;
  }

  @override
  Future<KpiSourceBinding?> bindingForKpi(String kpiId) async {
    calls.add('bindingForKpi');
    for (final b in bindings) {
      if (b.kpiId == kpiId && b.isActive) return b;
    }
    return null;
  }

  @override
  Future<void> upsertBinding(KpiSourceBinding b) async {
    calls.add('upsertBinding');
    upsertBindingCalls.add(b);
  }

  @override
  Future<void> deleteBinding(String id) async {
    calls.add('deleteBinding');
    deleteBindingCalls.add(id);
  }

  @override
  Future<List<KpiSubjectMap>> subjectMapFor(String connectionId) async {
    calls.add('subjectMapFor');
    return subjectMaps[connectionId] ?? const [];
  }

  @override
  Future<void> upsertSubjectMapping(KpiSubjectMap m) async {
    calls.add('upsertSubjectMapping');
    upsertSubjectMapCalls.add(m);
  }

  @override
  Future<void> deleteSubjectMapping(String id) async {
    calls.add('deleteSubjectMapping');
    deleteSubjectMapCalls.add(id);
  }

  @override
  Future<({int statusCode, dynamic body})> fetchSourceRows({
    required String bindingId,
    required String period,
  }) async {
    calls.add('fetchSourceRows');
    return (statusCode: 200, body: {'rows': <dynamic>[]});
  }

  @override
  Future<void> setKpiNumeratorSource(
    String kpiId,
    String? numeratorSource,
  ) async {
    calls.add('setKpiNumeratorSource');
    numeratorSourceCalls.add((kpiId: kpiId, source: numeratorSource));
  }
}

/// A repo whose reads fail exactly the way an unapplied migration fails --
/// PostgREST PGRST205, "the table isn't there yet".
class _PendingMigrationRepo extends _FakeRepo {
  @override
  Future<List<KpiConnection>> listConnections() async {
    calls.add('listConnections');
    throw PostgrestException(
      message:
          'Could not find the table \'public.kpi_connections\' in the '
          'schema cache',
      code: 'PGRST205',
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<_FakeRepo> pump(
    WidgetTester tester, {
    _FakeRepo? repo,
    List<KpiConnection> connections = const [],
    List<Kpi> kpis = const [],
    List<KpiSourceBinding> bindings = const [],
  }) async {
    final r = repo ?? (_FakeRepo()
      ..connections = connections
      ..bindings = bindings);
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kpiSourceConfigRepositoryProvider.overrideWithValue(r),
          kpiLibraryProvider.overrideWith((ref) async => kpis),
          userProfileProvider.overrideWith((ref) async => _profile()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: KpiSourcesSettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return r;
  }

  Future<void> fillValidRequiredBindingFields(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('bindingObjectName')),
      'v_fulfilment',
    );
    await tester.enterText(
      find.byKey(const Key('bindingPeriodColumn')),
      'period',
    );
    await tester.enterText(
      find.byKey(const Key('bindingSubjectColumn')),
      'staff_email',
    );
    await tester.enterText(
      find.byKey(const Key('bindingNumeratorColumn')),
      'correct_orders',
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the three sections render: connections, bindings, subject map', (
    tester,
  ) async {
    await pump(tester, connections: [_conn()], kpis: [_kpi()]);
    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Bindings'), findsOneWidget);
    expect(find.text('Subject Map'), findsOneWidget);
    // Fixture data actually rendered, not just the headers.
    expect(find.text('Cashflow Postgres'), findsWidgets);
    expect(find.text('Order Accuracy'), findsOneWidget);
  });

  testWidgets('an invalid identifier blocks save and says why', (
    tester,
  ) async {
    final repo = await pump(tester, connections: [_conn()], kpis: [_kpi()]);
    await tester.tap(find.byKey(const Key('bind-kpi-1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('bindingObjectName')),
      'orders; drop table employees',
    );
    await tester.enterText(
      find.byKey(const Key('bindingPeriodColumn')),
      'period',
    );
    await tester.enterText(
      find.byKey(const Key('bindingSubjectColumn')),
      'staff_email',
    );
    await tester.enterText(
      find.byKey(const Key('bindingNumeratorColumn')),
      'correct_orders',
    );
    await tester.pumpAndSettle();

    expect(
      find.text(kInvalidSourceIdentifierMessage),
      findsOneWidget,
      reason: 'the reason must be said inline, at the point of typing',
    );

    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('bindingSaveButton')),
    );
    expect(
      saveButton.onPressed,
      isNull,
      reason: 'Save must be refused while the identifier is invalid',
    );

    await tester.tap(
      find.byKey(const Key('bindingSaveButton')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.upsertBindingCalls, isEmpty);
  });

  testWidgets(
    'a binding with no denominator column saves null, not an empty string',
    (tester) async {
      final repo = await pump(tester, connections: [_conn()], kpis: [_kpi()]);
      await tester.tap(find.byKey(const Key('bind-kpi-1')));
      await tester.pumpAndSettle();

      await fillValidRequiredBindingFields(tester);
      // Denominator left blank -- a COUNT KPI has none.

      await tester.tap(find.byKey(const Key('bindingSaveButton')));
      await tester.pumpAndSettle();

      expect(repo.upsertBindingCalls, hasLength(1));
      expect(
        repo.upsertBindingCalls.single.denominatorColumn,
        isNull,
        reason: 'must be null, never the empty string the text field starts '
            'with',
      );
    },
  );

  testWidgets(
    'saving an active binding writes kpis.numerator_source as cfg:<kpiId>, '
    'and touches nothing else',
    (tester) async {
      final repo = await pump(
        tester,
        connections: [_conn()],
        kpis: [_kpi(id: 'kpi-1')],
      );
      await tester.tap(find.byKey(const Key('bind-kpi-1')));
      await tester.pumpAndSettle();
      await fillValidRequiredBindingFields(tester);

      await tester.tap(find.byKey(const Key('bindingSaveButton')));
      await tester.pumpAndSettle();

      expect(repo.numeratorSourceCalls, [
        (kpiId: 'kpi-1', source: 'cfg:kpi-1'),
      ]);
      expect(repo.upsertBindingCalls, hasLength(1));
      // Nothing OTHER than the binding row and the one narrow
      // numerator_source write happened. Nothing that could carry a KPI's
      // other definition fields (value_type, numerator_label,
      // denominator_source, unit, cadence, proof_type) exists on this fake
      // at all -- there is no broader method a binding save could reach
      // for, narrow or not.
      expect(repo.upsertConnectionCalls, isEmpty);
      expect(repo.deleteBindingCalls, isEmpty);
      expect(repo.upsertSubjectMapCalls, isEmpty);
      expect(repo.deleteSubjectMapCalls, isEmpty);
    },
  );

  testWidgets('unbinding deletes the binding and clears numerator_source', (
    tester,
  ) async {
    final repo = await pump(
      tester,
      connections: [_conn()],
      kpis: [_kpi(id: 'kpi-1')],
      bindings: [_binding(id: 'b-1', kpiId: 'kpi-1', connectionId: 'conn-1')],
    );

    await tester.tap(find.byKey(const Key('unbind-kpi-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unbind'));
    await tester.pumpAndSettle();

    expect(repo.deleteBindingCalls, ['b-1']);
    expect(repo.numeratorSourceCalls, [(kpiId: 'kpi-1', source: null)]);
  });

  testWidgets(
    'deactivating a binding on save also clears numerator_source',
    (tester) async {
      final repo = await pump(
        tester,
        connections: [_conn()],
        kpis: [_kpi(id: 'kpi-1')],
        bindings: [_binding(id: 'b-1', kpiId: 'kpi-1', connectionId: 'conn-1')],
      );

      await tester.tap(find.byKey(const Key('bind-kpi-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bindingActiveSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bindingSaveButton')));
      await tester.pumpAndSettle();

      expect(repo.numeratorSourceCalls, [(kpiId: 'kpi-1', source: null)]);
    },
  );

  testWidgets('a pending-migration error renders the notice, not a raw exception', (
    tester,
  ) async {
    await pump(tester, repo: _PendingMigrationRepo());
    expect(find.byType(PendingMigrationNotice), findsWidgets);
    expect(find.textContaining('is not set up yet'), findsWidgets);
  });
}
