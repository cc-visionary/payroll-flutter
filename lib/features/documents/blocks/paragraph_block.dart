import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class ParagraphBlock extends Block {
  final String text;
  final pw.TextAlign align;
  const ParagraphBlock(this.text, {this.align = pw.TextAlign.justify});

  @override
  pw.Widget toPdf(PdfTheme theme) => pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: theme.bodySize,
          color: theme.textColor,
          lineSpacing: 1.0,
        ),
      );
}
