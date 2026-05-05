import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class SignatureBlock extends Block {
  final String? name;
  final String? role;
  final DateTime date;
  const SignatureBlock({this.name, this.role, required this.date});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final fmt = DateFormat('MMMM d, yyyy');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 220,
          padding: const pw.EdgeInsets.only(bottom: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
            ),
          ),
          child: pw.Text(
            name ?? '',
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              color: theme.textColor,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        if (role != null && role!.isNotEmpty)
          pw.Text(
            role!,
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              fontWeight: pw.FontWeight.bold,
              color: theme.textColor,
            ),
          ),
        pw.Text(
          'Date: ${fmt.format(date)}',
          style: pw.TextStyle(
            fontSize: theme.bodySize,
            color: theme.textColor,
          ),
        ),
      ],
    );
  }
}
