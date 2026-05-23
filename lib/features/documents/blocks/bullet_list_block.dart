import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class BulletListBlock extends Block {
  final List<String> items;
  const BulletListBlock(this.items);

  @override
  pw.Widget toPdf(PdfTheme theme) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final item in items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Bullet(
                text: item,
                style: pw.TextStyle(
                  fontSize: theme.bodySize,
                  color: theme.textColor,
                ),
              ),
            ),
        ],
      );
}
