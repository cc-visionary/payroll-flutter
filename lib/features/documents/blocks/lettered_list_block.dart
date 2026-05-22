import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Ordered list with lowercase-alpha markers (a. b. c. …). Past 26 items
/// it falls back to a 1-based number marker. Used by the Employment
/// Contract's Termination clause (grounds a-f).
class LetteredListBlock extends Block {
  final List<String> items;
  const LetteredListBlock(this.items);

  /// 0-based index → marker. 0→'a' … 25→'z', then 26→'27', 27→'28', …
  static String markerFor(int index) {
    if (index < 26) return String.fromCharCode('a'.codeUnitAt(0) + index);
    return '${index + 1}';
  }

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 22,
                  child: pw.Text(
                    '${markerFor(i)}.',
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
