import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/letter_meta_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_template.dart';

SalaryAdjustmentInputs _i(SalaryAdjustmentType type) => SalaryAdjustmentInputs(
      type: type,
      employeeId: 'E1',
      employeeFullName: 'Jane Cruz',
      employeeGender: 'FEMALE',
      employeePosition: 'Brand Handler',
      companyId: 'CO1',
      companyName: 'Luxium',
      hrManagerName: 'Brixter',
      oldPosition: 'Brand Handler',
      newPosition: 'Senior Brand Handler',
      oldSalary: Decimal.parse('30000'),
      newSalary: type == SalaryAdjustmentType.lateral
          ? Decimal.parse('30000')
          : Decimal.parse('35000'),
      salaryPeriod: 'MONTHLY',
      reason: 'Merit review.',
      effectiveDate: DateTime.parse('2026-08-01'),
      issueDate: DateTime.parse('2026-07-08'),
    );

String _subject(List blocks) =>
    blocks.whereType<LetterMetaBlock>().first.subject ?? '';
String _body(List blocks) =>
    blocks.whereType<ParagraphBlock>().map((b) => b.text).join('\n');

void main() {
  const t = SalaryAdjustmentTemplate();

  test('lateral subject + unchanged-salary wording', () {
    final blocks = t.build(_i(SalaryAdjustmentType.lateral));
    expect(_subject(blocks), 'Notice of Lateral Transfer');
    expect(_body(blocks).toLowerCase(), contains('transferred'));
    expect(_body(blocks).toLowerCase(), contains('remains unchanged'));
  });

  test('demotion subject', () {
    final blocks = t.build(_i(SalaryAdjustmentType.demotion));
    expect(_subject(blocks), 'Notice of Change in Role');
  });

  test('promotion subject still works', () {
    final blocks = t.build(_i(SalaryAdjustmentType.promotion));
    expect(_subject(blocks), 'Notice of Promotion');
  });

  test('salary adjustment subject still works', () {
    final blocks = t.build(_i(SalaryAdjustmentType.salaryAdjustment));
    expect(_subject(blocks), 'Notice of Salary Adjustment');
  });
}
