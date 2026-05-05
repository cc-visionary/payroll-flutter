import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class SpacerBlock extends Block {
  final double height;
  const SpacerBlock(this.height);
  @override
  pw.Widget toPdf(PdfTheme theme) => pw.SizedBox(height: height);
}
