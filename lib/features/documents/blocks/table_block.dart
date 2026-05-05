import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Filled table with bold header row and bordered cells.
class TableBlock extends Block {
  final List<String> headers;
  final List<List<String>> rows;
  final List<double>? columnWidths;
  const TableBlock({
    required this.headers,
    required this.rows,
    this.columnWidths,
  });

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final widths = columnWidths;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
      columnWidths: widths == null
          ? null
          : {for (var i = 0; i < widths.length; i++) i: pw.FixedColumnWidth(widths[i])},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            for (final h in headers)
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  h,
                  style: pw.TextStyle(
                    fontSize: theme.bodySize,
                    fontWeight: pw.FontWeight.bold,
                    color: theme.textColor,
                  ),
                ),
              ),
          ],
        ),
        for (final row in rows)
          pw.TableRow(
            children: [
              for (final cell in row)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    cell,
                    style: pw.TextStyle(
                      fontSize: theme.bodySize,
                      color: theme.textColor,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
