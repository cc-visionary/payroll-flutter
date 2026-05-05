import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class KeyValueRow {
  final String label;
  final String value;
  const KeyValueRow(this.label, this.value);
}

/// Two-column aligned label/value list. Label column is bold and a
/// fixed width so values align across rows.
class KeyValueBlock extends Block {
  final List<KeyValueRow> rows;
  final double labelWidth;
  const KeyValueBlock(this.rows, {this.labelWidth = 110});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: labelWidth,
                  child: pw.Text(
                    '${r.label}:',
                    style: pw.TextStyle(
                      fontSize: theme.bodySize,
                      fontWeight: pw.FontWeight.bold,
                      color: theme.textColor,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    r.value,
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
