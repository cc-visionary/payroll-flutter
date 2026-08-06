import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/centered_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/letterhead_block.dart';
import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/key_value_block.dart';
import 'package:payroll_flutter/features/documents/blocks/company_header_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_template.dart';

void main() {
  QuitclaimInputs filled() => QuitclaimInputs(
    employeeId: 'emp-1',
    employeeFullName: 'Donald Xu',
    employeeAddress: '123 Mabini St, Manila',
    civilStatus: 'single',
    companyId: 'co-1',
    companyName: 'LUXIUM TRADING CO.',
    finalPayAmount: Decimal.parse('47250.00'),
    dateTerminated: DateTime(2026, 4, 30),
    dateSigned: DateTime(2026, 5, 5),
    placeSigned: 'Manila City',
  );

  test('build returns a non-empty block list', () {
    const t = QuitclaimTemplate();
    expect(t.build(filled()), isNotEmpty);
  });

  test('quitclaim build prepends LetterheadBlock', () {
    final i = filled().copyWith(
      logoBytes: Uint8List.fromList(const [137, 80, 78, 71]),
    );
    final blocks = const QuitclaimTemplate().build(i);
    expect(blocks.whereType<LetterheadBlock>(), isNotEmpty);
  });

  test(
    'first block is LetterheadBlock when companyName is set, canonical title is present',
    () {
      const t = QuitclaimTemplate();
      final blocks = t.build(filled());
      expect(blocks.first, isA<LetterheadBlock>());
      final titles = blocks.whereType<TitleBlock>().toList();
      expect(
        titles.any((b) => b.text == 'QUITCLAIM AND RELEASE' && b.centered),
        true,
      );
    },
  );

  test('build includes a centered employee signature block', () {
    const t = QuitclaimTemplate();
    final blocks = t.build(filled());
    final sig = blocks.whereType<CenteredSignatureBlock>().first;
    expect(sig.caption, 'Name and signature of Employee');
  });

  test('build includes the four notary lines', () {
    const t = QuitclaimTemplate();
    final paras = t
        .build(filled())
        .whereType<ParagraphBlock>()
        .map((p) => p.text);
    expect(paras.any((s) => s.startsWith('Doc. No.')), true);
    expect(paras.any((s) => s.startsWith('Page No.')), true);
    expect(paras.any((s) => s.startsWith('Book No.')), true);
    expect(paras.any((s) => s.startsWith('Series of 20')), true);
  });

  test('build has no logo, company header, key-value, or signatory block', () {
    const t = QuitclaimTemplate();
    final blocks = t.build(filled());
    expect(blocks.whereType<MultiSignatureBlock>(), isEmpty);
    expect(blocks.whereType<KeyValueBlock>(), isEmpty);
    expect(blocks.whereType<CompanyHeaderBlock>(), isEmpty);
  });
}
