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
    final rows = <pw.Widget>[];
    for (final item in items) {
      rows.add(_row(theme, item, nested: false));
      // One-level nesting: walk children; grandchildren are intentionally
      // not rendered. See spec §"New blocks" — Non-Reg sources have at
      // most 2 levels.
      for (final child in item.children) {
        rows.add(_row(theme, child, nested: true));
      }
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows,
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
