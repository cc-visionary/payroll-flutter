import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';
import 'emphasis_paragraph_block.dart';

/// A left-indented party description used in the Employment Contract
/// preamble (EMPLOYER / EMPLOYEE blocks). Renders [spans] (supporting
/// bold party name + italic address) inside a left-indented container to
/// match the source contract's block-quote layout.
class PartyBlock extends Block {
  final List<EmphasisSpan> spans;
  final double leftIndent;
  const PartyBlock({required this.spans, this.leftIndent = 110});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(left: leftIndent),
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(
            fontSize: theme.bodySize,
            color: theme.textColor,
            lineSpacing: 2,
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
      ),
    );
  }
}
