import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/section_heading_block.dart';

void main() {
  test('HeadingBlock stores text', () {
    const block = HeadingBlock('Section A');
    expect(block.text, 'Section A');
  });

  test('SectionHeadingBlock formats "N. Title"', () {
    const block = SectionHeadingBlock(number: 3, title: 'Repayment Options');
    expect(block.formatted, '3. Repayment Options');
  });

  test('blocks render without throwing', () async {
    final theme = await PdfTheme.defaults();
    expect(() => const HeadingBlock('h').toPdf(theme), returnsNormally);
    expect(
      () =>
          const SectionHeadingBlock(number: 1, title: 't').toPdf(theme),
      returnsNormally,
    );
  });
}
