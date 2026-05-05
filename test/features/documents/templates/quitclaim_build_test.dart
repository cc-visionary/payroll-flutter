import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';
import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/key_value_block.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_template.dart';

void main() {
  QuitclaimInputs filled() => QuitclaimInputs(
        employeeId: 'emp-1',
        employeeFullName: 'Donald Xu',
        companyId: 'co-1',
        companyName: 'LUXIUM TRADING CO.',
        companyAddress: 'Manila',
        companySignatoryName: 'Clinton Xu',
        companySignatoryRole: 'CEO',
        dateTerminated: DateTime(2026, 4, 30),
        dateSigned: DateTime(2026, 5, 5),
        finalPayAmount: Decimal.parse('47250.00'),
      );

  test('build returns a non-empty block list', () {
    const t = QuitclaimTemplate();
    final blocks = t.build(filled());
    expect(blocks, isNotEmpty);
  });

  test('build contains the canonical title', () {
    const t = QuitclaimTemplate();
    final blocks = t.build(filled());
    final title = blocks.whereType<TitleBlock>().first;
    expect(title.text, 'RELEASE, WAIVER, AND QUITCLAIM');
  });

  test('build ends with a multi-signature block', () {
    const t = QuitclaimTemplate();
    final blocks = t.build(filled());
    expect(blocks.last, isA<MultiSignatureBlock>());
  });

  test('build includes a KeyValueBlock with all 5 rows', () {
    const t = QuitclaimTemplate();
    final blocks = t.build(filled());
    final kv = blocks.whereType<KeyValueBlock>().first;
    expect(kv.rows.length, 5);
  });
}
