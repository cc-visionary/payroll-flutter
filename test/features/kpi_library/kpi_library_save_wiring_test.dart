import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_library_screen.dart';

/// Covers the wiring `flutter test`'s other KPI-library suites do not touch:
/// `KpiFormDialog._save()` mapping the [KpiDefinitionForm]'s draft onto the
/// [Kpi] it returns, and `KpiLibraryScreen._openForm` forwarding those eight
/// fields plus `writeDefinition: true` into `saveLibraryKpi`. Both the form's
/// own test (`kpi_definition_form_test.dart`) and the repository's own test
/// (`role_scorecard_kpi_links_test.dart`) exercise their half of this in
/// isolation; neither would catch `_openForm` dropping a field or losing
/// `writeDefinition: true` on a future edit.
///
/// A hand-written fake implementing [RoleScorecardRepository] (the same
/// `implements ... with noSuchMethod` shape already used by
/// `unassigned_tab_test.dart`) records the exact call `_openForm` makes,
/// rather than a mock HTTP transport — this test's job is proving the Dart
/// call is assembled correctly, not re-proving the JSON key mapping the
/// repository-level tests already cover.
class _RecordedSave {
  final String? id;
  final String companyId;
  final String name;
  final String valueType;
  final String? numeratorLabel;
  final String? numeratorSource;
  final String? denominatorLabel;
  final String? denominatorSource;
  final String? unit;
  final String cadence;
  final String? proofType;
  final bool writeDefinition;
  _RecordedSave({
    required this.id,
    required this.companyId,
    required this.name,
    required this.valueType,
    required this.numeratorLabel,
    required this.numeratorSource,
    required this.denominatorLabel,
    required this.denominatorSource,
    required this.unit,
    required this.cadence,
    required this.proofType,
    required this.writeDefinition,
  });
}

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
  }) async {
    saves.add(
      _RecordedSave(
        id: id,
        companyId: companyId,
        name: name,
        valueType: valueType,
        numeratorLabel: numeratorLabel,
        numeratorSource: numeratorSource,
        denominatorLabel: denominatorLabel,
        denominatorSource: denominatorSource,
        unit: unit,
        cadence: cadence,
        proofType: proofType,
        writeDefinition: writeDefinition,
      ),
    );
    return Kpi(id: 'new-kpi', companyId: companyId, name: name);
  }

  @override
  Future<List<String>> distinctKpiSources() async => const [
    'BigSeller',
    'Lark',
  ];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'New KPI dialog: a free-text source and writeDefinition: true both '
    'survive from the form to the saveLibraryKpi call',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _RecordingRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleScorecardRepositoryProvider.overrideWithValue(repo),
            kpiLibraryProvider.overrideWith((ref) async => const <Kpi>[]),
            kpiAssignedEmployeesProvider.overrideWith(
              (ref) async => const <String, List<KpiAssignee>>{},
            ),
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
          child: const MaterialApp(home: KpiLibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'New KPI'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.ancestor(
          of: find.text('Name'),
          matching: find.byType(TextField),
        ),
        'Return Rate',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('What is counted'),
          matching: find.byType(TextFormField),
        ),
        'Returns',
      );
      // The suggestion list only knows BigSeller and Lark — this is the
      // free-text case the autocomplete exists for.
      await tester.enterText(
        find.ancestor(
          of: find.text('Source'),
          matching: find.byType(TextFormField),
        ),
        'Temu',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        repo.saves,
        hasLength(1),
        reason: 'expected exactly one saveLibraryKpi call from Save',
      );
      final saved = repo.saves.single;
      expect(saved.companyId, 'co-1');
      expect(saved.name, 'Return Rate');
      expect(saved.numeratorLabel, 'Returns');
      expect(
        saved.numeratorSource,
        'Temu',
        reason:
            'a source outside the suggestion list must still reach '
            'saveLibraryKpi untouched',
      );
      expect(saved.valueType, 'COUNT');
      expect(saved.cadence, 'WEEKLY');
      expect(
        saved.writeDefinition,
        isTrue,
        reason:
            'the dialog now collects the definition fields, so the library '
            'screen must finally ask saveLibraryKpi to write them',
      );
    },
  );
}
