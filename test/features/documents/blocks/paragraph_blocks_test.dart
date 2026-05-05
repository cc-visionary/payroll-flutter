import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/emphasis_paragraph_block.dart';

void main() {
  test('ParagraphBlock renders with body size', () async {
    final theme = await PdfTheme.defaults();
    const block = ParagraphBlock('Hello world.');
    expect(() => block.toPdf(theme), returnsNormally);
  });

  test('EmphasisParagraphBlock accepts Spans with bold flag', () {
    const block = EmphasisParagraphBlock(spans: [
      EmphasisSpan('Plain text. '),
      EmphasisSpan('Bold inline.', bold: true),
      EmphasisSpan(' Trailing.'),
    ]);
    expect(block.spans.length, 3);
    expect(block.spans[1].bold, true);
  });
}
