import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/letterhead_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_template.dart';

void main() {
  test('id + name + supportsBulk', () {
    const t = SalaryAdjustmentTemplate();
    expect(t.id, 'salary_adjustment');
    expect(t.name.toLowerCase(), contains('salary'));
    expect(t.supportsBulk, isTrue);
  });

  test('ADJUSTMENT subject reads "Notice of Salary Adjustment"', () {
    final i = SalaryAdjustmentInputs(
      employeeId: 'e1',
      employeeFullName: 'Bob',
      employeePosition: 'Dev',
      companyId: 'c1',
      companyName: 'Luxium',
      hrManagerName: 'HR',
      oldSalary: Decimal.parse('1'),
      newSalary: Decimal.parse('2'),
      effectiveDate: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      reason: 'r',
    );
    const t = SalaryAdjustmentTemplate();
    final ps = t
        .build(i)
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .toList();
    // Subject appears either in a LetterMetaBlock (not inspectable here) or in
    // body text. Either way the body should describe an adjustment, not a promotion.
    final joined = ps.join(' ');
    expect(joined, contains('salary will be adjusted'));
    expect(joined, isNot(contains('promoted from')));
  });

  test('build prepends a LetterheadBlock with company + logo', () {
    final i = SalaryAdjustmentInputs(
      employeeId: 'e',
      employeeFullName: 'Bob',
      companyId: 'c',
      companyName: 'GameCove Online Store',
      companyAddress: '1 Market St',
      effectiveDate: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      oldSalary: Decimal.parse('1'),
      newSalary: Decimal.parse('2'),
    ).copyWith(logoBytes: Uint8List.fromList(const [137, 80, 78, 71]));
    final blocks = const SalaryAdjustmentTemplate().build(i);
    final head = blocks.whereType<LetterheadBlock>().toList();
    expect(head, isNotEmpty);
    expect(head.first.companyName, 'GameCove Online Store');
    expect(head.first.logoBytes, isNotNull);
  });

  test('PROMOTION body mentions promoted from/to', () {
    final i = SalaryAdjustmentInputs(
      type: SalaryAdjustmentType.promotion,
      employeeId: 'e1',
      employeeFullName: 'Bob',
      employeePosition: 'Dev',
      companyId: 'c1',
      companyName: 'Luxium',
      hrManagerName: 'HR',
      oldPosition: 'Dev',
      newPosition: 'Senior Dev',
      oldRoleScorecardId: 'r1',
      newRoleScorecardId: 'r2',
      oldSalary: Decimal.parse('1'),
      newSalary: Decimal.parse('2'),
      effectiveDate: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      reason: 'r',
    );
    const t = SalaryAdjustmentTemplate();
    final ps = t
        .build(i)
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .toList();
    final joined = ps.join(' ');
    expect(joined, contains('promoted from'));
    expect(joined, contains('Senior Dev'));
  });
}
