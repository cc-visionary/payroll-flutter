import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_template.dart';

void main() {
  test('Resignation Acceptance renders PDF', () async {
    final theme = PdfTheme.testStub();
    final i = ResignationAcceptanceInputs(
      employeeId: 'e1',
      employeeFullName: 'Alice Reyes',
      employeePosition: 'Accountant',
      employeeGender: 'FEMALE',
      companyId: 'c1',
      companyName: 'Luxium',
      companyAddress: '123 QC',
      hrManagerName: 'Brixter',
      resignationDate: DateTime(2026, 6, 1),
      lastDayOfWork: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
    );
    final bytes = await buildDocumentPdf(
      blocks: const ResignationAcceptanceTemplate().build(i),
      theme: theme,
    );
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    expect(bytes.length, greaterThan(2000));
  });
}
