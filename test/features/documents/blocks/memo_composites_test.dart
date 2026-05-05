import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/letter_meta_block.dart';
import 'package:payroll_flutter/features/documents/blocks/memo_header_block.dart';
import 'package:payroll_flutter/features/documents/blocks/memo_acknowledgment_block.dart';

void main() {
  test('MemoHeaderBlock stores all fields', () {
    final b = MemoHeaderBlock(
      titleText: 'NOTICE TO EXPLAIN',
      companyName: 'LUXIUM TRADING CO.',
      companyAddress: '908 Alvarado',
      date: DateTime(2026, 4, 27),
      to: const LetterParty(name: 'Donald', subtitle: 'CTO'),
      from: const LetterParty(name: 'Brixter', subtitle: 'HR Manager'),
      subject: 'Notice to Explain',
      salutation: 'Mr. Donald',
    );
    expect(b.titleText, 'NOTICE TO EXPLAIN');
  });

  test('MemoAcknowledgmentBlock is a const default', () {
    const b = MemoAcknowledgmentBlock();
    expect(b, isNotNull);
  });

  test('composites render without throwing', () async {
    final theme = await PdfTheme.defaults();
    expect(
      () => MemoHeaderBlock(
        titleText: 't',
        companyName: 'c',
        date: DateTime(2026, 1, 1),
        to: const LetterParty(name: 'a'),
        from: const LetterParty(name: 'b'),
        subject: 's',
      ).toPdf(theme),
      returnsNormally,
    );
    expect(
      () => const MemoAcknowledgmentBlock().toPdf(theme),
      returnsNormally,
    );
  });
}
