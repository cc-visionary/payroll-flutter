import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';
import 'company_header_block.dart';
import 'letter_meta_block.dart';
import 'logo_block.dart';
import 'paragraph_block.dart';
import 'title_block.dart';

/// Standard memo header: title + company + horizontal rules around the
/// Date/To/From/Subject block + optional salutation. Composes existing
/// primitives so any other memo-style template gets the exact same
/// look.
class MemoHeaderBlock extends Block {
  final String titleText;
  final String companyName;
  final String? companyAddress;
  final DateTime date;
  final LetterParty to;
  final LetterParty from;
  final String subject;
  final String? salutation;
  final Uint8List? logoBytes;

  const MemoHeaderBlock({
    required this.titleText,
    required this.companyName,
    this.companyAddress,
    required this.date,
    required this.to,
    required this.from,
    required this.subject,
    this.salutation,
    this.logoBytes,
  });

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (logoBytes != null) ...[
          LogoBlock(logoBytes!, height: 64).toPdf(theme),
          pw.SizedBox(height: 12),
        ],
        TitleBlock(titleText).toPdf(theme),
        pw.SizedBox(height: 12),
        CompanyHeaderBlock(
          name: companyName,
          address: companyAddress,
        ).toPdf(theme),
        pw.SizedBox(height: 12),
        LetterMetaBlock(
          date: date,
          to: to,
          from: from,
          subject: subject,
        ).toPdf(theme),
        if (salutation != null && salutation!.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          ParagraphBlock('Dear $salutation,').toPdf(theme),
        ],
      ],
    );
  }
}
