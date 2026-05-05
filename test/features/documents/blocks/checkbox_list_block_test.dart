import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/checkbox_list_block.dart';

void main() {
  test('CheckboxListBlock stores items', () {
    const block = CheckboxListBlock([
      CheckboxItem(label: 'Lump Sum Payment', body: 'Pay full amount...'),
      CheckboxItem(label: 'Salary Deductions', body: 'Repay through...'),
    ]);
    expect(block.items.length, 2);
    expect(block.items[0].label, 'Lump Sum Payment');
  });

  test('renders without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const CheckboxListBlock(
        [CheckboxItem(label: 'A', body: 'b')],
      ).toPdf(theme),
      returnsNormally,
    );
  });
}
