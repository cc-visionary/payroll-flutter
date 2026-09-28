import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';
import 'emphasis_paragraph_block.dart';

class BulletListBlock extends Block {
  final List<String> items;

  /// Items rendered AFTER [items] that carry inline emphasis (e.g. a bold
  /// "condition of employment"). They get the exact same bullet as the plain
  /// items — a typed "•" glyph is smaller and sits further left.
  final List<List<EmphasisSpan>> richItems;
  const BulletListBlock(this.items, {this.richItems = const []});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final style = pw.TextStyle(fontSize: theme.bodySize, color: theme.textColor);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final item in items)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Bullet(text: item, style: style),
          ),
        for (final spans in richItems)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: _RichBullet(spans: spans, style: style),
          ),
      ],
    );
  }
}

/// `pw.Bullet` with a rich-text body. Mirrors pdf 3.12.0's `Bullet.build`
/// (same margin, bullet size, bullet margin and `bulletStyle` merge) so a rich
/// item is indistinguishable from a plain one apart from its emphasis.
class _RichBullet extends pw.StatelessWidget {
  _RichBullet({required this.spans, required this.style});

  final List<EmphasisSpan> spans;
  final pw.TextStyle style;

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 2.0 * PdfPageFormat.mm),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 2.0 * PdfPageFormat.mm,
            height: 2.0 * PdfPageFormat.mm,
            margin: const pw.EdgeInsets.only(
              top: 1.5 * PdfPageFormat.mm,
              left: 5.0 * PdfPageFormat.mm,
              right: 2.0 * PdfPageFormat.mm,
            ),
            decoration: const pw.BoxDecoration(
              color: PdfColors.black,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: pw.Theme.of(context).bulletStyle.merge(style),
                children: [
                  for (final s in spans)
                    pw.TextSpan(
                      text: s.text,
                      style: pw.TextStyle(
                        fontWeight: s.bold
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                        fontStyle: s.italic
                            ? pw.FontStyle.italic
                            : pw.FontStyle.normal,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
