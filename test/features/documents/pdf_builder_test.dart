// test/features/documents/pdf_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/block.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';

class _StubBlock extends Block {
  final String text;
  const _StubBlock(this.text);
  @override
  pw.Widget toPdf(PdfTheme theme) => pw.Text(text);
}

void main() {
  test('buildDocumentPdf returns non-empty bytes for one block', () async {
    final theme = PdfTheme.testStub();
    final bytes = await buildDocumentPdf(
      blocks: [const _StubBlock('Hello')],
      theme: theme,
    );
    expect(bytes.length, greaterThan(100));
    // PDF magic header
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });

  test('buildDocumentPdf renders multiple blocks', () async {
    final theme = PdfTheme.testStub();
    final bytes = await buildDocumentPdf(
      blocks: [
        const _StubBlock('Block one'),
        const _StubBlock('Block two'),
        const _StubBlock('Block three'),
      ],
      theme: theme,
    );
    expect(bytes.length, greaterThan(100));
  });
}
