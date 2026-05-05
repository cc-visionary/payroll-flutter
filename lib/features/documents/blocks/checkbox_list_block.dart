import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class CheckboxItem {
  final String label;
  final String body;
  const CheckboxItem({required this.label, required this.body});
}

/// Empty checkbox + bold label + body. Designed for printed forms where
/// the recipient ticks one option (e.g., Acknowledgment & Repayment §3
/// "Repayment Options").
class CheckboxListBlock extends Block {
  final List<CheckboxItem> items;
  const CheckboxListBlock(this.items);

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final item in items)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 12,
                  height: 12,
                  margin: const pw.EdgeInsets.only(top: 2, right: 8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                      color: PdfColors.grey700,
                      width: 0.7,
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
                          text: '${item.label}: ',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.TextSpan(text: item.body),
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
