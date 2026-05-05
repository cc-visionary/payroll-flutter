import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Cached Inter theme for app PDFs. Identical to the theme used by the
/// payslip pipeline so generated documents stay visually consistent
/// across features.
///
/// `PdfGoogleFonts` caches font bytes after the first fetch; once this
/// function has resolved successfully on a given host, every subsequent
/// PDF render is offline.
pw.ThemeData? _cachedInterTheme;

Future<pw.ThemeData> loadInterTheme() async {
  final cached = _cachedInterTheme;
  if (cached != null) return cached;
  final base = await PdfGoogleFonts.interLight();
  final bold = await PdfGoogleFonts.interSemiBold();
  final italic = await PdfGoogleFonts.interLightItalic();
  final boldItalic = await PdfGoogleFonts.interSemiBoldItalic();
  final theme = pw.ThemeData.withFont(
    base: base,
    bold: bold,
    italic: italic,
    boldItalic: boldItalic,
  );
  _cachedInterTheme = theme;
  return theme;
}

/// Test-only hook to reset the cache between integration runs.
void debugResetInterThemeCache() {
  _cachedInterTheme = null;
}
