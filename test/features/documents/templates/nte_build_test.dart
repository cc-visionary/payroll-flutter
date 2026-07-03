import 'dart:typed_data';

import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/memo_header_block.dart';
import 'package:payroll_flutter/features/documents/blocks/memo_acknowledgment_block.dart';
import 'package:payroll_flutter/features/documents/blocks/section_heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/rich_text_block.dart';
import 'package:payroll_flutter/features/documents/blocks/bullet_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/image_attachment_block.dart';
import 'package:payroll_flutter/features/documents/blocks/page_break_block.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nte_template.dart';

void main() {
  NteInputs valid() => NteInputs(
        employeeId: 'e1',
        employeeFullName: 'Orlando Del Prado',
        employeeFirstName: 'Orlando',
        employeeLastName: 'Del Prado',
        employeePosition: 'Sales Associate',
        employeeDepartment: 'LCT Kiosk',
        companyId: 'c1',
        companyName: 'LUXIUM TRADING CO.',
        hrManagerName: 'Brixter Del Mundo',
        dateIssued: DateTime(2026, 4, 27),
        responseDeadline: DateTime(2026, 5, 2),
        subjectSubtopic: 'Theft Investigation',
        charges: [
          NteCharge(
            title: 'Unauthorized cash withdrawal',
            body: Delta()..insert('Body of charge.\n'),
          ),
        ],
        applicableViolations: ['Code of Conduct §3.1'],
      );

  test('build starts with MemoHeaderBlock', () {
    const t = NteTemplate();
    final blocks = t.build(valid());
    expect(blocks.first, isA<MemoHeaderBlock>());
  });

  test('build ends with MemoAcknowledgmentBlock', () {
    const t = NteTemplate();
    final blocks = t.build(valid());
    expect(blocks.last, isA<MemoAcknowledgmentBlock>());
  });

  test('each charge generates SectionHeadingBlock + RichTextBlock', () {
    const t = NteTemplate();
    final blocks = t.build(valid().copyWith(charges: [
      NteCharge(title: 'A', body: Delta()..insert('a\n')),
      NteCharge(title: 'B', body: Delta()..insert('b\n')),
    ]));
    final headings =
        blocks.whereType<SectionHeadingBlock>().toList();
    final richTexts = blocks.whereType<RichTextBlock>().toList();
    expect(headings.length, 2);
    expect(richTexts.length, 2);
    expect(headings[0].number, 1);
    expect(headings[1].number, 2);
  });

  test('build includes BulletListBlock with violations', () {
    const t = NteTemplate();
    final blocks = t.build(valid());
    final bullets = blocks.whereType<BulletListBlock>().first;
    expect(bullets.items, contains('Code of Conduct §3.1'));
  });

  test('build: MemoHeaderBlock is first and carries logoBytes when set', () {
    final blocks = const NteTemplate().build(valid().copyWith(
      logoBytes: Uint8List.fromList(const [137, 80, 78, 71]),
    ));
    expect(blocks.first, isA<MemoHeaderBlock>());
    expect((blocks.first as MemoHeaderBlock).logoBytes, isNotNull);
  });

  test('no attachment block when attachmentBytes is null', () {
    const t = NteTemplate();
    final blocks = t.build(valid());
    expect(blocks.whereType<ImageAttachmentBlock>(), isEmpty);
    expect(blocks.whereType<PageBreakBlock>(), isEmpty);
  });

  test('appends attachment section when attachmentBytes is set', () {
    const t = NteTemplate();
    final blocks = t.build(valid().copyWith(
      attachmentBytes: Uint8List.fromList([1, 2, 3]),
      attachmentCaption: 'Evidence photo',
    ));
    final img = blocks.whereType<ImageAttachmentBlock>().toList();
    expect(img.length, 1);
    expect(img.first.caption, 'Evidence photo');
    expect(blocks.whereType<PageBreakBlock>().length, 1);
    expect(
      blocks.whereType<HeadingBlock>().any((h) => h.text == 'Annex A'),
      isTrue,
    );
  });
}
