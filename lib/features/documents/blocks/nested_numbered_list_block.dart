import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class NestedNumberedItem {
  final String leadBold;
  final String body;
  const NestedNumberedItem({required this.leadBold, required this.body});
}

/// Numbered list where each item starts with a bold lead phrase
/// followed by body text on the same line. Matches the
/// Acknowledgment & Repayment §8 pattern ("Immediate Payment Due: ...").
class NestedNumberedListBlock extends Block {
  final List<NestedNumberedItem> items;
  const NestedNumberedListBlock({required this.items});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 22,
                  child: pw.Text(
                    '${i + 1}.',
                    style: pw.TextStyle(
                      fontSize: theme.bodySize,
                      color: theme.textColor,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.RichText(
                    text: pw.TextSpan(
                      style: pw.TextStyle(
                        fontSize: theme.bodySize,
                        color: theme.textColor,
                      ),
                      children: [
                        pw.TextSpan(
                          text: '${items[i].leadBold}: ',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.TextSpan(text: items[i].body),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
