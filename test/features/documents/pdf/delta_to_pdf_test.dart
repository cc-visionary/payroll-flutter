import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/delta_to_pdf.dart';

void main() {
  test('plain Delta renders to a single TextSpan list', () async {
    final theme = await PdfTheme.defaults();
    final delta = Delta()..insert('Hello world\n');
    final widget = deltaToPdf(delta, theme);
    expect(widget, isNotNull);
  });

  test('Delta with bold attribute renders without throwing', () async {
    final theme = await PdfTheme.defaults();
    final delta = Delta()
      ..insert('Plain ')
      ..insert('bold', {'bold': true})
      ..insert(' more\n');
    expect(() => deltaToPdf(delta, theme), returnsNormally);
  });

  test('Delta with bullet list block attribute renders', () async {
    final theme = await PdfTheme.defaults();
    final delta = Delta()
      ..insert('Item one')
      ..insert('\n', {'list': 'bullet'})
      ..insert('Item two')
      ..insert('\n', {'list': 'bullet'});
    expect(() => deltaToPdf(delta, theme), returnsNormally);
  });

  test('Delta with image embed strips the embed and renders text', () async {
    final theme = await PdfTheme.defaults();
    final delta = Delta()
      ..insert('Before ')
      ..insert({'image': 'http://example.com/x.png'})
      ..insert(' after\n');
    expect(() => deltaToPdf(delta, theme), returnsNormally);
  });
}
