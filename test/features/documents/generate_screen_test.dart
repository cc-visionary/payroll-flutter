import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:payroll_flutter/core/pdf/pdf_preview_scaffold.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/employee_document_repository.dart';
import 'package:payroll_flutter/data/repositories/employee_repository.dart';
import 'package:payroll_flutter/data/repositories/hiring_entity_repository.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/documents/generate_screen.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records every [saveGenerated] call so the test can assert it was invoked
/// with the right arguments (or never invoked in applicant-mode). The
/// superclass needs a [SupabaseClient]; we pass a throwaway one that is never
/// used because [saveGenerated] is fully overridden.
class _FakeDocRepo extends EmployeeDocumentRepository {
  _FakeDocRepo({this.throwOnSave = false})
      : super(SupabaseClient(
          'https://stub.supabase.co',
          'stub-anon-key',
          // Prevent the GoTrue auto-refresh periodic timer, which otherwise
          // leaks past widget disposal and trips flutter_test's
          // "Timer still pending" invariant.
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ));

  final bool throwOnSave;
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<SavedDocument> saveGenerated({
    required String employeeId,
    required String documentType,
    required String title,
    required String fileName,
    required Map<String, dynamic> generationOptions,
    String? templateId,
    String? sessionRecordId,
  }) async {
    calls.add({
      'employeeId': employeeId,
      'documentType': documentType,
      'title': title,
      'fileName': fileName,
      'generationOptions': generationOptions,
      'templateId': templateId,
      'sessionRecordId': sessionRecordId,
    });
    if (throwOnSave) {
      throw Exception('settings insert RLS denied');
    }
    // Echo back a stable id so the screen carries it as sessionRecordId.
    return SavedDocument(id: sessionRecordId ?? 'saved-doc-1');
  }
}

// Use ≥8-char ids: filenameForDocument falls back to employeeId.substring(0, 8)
// when there's no employee number, so shorter ids would RangeError.
const _empId = 'emp-00000001';
const _coId = 'co-00000001';

Employee _employee() => Employee(
      id: _empId,
      companyId: _coId,
      employeeNumber: 'EMP-001',
      firstName: 'Alice',
      lastName: 'Cruz',
      jobTitle: 'Sales Associate',
      hiringEntityId: _coId,
      gender: 'Female',
      employmentType: 'REGULAR',
      employmentStatus: 'RESIGNED',
      hireDate: DateTime(2020, 1, 1),
      separationDate: DateTime(2024, 6, 30),
      isRankAndFile: true,
      isOtEligible: true,
      isNdEligible: true,
      isHolidayPayEligible: true,
      taxOnFullEarnings: false,
      addressLine1: '123 Mabini St',
      city: 'Makati',
      province: 'Metro Manila',
      zipCode: '1200',
    );

const _company = HiringEntity(
  id: _coId,
  companyId: _coId,
  code: 'LUX',
  name: 'LUXIUM TRADING CO.',
  hrManagerName: 'Brixter Del Mundo',
  addressLine1: '1 Ayala Ave',
  city: 'Makati',
  province: 'Metro Manila',
  zipCode: '1200',
);

