import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/bullet_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/numbered_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/nested_numbered_list_block.dart';

void main() {
  test('BulletListBlock stores items', () {
    const block = BulletListBlock(['a', 'b', 'c']);
    expect(block.items, ['a', 'b', 'c']);
  });

  test('NumberedListBlock stores items', () {
    const block = NumberedListBlock(['one', 'two']);
    expect(block.items, ['one', 'two']);
  });

  test('NestedNumberedListBlock stores items + children', () {
    const block = NestedNumberedListBlock(
      items: [
        NestedNumberedItem(
          leadBold: 'Immediate Payment Due',
          body: 'The remaining...',
        ),
        NestedNumberedItem(leadBold: 'Legal Action', body: 'If the...'),
      ],
    );
    expect(block.items.length, 2);
    expect(block.items.first.leadBold, 'Immediate Payment Due');
  });

  test('blocks render without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const BulletListBlock(['a', 'b']).toPdf(theme),
      returnsNormally,
    );
    expect(
      () => const NumberedListBlock(['x', 'y']).toPdf(theme),
      returnsNormally,
    );
    expect(
      () => const NestedNumberedListBlock(
        items: [NestedNumberedItem(leadBold: 'L', body: 'b')],
      ).toPdf(theme),
      returnsNormally,
    );
  });
}
