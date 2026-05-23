import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/centered_signature_block.dart';

void main() {
  test('stores caption', () {
    const b = CenteredSignatureBlock('Name and signature of Employee');
    expect(b.caption, 'Name and signature of Employee');
  });

  test('renders without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const CenteredSignatureBlock('Name and signature of Employee')
          .toPdf(theme),
      returnsNormally,
    );
  });
}
