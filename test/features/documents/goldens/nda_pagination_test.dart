// Renders a full NDA and asserts the PDF bytes are valid (%PDF magic) and
// exceed a reasonable byte threshold for a multi-page document.

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/nda_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nda_template.dart';

void main() {
  test('full NDA produces a valid multi-page PDF', () async {
    final theme = PdfTheme.testStub();
    final inputs = NdaInputs(
      employeeId: 'e1',
      employeeFullName: 'Jamaica Phomela Litang Vidal',
      employeePosition: 'Human Resources and Administrative Assistant',
      employeeHomeAddress: '8 Tendido Street, San Jose, Quezon City',
      companyId: 'c1',
      companyName: 'Luxium Trading Co.',
      companyAddress: '908 Alvarado Street, Binondo, Manila, 1006',
      effectiveDate: DateTime(2025, 6, 9),
      authorizedSignatoryName: 'Brixter Del Mundo',
      authorizedSignatoryRole: 'People Manager',
    );
    const t = NdaTemplate();
    final bytes = await buildDocumentPdf(blocks: t.build(inputs), theme: theme);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    // 16 clauses + parties preamble + signature block → comfortably multi-page.
    expect(bytes.length, greaterThan(4000));
  });
}
