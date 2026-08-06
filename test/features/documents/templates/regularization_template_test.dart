import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/memo_header_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_template.dart';

RegularizationInputs _ri() => RegularizationInputs(
  employeeId: 'e1',
  employeeFullName: 'Bob',
  companyId: 'c1',
  companyName: 'Luxium',
  hrManagerName: 'HR',
  regularizationDate: DateTime(2026, 6, 5),
  baseSalary: Decimal.parse('25000'),
  issueDate: DateTime(2026, 6, 5),
);

void main() {
  test('id + name + supportsBulk', () {
    const t = RegularizationTemplate();
    expect(t.id, 'regularization');
    expect(t.supportsBulk, isTrue);
  });

  test('build mentions Congratulations + regularization date', () {
    final i = RegularizationInputs(
      employeeId: 'e1',
      employeeFullName: 'Bob',
      companyId: 'c1',
      companyName: 'Luxium',
      hrManagerName: 'HR',
      hireDate: DateTime(2026, 1, 5),
      regularizationDate: DateTime(2026, 6, 5),
      baseSalary: Decimal.parse('25000'),
      issueDate: DateTime(2026, 6, 5),
    );
    final text = const RegularizationTemplate()
        .build(i)
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .join(' ');
    expect(text.toLowerCase(), contains('congratulations'));
    expect(text, contains('June 5, 2026'));
  });

  test('Performance Summary heading only if non-empty', () {
    final base = RegularizationInputs(
      employeeId: 'e1',
      employeeFullName: 'B',
      companyId: 'c1',
      companyName: 'X',
      hrManagerName: 'HR',
      regularizationDate: DateTime(2026, 6, 5),
      baseSalary: Decimal.parse('1'),
      issueDate: DateTime(2026, 6, 5),
    );
    const t = RegularizationTemplate();
    expect(
      t
          .build(base)
          .whereType<HeadingBlock>()
          .any((h) => h.text.contains('Performance')),
      isFalse,
    );
    final withSummary = base.copyWith(
      performanceSummary: 'Exceeds expectations.',
    );
    expect(
      t
          .build(withSummary)
          .whereType<HeadingBlock>()
          .any((h) => h.text.contains('Performance')),
      isTrue,
    );
  });

  test('build: MemoHeaderBlock is first and carries logoBytes when set', () {
    final blocks = const RegularizationTemplate().build(
      _ri().copyWith(logoBytes: Uint8List.fromList(const [137, 80, 78, 71])),
    );
    expect(blocks.first, isA<MemoHeaderBlock>());
    expect((blocks.first as MemoHeaderBlock).logoBytes, isNotNull);
  });
}
