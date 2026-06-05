import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/key_value_block.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_template.dart';

void main() {
  test('FinalPayTemplate exposes correct id + name', () {
    const t = FinalPayTemplate();
    expect(t.id, 'final_pay');
    expect(t.name, contains('Final Pay'));
    expect(t.supportsBulk, isFalse);
  });

  test(
    'build() emits Computation heading + KeyValueBlock + multi-row math',
    () {
      final i = FinalPayInputs(
        employeeId: 'e1',
        employeeFullName: 'Alice',
        employeePosition: 'Accountant',
        employeeSeparationDate: DateTime(2026, 5, 31),
        companyId: 'c1',
        companyName: 'Luxium',
        companyAddress: '123 Street',
        hrManagerName: 'Brixter',
        lastNetPay: Decimal.parse('5000'),
        thirteenthMonth: Decimal.parse('2500'),
        unusedLeaveConversion: Decimal.parse('1000'),
        outstandingCashAdvance: Decimal.zero,
        computedAsOf: DateTime(2026, 6, 5),
        releaseDate: DateTime(2026, 7, 5),
      );
      const t = FinalPayTemplate();
      final blocks = t.build(i);
      expect(
        blocks.whereType<HeadingBlock>().any((h) => h.text == 'Computation'),
        isTrue,
      );
      expect(blocks.whereType<KeyValueBlock>(), isNotEmpty);
    },
  );

  test('build() shows otherDeductions row only when > 0', () {
    final base = FinalPayInputs(
      employeeId: 'e1',
      employeeFullName: 'A',
      companyId: 'c1',
      companyName: 'X',
      hrManagerName: 'HR',
      lastNetPay: Decimal.parse('1000'),
      thirteenthMonth: Decimal.zero,
      unusedLeaveConversion: Decimal.zero,
      outstandingCashAdvance: Decimal.zero,
      computedAsOf: DateTime(2026, 6, 5),
      releaseDate: DateTime(2026, 6, 6),
    );
    const t = FinalPayTemplate();
    // 5 rows = lastNetPay + 13th + leave + cashAdvance + TOTAL
    // (no other deductions)
    final kvBase = t.build(base).whereType<KeyValueBlock>().first;
    expect(kvBase.rows.length, equals(5));

    final withDed = base.copyWith(
      otherDeductions: Decimal.parse('200'),
      otherDeductionsLabel: 'SSS top-up',
    );
    final kvDed = t.build(withDed).whereType<KeyValueBlock>().first;
    expect(kvDed.rows.length, equals(6));
  });
}
