import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';

void main() {
  test('EmploymentContractTemplate builds against an applicantId', () {
    final tpl = EmploymentContractTemplate();
    final inputs = EmploymentContractInputs(
      applicantId: 'a1',
      employeeFullName: 'Jamaica Vidal',
      employeeAddress: '123 Mabini St, Binondo, Manila',
      companyId: 'c1',
      companyName: 'LUXIUM TRADING CO.',
      companyAddress: '456 Quintin Paredes, Binondo, Manila',
      representativeName: 'Brixter Del Mundo',
      representativeRole: 'People Manager',
      place: 'Binondo, Metro Manila, Philippines',
      dateEntered: DateTime(2025, 12, 3),
      industry: 'Retail Industry',
      position: 'HR Assistant',
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
      missionStatement: 'Support HR operations end to end.',
      responsibilities: const [
        ContractResponsibility(
          area: 'Recruitment',
          tasks: ['Post job openings', 'Screen applicants'],
        ),
        ContractResponsibility(
          area: 'Records',
          tasks: ['Maintain 201 files'],
        ),
      ],
      kpis: const [
        ContractKpi(metric: 'Time to fill', frequency: 'Monthly'),
      ],
    );
    final blocks = tpl.build(inputs);
    expect(blocks, isNotEmpty);
  });
}
