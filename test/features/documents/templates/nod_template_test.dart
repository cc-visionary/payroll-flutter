import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/memo_header_block.dart';
import 'package:payroll_flutter/features/documents/blocks/image_attachment_block.dart';
import 'package:payroll_flutter/features/documents/blocks/page_break_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_template.dart';

NodInputs _i({NodDecision d = NodDecision.writtenWarning, int days = 0}) =>
    NodInputs(
      employeeId: 'e1',
      employeeFullName: 'Bob',
      employeePosition: 'Dev',
      companyId: 'c1',
      companyName: 'X',
      hrManagerName: 'HR',
      charges: 'Tardiness 5 times in May',
      employeeResponseSummary: 'Admitted.',
      findings: 'Substantiated.',
      decision: d,
      suspensionDays: days,
      effectiveDate: DateTime(2026, 6, 6),
      issueDate: DateTime(2026, 6, 5),
    );

void main() {
  test('id + name + supportsBulk', () {
    const t = NodTemplate();
    expect(t.id, 'nod');
    expect(t.supportsBulk, isFalse);
  });

  test('build emits Charges/Response/Findings/Decision headings', () {
    const t = NodTemplate();
    final headings = t
        .build(_i())
        .whereType<HeadingBlock>()
        .map((h) => h.text)
        .toList();
    expect(
      headings,
      containsAll(['Charges', 'Employee Response', 'Findings', 'Decision']),
    );
  });

  test('TERMINATION text mentions Article 297', () {
    const t = NodTemplate();
    final body = t
        .build(_i(d: NodDecision.termination))
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .join(' ');
    expect(body, contains('Article 297'));
  });

  test('SUSPENSION text mentions number of days', () {
    const t = NodTemplate();
    final body = t
        .build(_i(d: NodDecision.suspension, days: 3))
        .whereType<ParagraphBlock>()
        .map((p) => p.text)
        .join(' ');
    expect(body, contains('3'));
    expect(body.toLowerCase(), contains('suspension'));
  });

  test('build includes the logo in MemoHeaderBlock when logoBytes set', () {
    final blocks = const NodTemplate().build(_i().copyWith(
      logoBytes: Uint8List.fromList(const [137, 80, 78, 71]),
    ));
    expect(blocks.first, isA<MemoHeaderBlock>());
    expect((blocks.first as MemoHeaderBlock).logoBytes, isNotNull);
  });

  test('no attachment block when attachmentBytes is null', () {
    const t = NodTemplate();
    final blocks = t.build(_i());
    expect(blocks.whereType<ImageAttachmentBlock>(), isEmpty);
    expect(blocks.whereType<PageBreakBlock>(), isEmpty);
  });

  test('appends attachment section when attachmentBytes is set', () {
    const t = NodTemplate();
    final blocks = t.build(_i().copyWith(
      attachmentBytes: Uint8List.fromList([9, 8, 7]),
      attachmentCaption: 'Damaged unit',
    ));
    final img = blocks.whereType<ImageAttachmentBlock>().toList();
    expect(img.length, 1);
    expect(img.first.caption, 'Damaged unit');
    expect(blocks.whereType<PageBreakBlock>().length, 1);
    expect(
      blocks.whereType<HeadingBlock>().any((h) => h.text == 'Attachment'),
      isTrue,
    );

    final iPage = blocks.indexWhere((b) => b is PageBreakBlock);
    final iHeading =
        blocks.indexWhere((b) => b is HeadingBlock && b.text == 'Attachment');
    final iImage = blocks.indexWhere((b) => b is ImageAttachmentBlock);
    expect(iPage, greaterThanOrEqualTo(0));
    expect(iPage, lessThan(iHeading));
    expect(iHeading, lessThan(iImage));
  });
}
