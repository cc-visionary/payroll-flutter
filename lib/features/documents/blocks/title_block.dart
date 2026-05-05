import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Large bold title. Defaults to left-aligned to match the canonical
/// Luxium memo style; pass `centered: true` for a centered header.
class TitleBlock extends Block {
  final String text;
  final bool centered;
  const TitleBlock(this.text, {this.centered = false});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Container(
      alignment: centered ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: theme.titleSize,
          fontWeight: pw.FontWeight.bold,
          color: theme.textColor,
        ),
      ),
    );
  }
}
