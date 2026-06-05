import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_template.dart';

void main() {
  test('NOD renders PDF', () async {
    final theme = PdfTheme.testStub();
    final i = NodInputs(
      employeeId: 'e1',
      employeeFullName: 'Alice Reyes',
      employeePosition: 'Accountant',
      employeeGender: 'FEMALE',
      companyId: 'c1',
      companyName: 'Luxium',
      companyAddress: '123 Quezon City',
      hrManagerName: 'Brixter Cruz',
      nteDate: DateTime(2026, 5, 20),
      charges:
          'Three (3) instances of unexcused absence in May 2026 — May 3, May 14, May 22.',
      employeeResponseSummary:
          'Employee cites family emergency for May 3; no excuse offered for May 14 and May 22.',
      findings:
          'Two absences (May 14, May 22) are unexcused; May 3 is partly mitigated.',
      decision: NodDecision.suspension,
      suspensionDays: 3,
      effectiveDate: DateTime(2026, 6, 10),
      issueDate: DateTime(2026, 6, 5),
    );
    final bytes = await buildDocumentPdf(
      blocks: const NodTemplate().build(i),
      theme: theme,
    );
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    expect(bytes.length, greaterThan(2000));
  });
}
