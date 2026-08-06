import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';
import 'paragraph_block.dart';
import 'receipt_block.dart';
import 'refusal_clause_block.dart';

/// Standard memo acknowledgment footer: receipt + italic refusal clause +
/// quoted refusal text + Witness 1 / Witness 2 lines, matching the
/// canonical Luxium memo template.
class MemoAcknowledgmentBlock extends Block {
  const MemoAcknowledgmentBlock();

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        const ReceiptBlock([
          ReceiptField(label: 'Received by', caption: '(Name & Signature)'),
          ReceiptField(label: 'Date & Time Received'),
        ]).toPdf(theme),
        pw.SizedBox(height: 16),
        const RefusalClauseBlock(
          'If the employee refuses to sign, the server shall note the refusal below:',
        ).toPdf(theme),
        pw.SizedBox(height: 8),
        const ParagraphBlock(
          '"Served on ______ at ______. Employee refused to acknowledge receipt. Witnessed by:"',
        ).toPdf(theme),
        pw.SizedBox(height: 16),
        const ReceiptBlock([
          ReceiptField(label: 'Witness 1', caption: '(Name & Signature)'),
          ReceiptField(label: 'Witness 2', caption: '(Name & Signature)'),
        ]).toPdf(theme),
      ],
    );
  }
}
