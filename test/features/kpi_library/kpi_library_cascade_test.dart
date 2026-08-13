import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_form_dialog.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_library_screen.dart';

/// Task 6: the KPI Library speaks the cascade.
///
/// Three things this suite exists to prove, none of which any other suite
/// covers:
///  * the level filter actually narrows the list, and "all" restores it;
///  * the parent picker refuses a same-level pick using `kpiParentError`'s
///    own message (Task 2), not a home-grown one, and refuses to save while
///    that message stands;
///  * `KpiFormDialog._save()` reconstructs an EDITED Kpi with its level,
///    parent, roll-up type, data method and default target intact — the
///    landmine flagged two tasks ago: the dialog used to drop all six on
///    reconstruction, harmless only because `saveLibraryKpi`'s save map never
///    wrote them either. Now that both sides carry them, a dropped field
///    would be silently written back as a reset, not merely absent.
///  * `departmentId` — the seventh field the same reconstruction used to
///    drop, deferred out of Task 6 as harmless because `saveLibraryKpi` never
///    writes `department_id` either — now survives too. Threaded, not
///    collected: this dialog has no department control, so the only way to
///    prove it survives is to pop the dialog directly and read the value off
///    the returned [Kpi], never through `saveLibraryKpi`'s recorded call.
Kpi _kpi(
  String id,
  String name, {
  String level = 'PERSONAL',
  String? parentKpiId,
  String rollupType = 'INDEPENDENT',
  String dataMethod = 'MANUAL_PERIODIC',
  String? targetDirection,
  num? targetValue,
}) => Kpi(
  id: id,
  companyId: 'co-1',
  name: name,
  level: level,
  parentKpiId: parentKpiId,
  rollupType: rollupType,
  dataMethod: dataMethod,
  targetDirection: targetDirection,
  targetValue: targetValue,
);

class _RecordedSave {
  final String? id;
  final String name;
  final String level;
  final String? parentKpiId;
  final String rollupType;
  final String dataMethod;
  final String? targetDirection;
  final num? targetValue;
  final bool writeCascade;
  _RecordedSave({
    required this.id,
    required this.name,
    required this.level,
    required this.parentKpiId,
    required this.rollupType,
    required this.dataMethod,
    required this.targetDirection,
    required this.targetValue,
    required this.writeCascade,
  });
}

/// Same `implements ... with noSuchMethod` shape as
/// `kpi_library_save_wiring_test.dart`'s `_RecordingRepo` — this test's job
/// is proving the Dart call `_openForm` assembles is correct, not re-proving
/// the JSON key mapping `role_scorecard_kpi_links_test.dart` already covers
/// at the repository level.
class _RecordingRepo implements RoleScorecardRepository {
  final saves = <_RecordedSave>[];

  @override
  Future<Kpi> saveLibraryKpi({
    String? id,
    required String companyId,
    required String name,
    String? category,
    String? description,
    String? measurementUnit,
    String valueType = 'COUNT',
    String? numeratorLabel,
    String? numeratorSource,
    String? denominatorLabel,
    String? denominatorSource,
    String? unit,
    String cadence = 'WEEKLY',
    String? proofType,
    bool writeDefinition = false,
    String level = 'PERSONAL',
    String? parentKpiId,
    String rollupType = 'INDEPENDENT',
    String dataMethod = 'MANUAL_PERIODIC',
    String? targetDirection,
    num? targetValue,
    bool writeCascade = false,
  }) async {
    saves.add(
      _RecordedSave(
        id: id,
        name: name,
        level: level,
        parentKpiId: parentKpiId,
        rollupType: rollupType,
        dataMethod: dataMethod,
        targetDirection: targetDirection,
        targetValue: targetValue,
        writeCascade: writeCascade,
      ),
    );
    return Kpi(id: id ?? 'new-kpi', companyId: companyId, name: name);
  }

