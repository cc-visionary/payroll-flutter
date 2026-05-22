import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_validate.dart';

void main() {
  EmploymentContractInputs valid() => EmploymentContractInputs(
        employeeId: 'e1',
        employeeFullName: 'Jamaica Vidal',
        employeeAddress: '8 Tendido St, Quezon City',
        companyId: 'c1',
        companyName: 'Luxium Trading Co.',
        companyAddress: '908 Alvarado St, Manila',
        representativeName: 'Brixter Del Mundo',
        representativeRole: 'People Manager',
        place: 'Binondo, Metro Manila, Philippines',
        dateEntered: DateTime(2025, 6, 9),
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
        responsibilities: const [
          ContractResponsibility(area: 'Primary', tasks: ['Recruit']),
        ],
      );

  test('valid inputs produce no errors', () {
    expect(validateEmploymentContract(valid()), isEmpty);
  });

  test('empty employeeId flagged', () {
    expect(validateEmploymentContract(valid().copyWith(employeeId: ''))
        .any((e) => e.field == 'employee'), true);
  });

  test('empty companyId flagged', () {
    expect(validateEmploymentContract(valid().copyWith(companyId: ''))
        .any((e) => e.field == 'company'), true);
  });

  test('empty position flagged', () {
    expect(validateEmploymentContract(valid().copyWith(position: ''))
        .any((e) => e.field == 'position'), true);
  });

  test('empty monthlySalary flagged', () {
    expect(validateEmploymentContract(valid().copyWith(monthlySalary: ''))
        .any((e) => e.field == 'monthlySalary'), true);
  });

  test('empty representativeName flagged', () {
    expect(validateEmploymentContract(valid().copyWith(representativeName: ''))
        .any((e) => e.field == 'representativeName'), true);
  });

  test('null probationStart flagged', () {
    expect(validateEmploymentContract(valid().copyWith(probationStart: null))
        .any((e) => e.field == 'probationStart'), true);
  });

  test('probationEnd before start flagged', () {
    final i = valid().copyWith(
      probationStart: DateTime(2025, 12, 6),
      probationEnd: DateTime(2025, 6, 9),
    );
    expect(validateEmploymentContract(i).any((e) => e.field == 'probationEnd'),
        true);
  });

  test('empty responsibilities flagged', () {
    expect(validateEmploymentContract(valid().copyWith(responsibilities: const []))
        .any((e) => e.field == 'responsibilities'), true);
  });

  test('responsibility with empty area flagged', () {
    final i = valid().copyWith(responsibilities: const [
      ContractResponsibility(area: '', tasks: ['x']),
    ]);
    expect(validateEmploymentContract(i)
        .any((e) => e.field == 'responsibilities[0].area'), true);
  });

  test('responsibility with no tasks flagged', () {
    final i = valid().copyWith(responsibilities: const [
      ContractResponsibility(area: 'Primary', tasks: []),
    ]);
    expect(validateEmploymentContract(i)
        .any((e) => e.field == 'responsibilities[0].tasks'), true);
  });

  test('zero workHoursPerDay flagged', () {
    expect(validateEmploymentContract(valid().copyWith(workHoursPerDay: 0))
        .any((e) => e.field == 'workHoursPerDay'), true);
  });

  test('zero nonCompeteMonths flagged', () {
    expect(validateEmploymentContract(valid().copyWith(nonCompeteMonths: 0))
        .any((e) => e.field == 'nonCompeteMonths'), true);
  });
}
