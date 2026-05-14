import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/labelled_bullet_list_block.dart';

void main() {
  test('LabelledBulletListBlock stores items', () {
    const block = LabelledBulletListBlock(items: [
      LabelledBulletItem(leadBold: 'Standard', body: 'The standard body.'),
      LabelledBulletItem(leadBold: 'Finding', body: 'The finding body.'),
    ]);
    expect(block.items.length, 2);
    expect(block.items.first.leadBold, 'Standard');
    expect(block.items.first.body, 'The standard body.');
    expect(block.items.first.children, isEmpty);
  });

  test('LabelledBulletItem holds nested children', () {
    const item = LabelledBulletItem(
      leadBold: 'Finding',
      body: 'Parent finding.',
      children: [
        LabelledBulletItem(leadBold: 'Detail A', body: 'Body A.'),
        LabelledBulletItem(leadBold: 'Detail B', body: 'Body B.'),
      ],
    );
    expect(item.children.length, 2);
    expect(item.children[0].leadBold, 'Detail A');
  });

  test('flat list renders without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const LabelledBulletListBlock(items: [
        LabelledBulletItem(leadBold: 'Standard', body: 'Body 1'),
        LabelledBulletItem(leadBold: 'Finding', body: 'Body 2'),
      ]).toPdf(theme),
      returnsNormally,
    );
  });

  test('flat list produces a Column with one row per top-level item', () {
    final theme = PdfTheme.testStub();
    final widget = const LabelledBulletListBlock(items: [
      LabelledBulletItem(leadBold: 'A', body: 'a'),
      LabelledBulletItem(leadBold: 'B', body: 'b'),
      LabelledBulletItem(leadBold: 'C', body: 'c'),
    ]).toPdf(theme);
    expect(widget, isA<pw.Column>());
    final col = widget as pw.Column;
    expect(col.children.length, 3);
  });

  test('nested children flatten into the column under the parent', () {
    final theme = PdfTheme.testStub();
    final widget = const LabelledBulletListBlock(items: [
      LabelledBulletItem(
        leadBold: 'Finding',
        body: 'Parent body.',
        children: [
          LabelledBulletItem(leadBold: 'Sub A', body: 'a'),
          LabelledBulletItem(leadBold: 'Sub B', body: 'b'),
        ],
      ),
    ]).toPdf(theme);
    final col = widget as pw.Column;
    // 1 parent row + 2 child rows = 3 entries.
    expect(col.children.length, 3);
  });

  test('depth-2 grandchildren are ignored (one-level nesting limit)', () {
    final theme = PdfTheme.testStub();
    final widget = const LabelledBulletListBlock(items: [
      LabelledBulletItem(
        leadBold: 'Finding',
        body: 'Parent.',
        children: [
          LabelledBulletItem(
            leadBold: 'Sub A',
            body: 'a',
            // These deeper-level children must NOT appear in output.
            children: [
              LabelledBulletItem(leadBold: 'Deeper', body: 'd'),
            ],
          ),
        ],
      ),
    ]).toPdf(theme);
    final col = widget as pw.Column;
    // 1 parent + 1 child = 2 entries; grandchild dropped.
    expect(col.children.length, 2);
  });
}
