import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Table with empty rows for hand-fill on the printed document. Used by
/// the Acknowledgment & Repayment doc's "Reason for Deduction" table.
class FillableTableBlock extends Block {
  final List<String> headers;
  final int blankRows;
  final List<double>? columnWidths;
  const FillableTableBlock({
    required this.headers,
    required this.blankRows,
    this.columnWidths,
  });

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final widths = columnWidths;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
      columnWidths: widths == null
          ? null
          : {
              for (var i = 0; i < widths.length; i++)
                i: pw.FixedColumnWidth(widths[i]),
            },
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
        for (var i = 0; i < blankRows; i++)
          pw.TableRow(
            children: [
              for (var j = 0; j < headers.length; j++) pw.SizedBox(height: 22),
            ],
          ),
      ],
    );
  }
}
