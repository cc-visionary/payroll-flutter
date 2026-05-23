import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class EmphasisSpan {
  final String text;
  final bool bold;
  final bool italic;
  const EmphasisSpan(this.text, {this.bold = false, this.italic = false});
}

/// Paragraph with embedded bold spans, e.g. mid-paragraph emphasis on a
/// suspension memo's "PREVENTIVE SUSPENSION effective immediately"
/// callout.
class EmphasisParagraphBlock extends Block {
  final List<EmphasisSpan> spans;
  const EmphasisParagraphBlock({required this.spans});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.RichText(
      textAlign: pw.TextAlign.justify,
      text: pw.TextSpan(
        style: pw.TextStyle(
          fontSize: theme.bodySize,
          color: theme.textColor,
          lineSpacing: 1.5,
        ),
        children: [
          for (final s in spans)
            pw.TextSpan(
              text: s.text,
              style: pw.TextStyle(
                fontWeight:
                    s.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                fontStyle:
                    s.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
              ),
            ),
        ],
      ),
    );
  }
}
