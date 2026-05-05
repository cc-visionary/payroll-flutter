import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class NumberedListBlock extends Block {
  final List<String> items;
  const NumberedListBlock(this.items);

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
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
                  child: pw.Text(
                    items[i],
                    style: pw.TextStyle(
                      fontSize: theme.bodySize,
                      color: theme.textColor,
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
