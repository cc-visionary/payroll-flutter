// lib/core/pdf/page_footer.dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_theme.dart';

/// Format a page-number footer string. Extracted so unit tests can
/// assert the format without rasterizing a full PDF.
String buildStandardPageFooterText(int pageNumber, int pagesCount) =>
    'Page $pageNumber of $pagesCount';

/// Standard "Page X of Y" footer for `pw.MultiPage.footer`. Bottom-center,
/// 9pt grey, sized + positioned per [PdfTheme]. Designed to be reused by
/// any feature that builds PDFs with shared theming.
pw.Widget buildStandardPageFooter(
  PdfTheme theme, {
  required int pageNumber,
  required int pagesCount,
}) {
  return pw.Container(
    alignment: pw.Alignment.center,
    margin: theme.footerMargin,
    child: pw.Text(
      buildStandardPageFooterText(pageNumber, pagesCount),
      style: pw.TextStyle(
        fontSize: theme.footerFontSize,
        color: PdfColors.grey700,
      ),
    ),
  );
}
