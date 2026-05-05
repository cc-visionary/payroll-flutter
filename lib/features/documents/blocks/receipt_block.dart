import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class ReceiptField {
  final String label;
  final String? caption;
  const ReceiptField({required this.label, this.caption});
}

class ReceiptBlock extends Block {
  final List<ReceiptField> fields;
  const ReceiptBlock(this.fields);

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final f in fields)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '${f.label}: ',
                      style: pw.TextStyle(
                        fontSize: theme.bodySize,
                        fontWeight: pw.FontWeight.bold,
                        color: theme.textColor,
                      ),
                    ),
                    pw.Container(
                      width: 240,
                      padding: const pw.EdgeInsets.only(bottom: 1),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.black,
                            width: 0.7,
                          ),
                        ),
                      ),
                      child: pw.SizedBox(height: 12),
                    ),
                  ],
                ),
                if (f.caption != null && f.caption!.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 90, top: 2),
                    child: pw.Text(
                      f.caption!,
                      style: pw.TextStyle(
                        fontSize: theme.footerFontSize,
                        color: PdfColors.grey700,
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