  @override
  Future<List<String>> distinctKpiSources() async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _hrProfile = UserProfile(
  userId: 'u1',
  email: 'hr@example.com',
  companyId: 'co-1',
  employeeId: null,
  appRole: AppRole.HR_ADMIN,
  mustChangePassword: false,
);

void main() {
  testWidgets('the level filter narrows the list, and "all" restores it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kpiLibraryProvider.overrideWith(
            (ref) async => [
              _kpi('p', 'Personal Metric', level: 'PERSONAL'),
              _kpi('d', 'Department Metric', level: 'DEPARTMENT'),
              _kpi('c', 'Company Metric', level: 'COMPANY'),
            ],
          ),
        ],
        child: const MaterialApp(home: KpiLibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal Metric'), findsOneWidget);
    expect(find.text('Department Metric'), findsOneWidget);
    expect(find.text('Company Metric'), findsOneWidget);

    await tester.tap(find.text('All levels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DEPARTMENT').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Department Metric'),
      findsOneWidget,
      reason: 'the matching level must still show',
    );
    expect(find.text('Personal Metric'), findsNothing);
    expect(find.text('Company Metric'), findsNothing);

    // Reopen — the closed button now shows the selected level, not the hint.
    await tester.tap(find.text('DEPARTMENT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All levels').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Personal Metric'),
      findsOneWidget,
      reason: '"All levels" must restore every row',
    );
    expect(find.text('Department Metric'), findsOneWidget);
    expect(find.text('Company Metric'), findsOneWidget);
  });

  testWidgets(
    'choosing a same-level parent surfaces kpiParentError\'s own message '
    'and leaves the form unsaved',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _RecordingRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScorecardRepositoryProvider.overrideWithValue(repo),
            kpiLibraryProvider.overrideWith(
              (ref) async => [
                _kpi('a', 'Alpha Metric', level: 'DEPARTMENT'),
                _kpi('b', 'Beta Metric', level: 'DEPARTMENT'),
              ],
            ),
            kpiAssignedEmployeesProvider.overrideWith(
              (ref) async => const <String, List<KpiAssignee>>{},
            ),
            userProfileProvider.overrideWith((ref) async => _hrProfile),
          ],
          child: const MaterialApp(home: KpiLibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Both rows sort alphabetically under Uncategorized/No department, so
      // Beta's edit button is the second (last) one in the list.
      await tester.tap(find.byTooltip('Edit').last);
      await tester.pumpAndSettle();
      expect(find.text('Edit KPI'), findsOneWidget);

      await tester.tap(find.byType(DropdownMenu<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha Metric (DEPARTMENT)').last);
      await tester.pumpAndSettle();

      expect(
        find.text('A KPI can only serve a higher level.'),
        findsOneWidget,
        reason: "kpiParentError's own wording, not a dialog-local rewrite",
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        repo.saves,
        isEmpty,
        reason: 'a refused parent must never reach saveLibraryKpi',
      );
      expect(
        find.text('Edit KPI'),
        findsOneWidget,
        reason: 'the dialog must still be open',
      );
    },
  );

  testWidgets(
    'editing only the name still round-trips level, parent, roll-up type, '
    'data method and default target through saveLibraryKpi',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _RecordingRepo();
      final parent = _kpi('parent-1', 'Company Parent', level: 'COMPANY');
      final existing = _kpi(
        'kpi-1',
        'Return Rate',
        level: 'DEPARTMENT',
        parentKpiId: 'parent-1',
        rollupType: 'SHARED',
        dataMethod: 'AUTOMATIC',
        targetDirection: 'HIGHER',
        targetValue: 42,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScorecardRepositoryProvider.overrideWithValue(repo),
            kpiLibraryProvider.overrideWith(
              (ref) async => [parent, existing],
            ),
            kpiAssignedEmployeesProvider.overrideWith(
              (ref) async => const <String, List<KpiAssignee>>{},
            ),
            userProfileProvider.overrideWith((ref) async => _hrProfile),
          ],
          child: const MaterialApp(home: KpiLibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // "Company Parent" < "Return Rate" alphabetically, so Return Rate's
      // edit button is the second (last) one.
      await tester.tap(find.byTooltip('Edit').last);
      await tester.pumpAndSettle();
      expect(find.text('Edit KPI'), findsOneWidget);

      await tester.enterText(
        find.ancestor(
          of: find.text('Name'),
          matching: find.byType(TextField),
        ),
        'Return Rate v2',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repo.saves, hasLength(1));
      final saved = repo.saves.single;
      expect(saved.id, 'kpi-1');
      expect(saved.name, 'Return Rate v2');
      expect(
        saved.level,
        'DEPARTMENT',
        reason: 'level must survive an edit that never touched it',
      );
      expect(saved.parentKpiId, 'parent-1');
      expect(saved.rollupType, 'SHARED');
      expect(saved.dataMethod, 'AUTOMATIC');
      expect(saved.targetDirection, 'HIGHER');
      expect(saved.targetValue, 42);
      expect(
        saved.writeCascade,
        isTrue,
        reason:
            'the dialog now collects the cascade fields, so the library '
            'screen must ask saveLibraryKpi to write them',
      );
    },
  );

  testWidgets(
    'editing only the name still round-trips departmentId in the Kpi the '
    'dialog pops, even though no control on the form ever shows it',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _RecordingRepo();
      final existing = Kpi(
        id: 'kpi-dept',
        companyId: 'co-1',
        name: 'Fill Rate',
        departmentId: 'dept-1',
      );

      Kpi? popped;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScorecardRepositoryProvider.overrideWithValue(repo),
            kpiLibraryProvider.overrideWith((ref) async => [existing]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<Kpi>(
                      context: context,
                      builder: (_) => KpiFormDialog(existing: existing),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit KPI'), findsOneWidget);

      await tester.enterText(
        find.ancestor(
          of: find.text('Name'),
          matching: find.byType(TextField),
        ),
        'Fill Rate v2',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Asserts the VALUE, not key presence — a Kpi built with the buggy
      // reconstruction still carries a `departmentId` key, just defaulted to
      // null. Only checking the value catches that.
      expect(
        popped?.departmentId,
        'dept-1',
        reason: 'departmentId must survive an edit that never touched it',
      );
    },
  );
}
