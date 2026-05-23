import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';

/// Single shared theme so all generated PDFs in the app render as one
/// visual family. PDFs are intentionally black-on-white — no Luxium
/// purple, since these are legal documents.
class PdfTheme {
  final pw.ThemeData fontTheme;
  final PdfPageFormat pageFormat;
  final pw.EdgeInsets pageMargin;
  final double titleSize;
  final double headingSize;
  final double bodySize;
  final PdfColor textColor;
  final bool showPageNumbers;
  final double footerFontSize;
  final pw.EdgeInsets footerMargin;
  final double footerHeight;

  const PdfTheme({
    required this.fontTheme,
    required this.pageFormat,
    required this.pageMargin,
    required this.titleSize,
    required this.headingSize,
    required this.bodySize,
    required this.textColor,
    required this.showPageNumbers,
    required this.footerFontSize,
    required this.footerMargin,
    required this.footerHeight,
  });

  /// Default theme used by document templates. Page format A4, Inter Light
  /// body / SemiBold bold, page numbers always on.
  ///
  /// Margins: top/left/right are 0.75 inch (54pt). The bottom margin is 0;
  /// the bottom 0.75 inch of whitespace is instead supplied by a
  /// fixed-height footer band (see [footerHeight]). `pw.MultiPage` computes
  /// the content's bottom boundary as `margin.bottom + footerHeight`, so
  /// `0 + 54 = 54pt` makes the content-to-edge bottom exactly 0.75 inch,
  /// matching the other three sides, while the page number sits inside that
  /// bottom margin band.
  ///
  /// 0.75 inch in PDF points is 54 (1in = 72pt).
  static Future<PdfTheme> defaults() async {
    return PdfTheme(
      fontTheme: await loadInterTheme(),
      pageFormat: PdfPageFormat.a4,
      pageMargin: const pw.EdgeInsets.fromLTRB(54, 54, 54, 0),
      titleSize: 22,
      headingSize: 14,
      bodySize: 11,
      textColor: PdfColors.black,
      showPageNumbers: true,
      footerFontSize: 9,
      footerMargin: const pw.EdgeInsets.only(bottom: 22),
      footerHeight: 54,
    );
  }

  /// Synchronous theme suitable for tests — avoids fetching Inter from
  /// Google Fonts (which races and times out under flutter_test). Uses
  /// the built-in Helvetica family. **Do not use in production code.**
  static PdfTheme testStub() {
    return PdfTheme(
      fontTheme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
      pageFormat: PdfPageFormat.a4,
      pageMargin: const pw.EdgeInsets.fromLTRB(54, 54, 54, 0),
      titleSize: 22,
      headingSize: 14,
      bodySize: 11,
      textColor: PdfColors.black,
      showPageNumbers: true,
      footerFontSize: 9,
      footerMargin: const pw.EdgeInsets.only(bottom: 22),
      footerHeight: 54,
    );
  }
}
