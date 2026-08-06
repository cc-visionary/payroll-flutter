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
    expect(validateNonReg(i).any((e) => e.field == 'hrManagerName'), true);
  });

  test('empty findings list flagged', () {
    final i = valid().copyWith(findings: const []);
    expect(validateNonReg(i).any((e) => e.field == 'findings'), true);
  });

  test('empty finding title flagged', () {
    final i = valid().copyWith(
      findings: const [FindingSection(title: '', standard: 's', finding: 'f')],
    );
    expect(validateNonReg(i).any((e) => e.field == 'findings[0].title'), true);
  });

  test('empty finding standard flagged', () {
    final i = valid().copyWith(
      findings: const [FindingSection(title: 'T', standard: '', finding: 'f')],
    );
    expect(
      validateNonReg(i).any((e) => e.field == 'findings[0].standard'),
      true,
    );
  });

  test('empty finding finding-body flagged', () {
    final i = valid().copyWith(
      findings: const [FindingSection(title: 'T', standard: 's', finding: '')],
    );
    expect(
      validateNonReg(i).any((e) => e.field == 'findings[0].finding'),
      true,
    );
  });

  test('empty sub-finding title flagged', () {
    final i = valid().copyWith(
      findings: const [
        FindingSection(
          title: 'T',
          standard: 's',
          finding: 'f',
          subFindings: [SubFinding(title: '', body: 'b')],
        ),
      ],
    );
    expect(
      validateNonReg(
        i,
      ).any((e) => e.field == 'findings[0].subFindings[0].title'),
      true,
    );
  });

  test('empty sub-finding body flagged', () {
    final i = valid().copyWith(
      findings: const [
        FindingSection(
          title: 'T',
          standard: 's',
          finding: 'f',
          subFindings: [SubFinding(title: 't', body: '')],
        ),
      ],
    );
    expect(
      validateNonReg(
        i,
      ).any((e) => e.field == 'findings[0].subFindings[0].body'),
      true,
    );
  });

  test('probationaryEnd before probationaryStart flagged', () {
    final i = valid().copyWith(
      probationaryStart: DateTime(2025, 12, 6),
      probationaryEnd: DateTime(2025, 6, 9),
    );
    expect(validateNonReg(i).any((e) => e.field == 'probationaryEnd'), true);
  });

  test('effectiveEndDate before probationaryStart flagged', () {
    final i = valid().copyWith(effectiveEndDate: DateTime(2025, 6, 1));
    expect(validateNonReg(i).any((e) => e.field == 'effectiveEndDate'), true);
  });

  test('effectiveEndDate well after probationaryEnd flagged', () {
    final i = valid().copyWith(
      probationaryEnd: DateTime(2025, 12, 6),
      effectiveEndDate: DateTime(2026, 1, 1),
    );
    expect(validateNonReg(i).any((e) => e.field == 'effectiveEndDate'), true);
  });

  test('effectiveEndDate within 7-day grace of probationaryEnd OK', () {
    final i = valid().copyWith(
      probationaryEnd: DateTime(2025, 12, 6),
      effectiveEndDate: DateTime(2025, 12, 12), // +6 days = within grace
    );
    expect(validateNonReg(i).any((e) => e.field == 'effectiveEndDate'), false);
  });
}
