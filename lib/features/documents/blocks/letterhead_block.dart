import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';
import 'company_header_block.dart';
import 'logo_block.dart';

/// Standard letterhead: optional left-aligned logo on top, then the company
/// name (bold) + address. Used by every non-memo template; memo templates fold
/// the logo into [MemoHeaderBlock] instead (which already draws the company line).
class LetterheadBlock extends Block {
  final Uint8List? logoBytes;
  final String companyName;
  final String? companyAddress;
  final double logoHeight;
  const LetterheadBlock({
    this.logoBytes,
    required this.companyName,
    this.companyAddress,
    this.logoHeight = 64,
  });

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null) ...[
          LogoBlock(logoBytes!, height: logoHeight).toPdf(theme),
          pw.SizedBox(height: 12),
        ],
        CompanyHeaderBlock(
          name: companyName,
          address: companyAddress,
        ).toPdf(theme),
      ],
    );
  }
}