/// Pumps a COE [GenerateScreen] inside a GoRouter + ProviderScope with all
/// data providers stubbed offline. When [employeeId] is null the COE starts
/// from empty inputs (invalid); otherwise it autofills to a fully-valid doc.
Future<void> _pumpCoe(
  WidgetTester tester, {
  required String? employeeId,
  required _FakeDocRepo repo,
}) async {
  final router = GoRouter(
    initialLocation: '/gen',
    routes: [
      GoRoute(
        path: '/gen',
        builder: (_, _) => GenerateScreen(
          templateId: 'coe',
          employeeId: employeeId,
          pdfThemeOverride: PdfTheme.testStub(),
          showLivePreview: false,
        ),
      ),
      GoRoute(
        path: '/documents',
        builder: (_, _) => const Scaffold(body: Text('Documents hub')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        employeeDocumentRepositoryProvider.overrideWithValue(repo),
        documentEmployeeProvider(_empId).overrideWith((ref) => _employee()),
        hiringEntityByIdProvider(_coId).overrideWith((ref) => _company),
        employeeListProvider(const EmployeeListQuery(includeArchived: true))
            .overrideWith((ref) => [_employee()]),
        employeeListProvider(const EmployeeListQuery())
            .overrideWith((ref) => [_employee()]),
        hiringEntityListProvider.overrideWith((ref) => [_company]),
        roleScorecardListProvider
            .overrideWith((ref) => const <RoleScorecard>[]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // Let the post-frame autofill + theme pre-warm settle.
  await tester.pumpAndSettle();
}

Finder _generateButton() => find.widgetWithText(FilledButton, 'Generate');

/// Tap Generate and pump a bounded number of frames. We can't `pumpAndSettle`
/// because the preview stage embeds a `PdfPreview` rasterizer that never
/// quiesces — but the Generate pipeline (render + fake save) completes within
/// a few microtask/animation frames, after which the preview bar is present.
Future<void> _tapGenerate(WidgetTester tester) async {
  await tester.tap(_generateButton());
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('GenerateScreen two-stage flow (COE)', () {
    testWidgets('Generate button is disabled when the form is invalid',
        (tester) async {
      final repo = _FakeDocRepo();
      await _pumpCoe(tester, employeeId: null, repo: repo);

      // Empty COE inputs ⇒ validation errors ⇒ Generate disabled.
      final btn = tester.widget<FilledButton>(_generateButton());
      expect(btn.onPressed, isNull, reason: 'invalid form must disable Generate');

      // No Download/Print exposed in the editing stage.
      expect(find.byIcon(Icons.download), findsNothing);
      expect(find.byIcon(Icons.print), findsNothing);
    });

    testWidgets('Generate button is enabled when the form is valid',
        (tester) async {
      final repo = _FakeDocRepo();
      await _pumpCoe(tester, employeeId: _empId, repo: repo);

      final btn = tester.widget<FilledButton>(_generateButton());
      expect(btn.onPressed, isNotNull, reason: 'valid form must enable Generate');
    });

    testWidgets(
        'pressing Generate transitions editing → preview and calls saveGenerated',
        (tester) async {
      final repo = _FakeDocRepo();
      await _pumpCoe(tester, employeeId: _empId, repo: repo);

      // Editing stage: no full export bar yet.
      expect(find.text('Back to edit'), findsNothing);

      await _tapGenerate(tester);

      // Preview stage reached.
      expect(find.text('Back to edit'), findsOneWidget);
      expect(find.text('Saved to the employee record.'), findsOneWidget);
      expect(find.byType(PdfPreviewScaffold), findsOneWidget);

      // Persistence happened with the right args.
      expect(repo.calls, hasLength(1));
      final call = repo.calls.single;
      expect(call['employeeId'], _empId);
      expect(call['documentType'], 'COE');
      expect(call['title'], 'Certificate of Employment');
      expect(call['templateId'], 'coe');
      expect(call['sessionRecordId'], isNull, reason: 'first save = insert');
      // The PDF is never persisted — settings-only. saveGenerated takes no
      // pdfBytes argument, so nothing PDF-shaped is recorded on the call.
      expect(call.containsKey('pdfBytes'), isFalse);
      expect(call.containsKey('pdfBytesLen'), isFalse);
      expect(call['generationOptions'], containsPair('employeeId', _empId));
    });

    testWidgets('Back to edit returns to editing with form state intact',
        (tester) async {
      final repo = _FakeDocRepo();
      await _pumpCoe(tester, employeeId: _empId, repo: repo);

      await _tapGenerate(tester);
      expect(find.text('Back to edit'), findsOneWidget);

      await tester.tap(find.text('Back to edit'));
      await tester.pump();

      // Back in the editing stage; the form (and its valid state) is intact.
      expect(find.text('Back to edit'), findsNothing);
      final btn = tester.widget<FilledButton>(_generateButton());
      expect(btn.onPressed, isNotNull,
          reason: 'form state preserved ⇒ still valid');

      // Re-generating in the same session UPDATES the same row: the second
      // saveGenerated carries the sessionRecordId returned by the first.
      await _tapGenerate(tester);
      expect(repo.calls, hasLength(2));
      expect(repo.calls.last['sessionRecordId'], 'saved-doc-1',
          reason: 'second save reuses the session record id');
    });

    testWidgets(
        'settings-save failure still reaches preview and warns (non-blocking)',
        (tester) async {
      final repo = _FakeDocRepo(throwOnSave: true);
      await _pumpCoe(tester, employeeId: _empId, repo: repo);

      await _tapGenerate(tester);

      // The render succeeded, so the preview stage IS reached even though the
      // settings record failed to save — Download/Print must keep working.
      expect(find.text('Back to edit'), findsOneWidget);
      expect(find.byType(PdfPreviewScaffold), findsOneWidget);

      // A non-blocking warning is surfaced (inline banner in the preview),
      // and the success "Saved to the employee record." line is NOT shown.
      expect(find.text('Saved to the employee record.'), findsNothing);
      expect(
        find.textContaining("settings weren't recorded"),
        findsWidgets,
      );
      // Save was attempted.
      expect(repo.calls, hasLength(1));
    });
  });

  // Applicant-mode (no employee id ⇒ skip persistence) is decided by the pure
  // `scopedEmployeeId` seam. A full applicant-mode UI flow is only reachable
  // via the Employment Contract template, whose extensive validation cannot be
  // satisfied through provider overrides alone (probation dates etc. are left
  // for manual entry by design) — so the skip DECISION is verified here at the
  // unit level instead, and the employee-scoped save path is verified by the
  // widget tests above.
  group('scopedEmployeeId (applicant-mode skip decision)', () {
    test('null id ⇒ null (skip save)', () {
      expect(scopedEmployeeId(null), isNull);
    });
    test('empty id ⇒ null (skip save)', () {
      expect(scopedEmployeeId(''), isNull);
    });
    test('non-empty id ⇒ unchanged (employee-scoped ⇒ save)', () {
      expect(scopedEmployeeId('emp-123'), 'emp-123');
    });
  });
}
