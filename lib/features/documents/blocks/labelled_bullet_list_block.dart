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
    // Rendering implemented in Task 2.
    return pw.SizedBox.shrink();
  }
}
