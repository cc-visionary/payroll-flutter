// Renders a Non-Reg with enough findings to force pagination, then asserts
// the PDF bytes contain valid PDF magic and exceed a reasonable byte
// threshold for a 2+ page document. Full text-extraction verification of
// the "Page X of Y" footer is covered by the unit test in
// test/core/pdf/page_footer_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  test('Non-Reg with 5 findings × 3 sub-findings produces multi-page PDF',
      () async {
    final theme = PdfTheme.testStub();
    final inputs = NonRegInputs(
      employeeId: 'e1',
      employeeFullName: 'Jamaica Phomela Litang Vidal',
      employeeLastName: 'Vidal',
      employeePosition: 'HR Assistant',
      companyId: 'c1',
      companyName: 'LUXIUM TRADING CO.',
      hrManagerName: 'Brixter Del Mundo',
      dateIssued: DateTime(2025, 12, 3),
      probationaryStart: DateTime(2025, 6, 9),
      probationaryEnd: DateTime(2025, 12, 6),
      effectiveEndDate: DateTime(2025, 12, 5),
      salutationName: 'Ms. Vidal',
      noteOnScope:
          'While your primary title is HR Assistant, your evaluation '
          'encompasses your assigned sales support duties during the LCT '
          'Bazaar.',
      findings: [
        for (var i = 0; i < 5; i++)
          FindingSection(
            title: 'Finding section ${i + 1} — long descriptive title for '
                'pagination testing',
            standard:
                'Annex B requires the employee to demonstrate the necessary '
                'role-specific skills and knowledge to perform their job '
                'effectively without excessive supervision. Lorem ipsum '
                'dolor sit amet, consectetur adipiscing elit.',
            finding:
                'You have failed to demonstrate the required level of '
                'engagement and focus expected of this role. Duis ac '
                'fermentum erat. Donec pulvinar lacinia magna.',
            subFindings: [
              for (var s = 0; s < 3; s++)
                SubFinding(
                  title: 'Sub-finding ${s + 1}',
                  body: 'Detailed body text for sub-finding ${s + 1}. '
                      'Lorem ipsum dolor sit amet, consectetur adipiscing '
                      'elit. Pellentesque habitant morbi tristique.',
                ),
            ],
          ),
      ],
    );
    const t = NonRegTemplate();
    final bytes =
        await buildDocumentPdf(blocks: t.build(inputs), theme: theme);

    // PDF magic header
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');

    // Reasonable byte threshold for a multi-page Non-Reg with 5 findings,
    // intro paragraphs, decision, and acknowledgment page.
    expect(bytes.length, greaterThan(3000));
  });
}
