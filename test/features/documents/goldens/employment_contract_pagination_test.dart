// Renders a full Employment Contract and asserts the PDF bytes are valid
// (%PDF magic) and exceed a reasonable byte threshold for a multi-page
// document. Full footer text-extraction is covered by the page_footer
// unit test.

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';

void main() {
  test('full Employment Contract produces a valid multi-page PDF', () async {
    final theme = PdfTheme.testStub();
    final inputs = EmploymentContractInputs(
      employeeId: 'e1',
      employeeFullName: 'Jamaica Phomela Litang Vidal',
      employeeAddress: '8 Tendido Street, San Jose, Quezon City',
      companyId: 'c1',
      companyName: 'Luxium Trading Co.',
      companyAddress: '908 Alvarado Street, Binondo, Manila, 1006',
      representativeName: 'Brixter Del Mundo',
      representativeRole: 'People Manager',
      place: 'Binondo, Metro Manila, Philippines',
      dateEntered: DateTime(2025, 6, 9),
      industry: 'Retail Industry',
      position: 'Human Resources and Administrative Assistant',
      probationStart: DateTime(2025, 6, 9),
      probationEnd: DateTime(2025, 12, 6),
      monthlySalary: '17,000',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Saturday',
      nonCompeteMonths: 24,
      employerSignatoryName: 'Brixter Del Mundo',
      employerSignatoryRole: 'People Manager',
      witness1Name: 'Christopher Lim',
      witness1Role: 'COO',
      witness2Name: 'Clinton Xu',
      witness2Role: 'CEO',
      missionStatement:
          'Support HR and administrative operations across the company.',
      responsibilities: const [
        ContractResponsibility(
          area: 'Primary Responsibilities',
          tasks: [
            'Assist in end-to-end recruitment activities.',
            'Support the onboarding process for new hires.',
            'Maintain and organize employee records.',
          ],
        ),
        ContractResponsibility(
          area: 'Administrative Tasks',
          tasks: [
            'Update and manage the HR calendar.',
            'Monitor office supplies inventory.',
          ],
        ),
      ],
      kpis: const [
        ContractKpi(
          metric: 'Timeliness of calendar updates',
          frequency: 'Weekly',
        ),
        ContractKpi(
          metric: 'Recruitment coordination efficiency',
          frequency: 'Monthly',
        ),
      ],
    );
    const t = EmploymentContractTemplate();
    final bytes = await buildDocumentPdf(blocks: t.build(inputs), theme: theme);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    // 17 clauses + preamble + Annex A → comfortably multi-page.
    expect(bytes.length, greaterThan(4000));
  });
}
