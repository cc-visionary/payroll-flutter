import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';

void main() {
  test('TitleBlock exposes its fields', () {
    const block = TitleBlock('PREVENTIVE SUSPENSION MEMO');
    expect(block.text, 'PREVENTIVE SUSPENSION MEMO');
    expect(block.centered, isFalse);
    expect(const TitleBlock('X', centered: true).centered, isTrue);
  });

  test('TitleBlock toPdf does not throw (left-aligned)', () {
    final theme = PdfTheme.testStub();
    expect(() => const TitleBlock('Title').toPdf(theme), returnsNormally);
  });

  test('TitleBlock toPdf does not throw (centered)', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const TitleBlock('Title', centered: true).toPdf(theme),
      returnsNormally,
    );
  });
}
