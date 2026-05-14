import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class LabelledBulletItem {
  final String leadBold;
  final String body;
  final List<LabelledBulletItem> children;
  const LabelledBulletItem({
    required this.leadBold,
    required this.body,
    this.children = const [],
  });
}

/// Bullet list where each item has a bold lead label followed by a plain
/// body span. Supports ONE level of nested sub-bullets (rendered with the
/// `○` glyph). Used by Non-Reg findings sections, and reusable by other
/// memo-style HR templates with the same pattern.
class LabelledBulletListBlock extends Block {
  final List<LabelledBulletItem> items;
  const LabelledBulletListBlock({required this.items});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final item in items) _row(theme, item, nested: false),
      ],
    );
  }

  pw.Widget _row(PdfTheme theme, LabelledBulletItem item,
      {required bool nested}) {
    final glyph = nested ? '○' : '•';
    final indent = nested ? 36.0 : 12.0;
    return pw.Padding(
      padding: pw.EdgeInsets.only(left: indent, bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 14,
            child: pw.Text(
              glyph,
              style: pw.TextStyle(
                fontSize: theme.bodySize,
                color: theme.textColor,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: pw.TextStyle(
                  fontSize: theme.bodySize,
                  color: theme.textColor,
                ),
                children: [
                  pw.TextSpan(
                    text: '${item.leadBold}: ',
                    style:
                        pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.TextSpan(text: item.body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
