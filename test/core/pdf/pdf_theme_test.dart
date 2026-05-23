import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';

void main() {
  group('PdfTheme.defaults', () {
    test('uses A4 page format and 0.75in margin', () async {
      final theme = await PdfTheme.defaults();
      expect(theme.pageFormat, PdfPageFormat.a4);
      // 0.75in margin in points: 0.75 * 72 = 54
      expect(theme.pageMargin.left, closeTo(54, 0.1));
      expect(theme.pageMargin.top, closeTo(54, 0.1));
      expect(theme.pageMargin.right, closeTo(54, 0.1));
      // Bottom page margin is 0; the bottom 0.75in is supplied by the
      // fixed-height footer band so MultiPage's content-to-edge bottom
      // (margin.bottom + footerHeight = 0 + 54) equals 0.75in.
      expect(theme.pageMargin.bottom, closeTo(0, 0.1));
      expect(theme.footerHeight, closeTo(54, 0.1));
    });

    test('default sizes match spec', () async {
      final theme = await PdfTheme.defaults();
      expect(theme.titleSize, 22);
      expect(theme.headingSize, 14);
      expect(theme.bodySize, 11);
      expect(theme.footerFontSize, 9);
    });

    test('page numbers enabled by default', () async {
      final theme = await PdfTheme.defaults();
      expect(theme.showPageNumbers, true);
    });
  });
}
