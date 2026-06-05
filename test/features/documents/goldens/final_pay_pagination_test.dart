// Renders a full Final Pay computation letter and asserts the PDF bytes
// are valid (%PDF magic) and exceed a reasonable byte threshold.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_template.dart';

void main() {
  test('Final Pay produces a valid PDF', () async {
    final theme = PdfTheme.testStub();
    final i = FinalPayInputs(
      employeeId: 'e1',
      employeeFullName: 'Alice Reyes',
      employeePosition: 'Senior Accountant',
      employeeHireDate: DateTime(2022, 1, 5),
      employeeSeparationDate: DateTime(2026, 5, 31),
      companyId: 'c1',
      companyName: 'Luxium Holdings Corp.',
      companyAddress: '123 Sample Address, Quezon City',
      hrManagerName: 'Brixter Cruz',
      lastNetPay: Decimal.parse('12345.67'),
      thirteenthMonth: Decimal.parse('8000.00'),
      unusedLeaveConversion: Decimal.parse('2400.00'),
      outstandingCashAdvance: Decimal.parse('500.00'),
      otherDeductions: Decimal.parse('150.00'),
      otherDeductionsLabel: 'SSS contribution top-up',
      computedAsOf: DateTime(2026, 6, 5),
      releaseDate: DateTime(2026, 7, 5),
    );
    const t = FinalPayTemplate();
    final bytes = await buildDocumentPdf(blocks: t.build(i), theme: theme);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    expect(bytes.length, greaterThan(2000));
  });
}
