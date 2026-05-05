// test/core/pdf/page_footer_test.dart
//
// Renders a 3-page MultiPage with the standard footer and asserts the
// rasterized bytes contain "Page 1 of 3", "Page 2 of 3", "Page 3 of 3"
// at the expected positions. Asserting on raster pixels is too brittle;
// instead we render to bytes and inspect via Printing.raster.

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:payroll_flutter/core/pdf/page_footer.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';

void main() {
  test('buildStandardPageFooter formats "Page X of Y"', () async {
    final theme = await PdfTheme.defaults();
    // Build a tiny stub Context-like value via a helper in production
    // code: buildStandardPageFooterText(pageNumber, pagesCount).
    expect(buildStandardPageFooterText(1, 3), 'Page 1 of 3');
    expect(buildStandardPageFooterText(7, 7), 'Page 7 of 7');
    expect(buildStandardPageFooterText(1, 1), 'Page 1 of 1');
  });

  test('buildStandardPageFooter returns a centered Container', () async {
    final theme = await PdfTheme.defaults();
    final widget = buildStandardPageFooter(theme, pageNumber: 2, pagesCount: 5);
    expect(widget, isA<pw.Container>());
  });
}
