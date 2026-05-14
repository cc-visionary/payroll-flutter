import 'package:flutter_test/flutter_test.dart';
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
}
