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
    final style = pw.TextStyle(
      fontSize: theme.titleSize,
      fontWeight: pw.FontWeight.bold,
      color: theme.textColor,
    );
    if (centered) {
      return pw.SizedBox(
        width: double.infinity,
        child: pw.Text(text, textAlign: pw.TextAlign.center, style: style),
      );
    }
    return pw.Text(text, style: style);
  }
}
