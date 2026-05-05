import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';

void main() {
  group('PdfTheme.defaults', () {
    test('uses A4 page format and 25mm margin', () async {
      final theme = await PdfTheme.defaults();
      expect(theme.pageFormat, PdfPageFormat.a4);
      // 25mm margin in points: 25 * (72/25.4) ≈ 70.866
      expect(theme.pageMargin.left, closeTo(70.86, 0.1));
      expect(theme.pageMargin.top, closeTo(70.86, 0.1));
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
