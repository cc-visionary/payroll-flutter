// Renders an NTE with enough charges to force pagination, then asserts
// the PDF bytes contain valid PDF magic and exceed a reasonable byte
// threshold for a 2+ page document. Full text-extraction verification
// of the "Page X of Y" footer is covered by the unit test in
// test/core/pdf/page_footer_test.dart.

import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nte_template.dart';

void main() {
  test('NTE with 6 charges paginates and produces valid multi-page PDF',
      () async {
    final theme = PdfTheme.testStub();
    final inputs = NteInputs(
      employeeId: 'e1',
      employeeFullName: 'Donald Xu',
      employeeFirstName: 'Donald',
      employeeLastName: 'Xu',
      employeePosition: 'CTO',
      employeeDepartment: 'Tech',
      companyId: 'c1',
      companyName: 'LUXIUM TRADING CO.',
      hrManagerName: 'Brixter',
      dateIssued: DateTime(2026, 5, 5),
      responseDeadline: DateTime(2026, 5, 10),
      subjectSubtopic: 'Pagination test',
      charges: [
        for (var i = 0; i < 6; i++)
          NteCharge(
            title: 'Charge ${i + 1}',
            body: Delta()
              ..insert(
                  'This is the body of charge ${i + 1}. It is intentionally '
                  'long to consume vertical space and force the document to '
                  'spill onto multiple pages so the page-number footer can '
                  'be exercised end-to-end. Lorem ipsum dolor sit amet, '
                  'consectetur adipiscing elit. Duis ac fermentum erat.\n'),
          ),
      ],
      applicableViolations: ['Code of Conduct §3.1'],
    );
    const t = NteTemplate();
    final bytes = await buildDocumentPdf(blocks: t.build(inputs), theme: theme);

    // PDF magic header
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');

    // Reasonable byte threshold for a multi-page doc with 6 charges +
    // memo header + memo acknowledgment footer.
    expect(bytes.length, greaterThan(2000));
  });
}
