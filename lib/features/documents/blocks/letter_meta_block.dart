import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class LetterParty {
  final String name;
  final String? subtitle;
  const LetterParty({required this.name, this.subtitle});
}

/// Date / To / From / Subject section with a thin divider above and
/// below. Used inside `MemoHeaderBlock` and reusable by any letter-style
/// document that needs the same metadata header.
class LetterMetaBlock extends Block {
  final DateTime date;
  final LetterParty to;
  final LetterParty from;
  final String subject;
  const LetterMetaBlock({
    required this.date,
    required this.to,
    required this.from,
    required this.subject,
  });

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final formatter = DateFormat('MMMM d, yyyy');
    final divider = pw.Divider(color: PdfColors.grey400, height: 1);

    pw.Widget label(String text) => pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: theme.bodySize,
            fontWeight: pw.FontWeight.bold,
            color: theme.textColor,
          ),
        );
    pw.Widget value(String text) => pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: theme.bodySize,
            color: theme.textColor,
          ),
        );
    pw.Widget partyValue(LetterParty p) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            value(p.name),
            if (p.subtitle != null && p.subtitle!.isNotEmpty)
              value(p.subtitle!),
          ],
        );
    pw.Widget row(String l, pw.Widget v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 70, child: label(l)),
              pw.Expanded(child: v),
            ],
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        divider,
        pw.SizedBox(height: 12),
        row('Date:', value(formatter.format(date))),
        row('To:', partyValue(to)),
        row('From:', partyValue(from)),
        row('Subject:', value(subject)),
        divider,
      ],
    );
  }
}
