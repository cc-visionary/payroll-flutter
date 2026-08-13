import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/department.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/repositories/department_repository.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_form_dialog.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_library_screen.dart';

/// Task 6: the KPI Library speaks the cascade.
///
/// Four things this suite exists to prove, none of which any other suite
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
///  * `departmentId` — the final fix wave's own defect. This dialog used to
///    have no department control at all (`department_id` stayed null for
///    EVERY KPI created or edited in-app, silently producing zero
///    DEPARTMENT rows), and even the round-trip-on-an-untouched-edit
///    behaviour only worked by accident because `saveLibraryKpi` never wrote
///    the column either. Both halves are exercised below: picking a
///    department through the new dropdown and having it reach
///    `saveLibraryKpi`, and an edit that never touches the picker still
///    round-tripping whatever department was already set.
Kpi _kpi(
  String id,
  String name, {
  String level = 'PERSONAL',
  String? parentKpiId,
  String rollupType = 'INDEPENDENT',
  String dataMethod = 'MANUAL_PERIODIC',
  String? targetDirection,
  num? targetValue,
  String? departmentId,
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
  departmentId: departmentId,
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
  final String? departmentId;
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
    required this.departmentId,
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
    String? departmentId,
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
        departmentId: departmentId,
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
    'data method, default target and department through saveLibraryKpi',
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
        departmentId: 'dept-1',
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
            departmentListProvider.overrideWith(
              (ref) async => const [
                Department(
                  id: 'dept-1',
                  companyId: 'co-1',
                  code: 'OPS',
                  name: 'Operations',
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: KpiLibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The library groups by department first, "No department" last
      // (kpi_rows.dart's groupKpisByDepartment) -- "Return Rate" now has
      // dept-1/Operations and "Company Parent" has none, so Return Rate's
      // group renders first and its edit button is the first (not last) one.
      await tester.tap(find.byTooltip('Edit').first);
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
        saved.departmentId,
        'dept-1',
        reason: 'department must survive an edit that never touched it',
      );
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
    'picking a department in the Cascade section reaches saveLibraryKpi -- '
    'the actual defect: a KPI created or edited in-app could never set '
    'department_id at all, because no control ever collected it',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _RecordingRepo();
      final existing = _kpi(
        'kpi-dept',
        'Fill Rate',
        level: 'DEPARTMENT',
        rollupType: 'DIRECT',
        // Starts with no department -- exactly the shape that used to
        // resolve to zero DEPARTMENT rows in compute_kpi_results.dart no
        // matter what anyone did in this dialog.
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScorecardRepositoryProvider.overrideWithValue(repo),
            kpiLibraryProvider.overrideWith((ref) async => [existing]),
            kpiAssignedEmployeesProvider.overrideWith(
              (ref) async => const <String, List<KpiAssignee>>{},
            ),
            userProfileProvider.overrideWith((ref) async => _hrProfile),
            departmentListProvider.overrideWith(
              (ref) async => const [
                Department(
                  id: 'dept-1',
                  companyId: 'co-1',
                  code: 'OPS',
                  name: 'Operations',
                ),
                Department(
                  id: 'dept-2',
                  companyId: 'co-1',
                  code: 'SLS',
                  name: 'Sales',
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: KpiLibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit KPI'), findsOneWidget);

      // The closed dropdown currently shows its "no department" state --
      // unique text among this dialog's dropdowns, so this also locates the
      // Department field without depending on widget order.
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<String?>,
          'No department (company-wide)',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OPS — Operations').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repo.saves, hasLength(1));
      expect(
        repo.saves.single.departmentId,
        'dept-1',
        reason:
            'the dialog must actually collect a department choice and hand '
            'it to saveLibraryKpi -- previously no such control existed',
      );
    },
  );

  testWidgets(
    'editing only the name still round-trips departmentId when the picker '
    'is never touched',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _RecordingRepo();
      final existing = Kpi(
        id: 'kpi-dept-2',
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
            departmentListProvider.overrideWith(
              (ref) async => const [
                Department(
                  id: 'dept-1',
                  companyId: 'co-1',
                  code: 'OPS',
                  name: 'Operations',
                ),
              ],
            ),
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
