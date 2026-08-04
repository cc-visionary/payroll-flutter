import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class SignatureBlock extends Block {
  final String? name;
  final String? role;
  final DateTime? date;
  /// Transparent-PNG signature rendered above the printed name, sitting on
  /// the sign line. Company-side signatories only.
  final Uint8List? signatureImage;
  const SignatureBlock({this.name, this.role, this.date, this.signatureImage});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final fmt = DateFormat('MMMM d, yyyy');
    final dateLine = date == null
        ? 'Date: _______________________'
        : 'Date: ${fmt.format(date!)}';
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
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (signatureImage != null)
                pw.Container(
                  height: 40,
                  alignment: pw.Alignment.bottomLeft,
                  child: pw.Image(pw.MemoryImage(signatureImage!),
                      height: 38, fit: pw.BoxFit.contain),
                ),
              pw.Text(
                name ?? '',
                style: pw.TextStyle(
                  fontSize: theme.bodySize,
                  fontWeight: pw.FontWeight.bold,
                  color: theme.textColor,
                ),
              ),
            ],
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
          dateLine,
          style: pw.TextStyle(
            fontSize: theme.bodySize,
            color: theme.textColor,
          ),
        ),
      ],
    );
  }
}
