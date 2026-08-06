import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/emphasis_paragraph_block.dart';

void main() {
  test('ParagraphBlock renders with body size', () {
    final theme = PdfTheme.testStub();
    const block = ParagraphBlock('Hello world.');
    expect(() => block.toPdf(theme), returnsNormally);
  });

  test('EmphasisParagraphBlock accepts Spans with bold flag', () {
    const block = EmphasisParagraphBlock(
      spans: [
        EmphasisSpan('Plain text. '),
        EmphasisSpan('Bold inline.', bold: true),
        EmphasisSpan(' Trailing.'),
      ],
    );
    expect(block.spans.length, 3);
    expect(block.spans[1].bold, true);
  });

  test('EmphasisSpan italic defaults false; bold-only still works', () {
    const a = EmphasisSpan('x');
    const b = EmphasisSpan('y', bold: true);
    const c = EmphasisSpan('z', italic: true);
    expect(a.italic, false);
    expect(a.bold, false);
    expect(b.bold, true);
    expect(c.italic, true);
  });

  test('EmphasisParagraphBlock renders with italic span without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const EmphasisParagraphBlock(
        spans: [EmphasisSpan('plain '), EmphasisSpan('italic', italic: true)],
      ).toPdf(theme),
      returnsNormally,
    );
  });
}
