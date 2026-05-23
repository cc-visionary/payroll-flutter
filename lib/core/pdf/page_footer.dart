// lib/core/pdf/page_footer.dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_theme.dart';

/// Format a page-number footer string. Extracted so unit tests can
/// assert the format without rasterizing a full PDF.
String buildStandardPageFooterText(int pageNumber, int pagesCount) =>
    'Page $pageNumber of $pagesCount';

/// Standard "Page X of Y" footer for `pw.MultiPage.footer`. A fixed-height
/// band ([PdfTheme.footerHeight], 0.75in) with the page number bottom-center,
/// 9pt grey, padded by [PdfTheme.footerMargin] so it sits ~0.3in from the
/// page bottom edge. The fixed height is what `pw.MultiPage` adds to the
/// content boundary, making the content-to-edge bottom equal 0.75in (the
/// page bottom margin is 0). Designed to be reused by any feature that
/// builds PDFs with shared theming.
pw.Widget buildStandardPageFooter(
  PdfTheme theme, {
  required int pageNumber,
  required int pagesCount,
}) {
  return pw.Container(
    height: theme.footerHeight,
    alignment: pw.Alignment.bottomCenter,
    padding: theme.footerMargin,
    child: pw.Text(
      buildStandardPageFooterText(pageNumber, pagesCount),
      style: pw.TextStyle(
        fontSize: theme.footerFontSize,
        color: PdfColors.grey700,
      ),
    ),
  );
}
