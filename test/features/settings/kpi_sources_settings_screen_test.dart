import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:payroll_flutter/data/models/department.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/kpi_source_config.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/department_repository.dart';
import 'package:payroll_flutter/data/repositories/employee_repository.dart';
import 'package:payroll_flutter/data/repositories/kpi_source_config_repository.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart'
    show kpiLibraryProvider, roleScorecardListProvider;
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

Employee _employee({String id = 'e-1', String fullName = 'Alice Smith'}) {
  final parts = fullName.split(' ');
  return Employee(
    id: id,
    companyId: 'c1',
    employeeNumber: id,
    firstName: parts.first,
    lastName: parts.length > 1 ? parts.sublist(1).join(' ') : 'X',
    employmentType: 'FULL_TIME',
    employmentStatus: 'ACTIVE',
    hireDate: DateTime(2024, 1, 1),
    isRankAndFile: true,
    isOtEligible: false,
    isNdEligible: false,
    isHolidayPayEligible: false,
    sssEligibilityOverride: false,
    philhealthEligibilityOverride: false,
    pagibigEligibilityOverride: false,
    taxOnFullEarnings: false,
  );
}

Department _department({String id = 'd-1', String name = 'Operations'}) =>
    Department(id: id, companyId: 'c1', code: id, name: name);

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

  /// Overrides [fetchSourceRows]'s canned empty-rows answer -- Task 9's
  /// unmapped-keys probe needs to see specific rows come back from a
  /// specific binding, not the blanket `{'rows': []}` every other test in
  /// this file is happy with.
  Future<({int statusCode, dynamic body})> Function({
    required String bindingId,
    required String period,
  })?
  fetchSourceRowsImpl;

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
    // A REAL write, not just a logged call: the "mapping it makes it
    // disappear" test proves disappearance is a consequence of THIS write
    // -- the same fetcher keeps returning the same unmapped key on a
    // second check; only the subject map (read fresh by `subjectMapFor`
    // below) changes. A fake that only recorded the call, without this
    // list actually reflecting it, would let that test pass for the wrong
    // reason -- the tautology this repo's brief warns about.
    final existing = subjectMaps[m.connectionId] ?? const <KpiSubjectMap>[];
    subjectMaps[m.connectionId] = [
      for (final row in existing)
        if (row.externalKey != m.externalKey) row,
      m,
    ];
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
    final impl = fetchSourceRowsImpl;
    if (impl != null) return impl(bindingId: bindingId, period: period);
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

/// Simulates the second of the two sequential, non-transactional writes in
/// `_openBindingDialog`'s `onSave` failing AFTER the first ([upsertBinding])
/// has already gone through -- [upsertBindingCalls] (the real base-class
/// bookkeeping) still records the save, proving the binding row did
/// change, while [setKpiNumeratorSource] never gets there.
class _LinkFailsAfterBindingSavedRepo extends _FakeRepo {
  @override
  Future<void> setKpiNumeratorSource(
    String kpiId,
    String? numeratorSource,
  ) async {
    calls.add('setKpiNumeratorSource');
    numeratorSourceCalls.add((kpiId: kpiId, source: numeratorSource));
    throw PostgrestException(message: 'connection reset', code: '08006');
  }
}

