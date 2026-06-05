// Renders Salary Adjustment letters in both modes (pure salary change and
// promotion) and asserts the PDF bytes are valid (%PDF magic) and exceed a
// reasonable byte threshold.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_template.dart';

void main() {
  test('SalaryAdjustment ADJUSTMENT mode renders PDF', () async {
    final theme = PdfTheme.testStub();
    final i = SalaryAdjustmentInputs(
      employeeId: 'e1',
      employeeFullName: 'Alice Reyes',
      employeePosition: 'Accountant',
      companyId: 'c1',
      companyName: 'GameCove',
      hrManagerName: 'Brixter',
      oldSalary: Decimal.parse('20000'),
      newSalary: Decimal.parse('25000'),
      effectiveDate: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      reason: 'In recognition of your performance.',
    );
    final bytes = await buildDocumentPdf(
      blocks: const SalaryAdjustmentTemplate().build(i),
      theme: theme,
    );
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    expect(bytes.length, greaterThan(1500));
  });

  test('SalaryAdjustment PROMOTION mode renders PDF', () async {
    final theme = PdfTheme.testStub();
    final i = SalaryAdjustmentInputs(
      type: SalaryAdjustmentType.promotion,
      employeeId: 'e1',
      employeeFullName: 'Alice Reyes',
      employeePosition: 'Accountant',
      companyId: 'c1',
      companyName: 'GameCove',
      hrManagerName: 'Brixter',
      oldPosition: 'Accountant',
      newPosition: 'Senior Accountant',
      oldRoleScorecardId: 'r1',
      newRoleScorecardId: 'r2',
      oldSalary: Decimal.parse('20000'),
      newSalary: Decimal.parse('28000'),
      effectiveDate: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      reason: 'Promoted following Q2 performance review.',
    );
    final bytes = await buildDocumentPdf(
      blocks: const SalaryAdjustmentTemplate().build(i),
      theme: theme,
    );
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    expect(bytes.length, greaterThan(1500));
  });
}
