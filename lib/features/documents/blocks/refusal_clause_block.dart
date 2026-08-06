import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Italicized small-print clause used in the standard memo
/// acknowledgment footer (e.g., "If the employee refuses to sign...").
class RefusalClauseBlock extends Block {
  final String text;
  const RefusalClauseBlock(this.text);

  @override
  pw.Widget toPdf(PdfTheme theme) => pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: theme.bodySize - 1,
      fontStyle: pw.FontStyle.italic,
      color: theme.textColor,
    ),
  );
}
