import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class SignatoryLine {
  final String? name;
  final String? role;
  const SignatoryLine({this.name, this.role});
}

/// Signature block in the "sign above the printed name" format: an empty
/// underline (the wet-signature space), the printed name below it, and the
/// role/title below the name in bold. Render either stacked (one per row)
/// or side-by-side ([row] = true, e.g. for witnesses). Name/role are
/// omitted when empty (blank line for hand-fill).
class SignatureLineBlock extends Block {
  final List<SignatoryLine> signatories;
  final bool row;
  final double lineWidth;
  const SignatureLineBlock(
    this.signatories, {
    this.row = false,
    this.lineWidth = 240,
  });

  pw.Widget _one(PdfTheme theme, SignatoryLine s) {
    final hasName = s.name != null && s.name!.trim().isNotEmpty;
    final hasRole = s.role != null && s.role!.trim().isNotEmpty;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        // Empty signature space with a bottom rule (the signature line).
        pw.Container(
          width: lineWidth,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
            ),
          ),
          child: pw.SizedBox(height: 24),
        ),
        pw.SizedBox(height: 3),
        if (hasName)
          pw.Text(
            s.name!,
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              color: theme.textColor,
            ),
          ),
        if (hasRole)
          pw.Text(
            s.role!,
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              fontWeight: pw.FontWeight.bold,
              color: theme.textColor,
            ),
          ),
      ],
    );
  }

  @override
  pw.Widget toPdf(PdfTheme theme) {
    if (row) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < signatories.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 32),
            pw.Expanded(child: _one(theme, signatories[i])),
          ],
        ],
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < signatories.length; i++) ...[
          if (i > 0) pw.SizedBox(height: 28),
          _one(theme, signatories[i]),
        ],
      ],
    );
  }
}