/// Same shape as [_LinkFailsAfterBindingSavedRepo], for the unbind flow:
/// [deleteBinding] succeeds ([deleteBindingCalls] records it) but the
/// follow-up [setKpiNumeratorSource] clear fails.
class _UnlinkFailsAfterBindingDeletedRepo extends _FakeRepo {
  @override
  Future<void> setKpiNumeratorSource(
    String kpiId,
    String? numeratorSource,
  ) async {
    calls.add('setKpiNumeratorSource');
    numeratorSourceCalls.add((kpiId: kpiId, source: numeratorSource));
    throw PostgrestException(message: 'connection reset', code: '08006');
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
    List<Employee> employees = const [],
    List<Department> departments = const [],
    List<RoleScorecard> roles = const [],
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
          employeeListProvider.overrideWith((ref, query) async => employees),
          departmentListProvider.overrideWith((ref) async => departments),
          roleScorecardListProvider.overrideWith((ref) async => roles),
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

  testWidgets(
    'when the binding save succeeds but linking it to the KPI fails, the '
    'toast says the binding WAS saved -- not "Could not save"',
    (tester) async {
      final repo = await pump(
        tester,
        repo: _LinkFailsAfterBindingSavedRepo()..connections = [_conn()],
        kpis: [_kpi(id: 'kpi-1')],
      );
      await tester.tap(find.byKey(const Key('bind-kpi-1')));
      await tester.pumpAndSettle();
      await fillValidRequiredBindingFields(tester);

      await tester.tap(find.byKey(const Key('bindingSaveButton')));
      await tester.pumpAndSettle();

      // The binding write itself DID happen -- this is the fact the
      // message must not contradict.
      expect(repo.upsertBindingCalls, hasLength(1));
      expect(
        find.textContaining('Could not save the binding'),
        findsNothing,
        reason: 'the binding row did change; this message would be a lie',
      );
      expect(
        find.textContaining(kBindingSavedButLinkFailedMessage),
        findsOneWidget,
      );
      expect(
        find.textContaining('read as having no data'),
        findsOneWidget,
        reason: 'must say what the user should now expect, not just that '
            'something failed',
      );
    },
  );

  testWidgets(
    'when unbinding deletes the binding but clearing the KPI link fails, '
    'the toast says the binding WAS removed -- not "Could not unbind"',
    (tester) async {
      final repo = await pump(
        tester,
        repo: _UnlinkFailsAfterBindingDeletedRepo()
          ..connections = [_conn()]
          ..bindings = [_binding(id: 'b-1', kpiId: 'kpi-1', connectionId: 'conn-1')],
        kpis: [_kpi(id: 'kpi-1')],
      );

      await tester.tap(find.byKey(const Key('unbind-kpi-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Unbind'));
      await tester.pumpAndSettle();

      expect(repo.deleteBindingCalls, ['b-1']);
      expect(
        find.textContaining('Could not unbind'),
        findsNothing,
        reason: 'the binding row was already deleted; this message would '
            'be a lie',
      );
      expect(
        find.textContaining(kBindingRemovedButUnlinkFailedMessage),
        findsOneWidget,
      );
      expect(
        find.textContaining('read as having no data'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a pending-migration error renders the notice, not a raw exception', (
    tester,
  ) async {
    await pump(tester, repo: _PendingMigrationRepo());
    expect(find.byType(PendingMigrationNotice), findsWidgets);
    expect(find.textContaining('is not set up yet'), findsWidgets);
  });

  group('unmapped subjects (Task 9)', () {
    testWidgets(
      'a fetch returning an unknown key surfaces that key, and mapping it '
      'makes it disappear',
      (tester) async {
        final repo = _FakeRepo()
          ..connections = [_conn()]
          ..bindings = [_binding(id: 'b-1', kpiId: 'kpi-1', connectionId: 'conn-1')]
          ..fetchSourceRowsImpl = ({required bindingId, required period}) async => (
            statusCode: 200,
            body: {
              'rows': [
                {
                  'subject_key': 'unknown@x',
                  'numerator': 5,
                  'denominator': 5,
                },
              ],
            },
          );

        await pump(
          tester,
          repo: repo,
          kpis: [_kpi(id: 'kpi-1')],
          connections: [_conn()],
          bindings: repo.bindings,
          employees: [_employee(id: 'e-1', fullName: 'Alice Smith')],
        );

        await tester.tap(find.byKey(const Key('checkUnmapped-kpi-1')));
        await tester.pumpAndSettle();

        expect(
          find.text('unknown@x'),
          findsOneWidget,
          reason: 'the actual unmapped key must be surfaced, not just a count',
        );

        await tester.tap(find.byKey(const Key('mapUnresolved-unknown@x')));
        await tester.pumpAndSettle();

        // The external key is already known -- it came from the unmapped
        // list, not something the admin retypes.
        final keyField = tester.widget<TextField>(
          find.byKey(const Key('subjectMapExternalKey')),
        );
        expect(keyField.controller!.text, 'unknown@x');

        await tester.tap(find.byKey(const Key('subjectMapTarget')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alice Smith').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('subjectMapSaveButton')));
        await tester.pumpAndSettle();

        expect(repo.upsertSubjectMapCalls, hasLength(1));
        expect(repo.upsertSubjectMapCalls.single.externalKey, 'unknown@x');
        expect(repo.upsertSubjectMapCalls.single.employeeId, 'e-1');

        // Disappearance is a consequence of the write above, not a second
        // fixture: fetchSourceRowsImpl still returns the SAME row on this
        // re-check -- only the subject map (mutated by the fake's
        // upsertSubjectMapping) changed. Scoped to the still-open unmapped-
        // keys dialog: the underlying Subject Map section (still mounted
        // behind it) now legitimately shows 'unknown@x' too -- as a MAPPED
        // row, in its own table -- so a screen-wide text search would find
        // it there for the right reason and defeat this assertion.
        final dialogFinder = find.byType(AlertDialog).first;
        expect(
          find.descendant(of: dialogFinder, matching: find.text('unknown@x')),
          findsNothing,
          reason: 'mapping the key must make it disappear from THIS dialog, '
              'proven by re-reading the same fetch result through an '
              'updated subject map',
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.textContaining('No unmapped'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a blank key is reported distinctly and offers no mapping control', (
      tester,
    ) async {
      final repo = _FakeRepo()
        ..connections = [_conn()]
        ..bindings = [_binding(id: 'b-1', kpiId: 'kpi-1', connectionId: 'conn-1')]
        ..fetchSourceRowsImpl = ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              {'subject_key': '', 'numerator': 5, 'denominator': 5},
            ],
          },
        );

      await pump(
        tester,
        repo: repo,
        kpis: [_kpi(id: 'kpi-1')],
        connections: [_conn()],
        bindings: repo.bindings,
      );

      await tester.tap(find.byKey(const Key('checkUnmapped-kpi-1')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('blank'),
        findsOneWidget,
        reason: 'a blank key is a different problem (upstream in the '
            'source) and must be named as such',
      );
      expect(
        find.byKey(const Key('mapUnresolved-')),
        findsNothing,
        reason: 'a blank key cannot be mapped -- the DB forbids a blank '
            'external_key -- so no control may offer to try',
      );
    });

    testWidgets('a NONE-kind binding shows no unmapped-keys section', (tester) async {
      final noneBinding = KpiSourceBinding(
        id: 'b-1',
        companyId: 'c1',
        kpiId: 'kpi-1',
        connectionId: 'conn-1',
        objectName: 'v_company_fact',
        periodColumn: 'period',
        subjectColumn: 'ignored',
        numeratorColumn: 'total',
        subjectKind: SubjectKind.none,
      );
      await pump(
        tester,
        connections: [_conn()],
        kpis: [_kpi(id: 'kpi-1')],
        bindings: [noneBinding],
      );

      expect(
        find.byKey(const Key('checkUnmapped-kpi-1')),
        findsNothing,
        reason: 'a NONE-kind binding has no subject to map -- offering the '
            'section at all would be meaningless',
      );
    });

    testWidgets('a DEPARTMENT-kind binding offers a department picker, not an employee one', (
      tester,
    ) async {
      final deptBinding = KpiSourceBinding(
        id: 'b-1',
        companyId: 'c1',
        kpiId: 'kpi-1',
        connectionId: 'conn-1',
        objectName: 'v_dept_fact',
        periodColumn: 'period',
        subjectColumn: 'dept_code',
        numeratorColumn: 'total',
        subjectKind: SubjectKind.department,
      );
      final repo = _FakeRepo()
        ..connections = [_conn()]
        ..bindings = [deptBinding]
        ..fetchSourceRowsImpl = ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              {
                'subject_key': 'CC-UNKNOWN',
                'numerator': 5,
                'denominator': 5,
              },
            ],
          },
        );

      await pump(
        tester,
        repo: repo,
        kpis: [_kpi(id: 'kpi-1')],
        connections: [_conn()],
        bindings: repo.bindings,
        departments: [_department(id: 'd-1', name: 'Operations')],
        employees: [_employee(id: 'e-1', fullName: 'Alice Smith')],
      );

      await tester.tap(find.byKey(const Key('checkUnmapped-kpi-1')));
      await tester.pumpAndSettle();
      expect(find.text('CC-UNKNOWN'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mapUnresolved-CC-UNKNOWN')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('subjectMapKind')),
        findsNothing,
        reason: 'the binding is DEPARTMENT-kind -- there is no employee '
            'target to choose between, so the employee/department switch '
            'must not even render',
      );
      expect(
        find.text('Alice Smith'),
        findsNothing,
        reason: 'no employee picker for a DEPARTMENT-kind binding',
      );

      await tester.tap(find.byKey(const Key('subjectMapTarget')));
      await tester.pumpAndSettle();
      expect(
        find.text('Operations'),
        findsWidgets,
        reason: 'a department picker must be offered instead',
      );
    });
  });
}
