import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_template.dart';

void main() {
  test('Regularization renders PDF', () async {
    final theme = PdfTheme.testStub();
    final i = RegularizationInputs(
      employeeId: 'e1',
      employeeFullName: 'Alice Reyes',
      employeePosition: 'Accountant',
      employeeGender: 'FEMALE',
      companyId: 'c1',
      companyName: 'Luxium',
      companyAddress: '123 QC',
      hrManagerName: 'Brixter',
      hireDate: DateTime(2026, 1, 5),
      regularizationDate: DateTime(2026, 6, 5),
      baseSalary: Decimal.parse('25000'),
      issueDate: DateTime(2026, 6, 5),
      performanceSummary: 'Exceeds expectations across all KPIs in Q1 and Q2.',
    );
    final bytes = await buildDocumentPdf(
      blocks: const RegularizationTemplate().build(i),
      theme: theme,
    );
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    expect(bytes.length, greaterThan(2000));
  });
}
