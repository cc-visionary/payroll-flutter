import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_validate.dart';

void main() {
  NonRegInputs valid() => NonRegInputs(
        employeeId: 'e1',
        employeeFullName: 'Jamaica Vidal',
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
        findings: [
          const FindingSection(
            title: 'Failure to Meet Performance Standards',
            standard: 'Annex B requires demonstrating skills.',
            finding: 'Output has been substandard.',
            subFindings: [
              SubFinding(
                title: 'Lack of Core Competency',
                body: 'You failed to demonstrate working knowledge.',
              ),
            ],
          ),
        ],
      );

  test('valid inputs produce no errors', () {
    expect(validateNonReg(valid()), isEmpty);
  });

  test('empty employeeId flagged', () {
    final i = valid().copyWith(employeeId: '');
    expect(validateNonReg(i).any((e) => e.field == 'employee'), true);
  });

  test('empty companyId flagged', () {
    final i = valid().copyWith(companyId: '');
    expect(validateNonReg(i).any((e) => e.field == 'company'), true);
  });

  test('missing hrManagerName flagged', () {
    final i = valid().copyWith(hrManagerName: '');
    expect(
      validateNonReg(i).any((e) => e.field == 'hrManagerName'),
      true,
    );
  });

  test('empty findings list flagged', () {
    final i = valid().copyWith(findings: const []);
    expect(validateNonReg(i).any((e) => e.field == 'findings'), true);
  });
}
