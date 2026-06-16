import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_preview_scaffold.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/view/document_view_screen.dart';

EmploymentContractInputs _contract() => EmploymentContractInputs(
      employeeId: 'emp-1',
      employeeFullName: 'Arriane Reynido Pabelonia',
      employeeAddress: '1 Mabini St',
      companyId: 'co-1',
      companyName: 'LUXIUM TRADING CO.',
      companyAddress: '1 Ayala Ave',
      representativeName: 'Brixter',
      representativeRole: 'HR Manager',
      place: 'Makati',
      dateEntered: DateTime(2026, 6, 15),
      industry: 'Retail',
      position: 'Sales & Ops Assistant',
      probationStart: DateTime(2026, 6, 15),
      probationEnd: DateTime(2026, 12, 15),
      monthlySalary: '695',
      salaryPeriod: 'day',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Saturday',
      nonCompeteMonths: 24,
      employerSignatoryName: 'Brixter Legaspi Del Mundo',
      employerSignatoryRole: 'HR Manager',
    );

Map<String, dynamic> _row({
  required String templateId,
  Map<String, dynamic>? options,
}) =>
    {
      'id': 'doc-1',
      'employee_id': 'emp-1',
      'document_type': templateId.toUpperCase(),
      'title': 'Employment Contract',
      'file_name': 'contract.pdf',
      'generation_options': {
        ...(options ?? _contract().toJson()),
        '__template_id': templateId,
      },
      'status': 'ISSUED',
    };

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic>? row,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        documentByIdProvider('doc-1').overrideWith((ref) => row),
      ],
      child: MaterialApp(
        home: DocumentViewScreen(
          documentId: 'doc-1',
          pdfThemeOverride: PdfTheme.testStub(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a PDF preview for a supported saved document',
      (tester) async {
    await _pump(tester, row: _row(templateId: 'employment_contract'));
    // PdfPreview rasterizes asynchronously and never fully settles, so pump a
    // bounded number of frames instead of pumpAndSettle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(PdfPreviewScaffold), findsOneWidget);
  });

  testWidgets('shows a friendly message for a type without a re-render path',
      (tester) async {
    // An id not in kReRenderableSavedTemplateIds (all real templates are now
    // supported, so use a synthetic unknown type to exercise the fallback).
    await _pump(tester, row: _row(templateId: 'totally_unknown'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfPreviewScaffold), findsNothing);
    expect(find.textContaining(RegExp("isn't available|not available")),
        findsOneWidget);
  });

  testWidgets('shows not-found when the document row is missing',
      (tester) async {
    await _pump(tester, row: null);
    await tester.pumpAndSettle();
    expect(find.textContaining('not found'), findsOneWidget);
  });
}
