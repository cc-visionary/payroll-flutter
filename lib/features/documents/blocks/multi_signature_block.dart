import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class SignatoryParty {
  final String? name;
  final String? role;
  final DateTime? date;
  const SignatoryParty({this.name, this.role, this.date});
}

class MultiSignatureBlock extends Block {
  final List<SignatoryParty> signatories;
  const MultiSignatureBlock(this.signatories);

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final fmt = DateFormat('MMMM d, yyyy');
    pw.Widget one(SignatoryParty s) => pw.Column(
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
                s.name ?? '',
                style: pw.TextStyle(
                  fontSize: theme.bodySize,
                  color: theme.textColor,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            if (s.role != null && s.role!.isNotEmpty)
              pw.Text(
                s.role!,
                style: pw.TextStyle(
                  fontSize: theme.bodySize,
                  fontWeight: pw.FontWeight.bold,
                  color: theme.textColor,
                ),
              ),
            if (s.date != null)
              pw.Text(
                'Date: ${fmt.format(s.date!)}',
                style: pw.TextStyle(
                  fontSize: theme.bodySize,
                  color: theme.textColor,
                ),
              ),
          ],
        );
    return pw.Wrap(
      spacing: 40,
      runSpacing: 24,
      children: [for (final s in signatories) one(s)],
    );
  }
}
