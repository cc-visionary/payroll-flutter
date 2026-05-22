import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/lettered_list_block.dart';

void main() {
  test('stores items', () {
    const b = LetteredListBlock(['first', 'second', 'third']);
    expect(b.items.length, 3);
    expect(b.items.first, 'first');
  });

  test('marker for index: a, b, c', () {
    expect(LetteredListBlock.markerFor(0), 'a');
    expect(LetteredListBlock.markerFor(1), 'b');
    expect(LetteredListBlock.markerFor(25), 'z');
  });

  test('marker past 26 falls back to 1-based number', () {
    expect(LetteredListBlock.markerFor(26), '27');
    expect(LetteredListBlock.markerFor(30), '31');
  });

  test('renders a Column with one entry per item', () {
    final theme = PdfTheme.testStub();
    final w = const LetteredListBlock(['a', 'b', 'c']).toPdf(theme);
    expect(w, isA<pw.Column>());
    expect((w as pw.Column).children.length, 3);
  });

  test('renders without throwing', () {
    final theme = PdfTheme.testStub();
    expect(() => const LetteredListBlock(['x']).toPdf(theme), returnsNormally);
  });
}
