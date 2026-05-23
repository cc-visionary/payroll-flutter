// Renders a full Liability Waiver and asserts the PDF bytes are valid
// (%PDF magic) and exceed a reasonable byte threshold for the document.

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_template.dart';

void main() {
  test('full Liability Waiver produces a valid PDF', () async {
    final theme = PdfTheme.testStub();
    final inputs = LiabilityWaiverInputs(
      employeeId: 'e1',
      employeeFullName: 'Jamaica Phomela Litang Vidal',
      employeeAddress: '8 Tendido Street, San Jose, Quezon City',
      companyId: 'c1',
      companyName: 'Luxium Trading Co.',
      dateOfEmployment: DateTime(2024, 1, 15),
      outingDate: DateTime(2026, 6, 20),
      outingLocation: 'Tagaytay City, Cavite',
      dateSigned: DateTime(2026, 5, 23),
      signingPlace: 'Quezon City, Metro Manila',
    );
    const t = LiabilityWaiverTemplate();
    final bytes = await buildDocumentPdf(blocks: t.build(inputs), theme: theme);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    // 5 numbered items + lettered lists + signature → 2-page document.
    expect(bytes.length, greaterThan(2000));
  });
}
