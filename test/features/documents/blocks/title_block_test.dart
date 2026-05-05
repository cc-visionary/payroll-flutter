import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';

void main() {
  test('TitleBlock exposes its text', () {
    const block = TitleBlock('PREVENTIVE SUSPENSION MEMO');
    expect(block.text, 'PREVENTIVE SUSPENSION MEMO');
  });

  test('TitleBlock toPdf does not throw', () async {
    final theme = await PdfTheme.defaults();
    expect(() => const TitleBlock('Title').toPdf(theme), returnsNormally);
  });
}
