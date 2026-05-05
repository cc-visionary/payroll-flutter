import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class HeadingBlock extends Block {
  final String text;
  const HeadingBlock(this.text);

  @override
  pw.Widget toPdf(PdfTheme theme) => pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: theme.headingSize,
          fontWeight: pw.FontWeight.bold,
          color: theme.textColor,
        ),
      );
}
