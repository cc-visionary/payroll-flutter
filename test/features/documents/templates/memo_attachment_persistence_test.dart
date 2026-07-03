import 'dart:typed_data';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/image_attachment_block.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_template.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nte_template.dart';

void main() {
  group('memo attachment is generation-time only (never persisted)', () {
    test('NTE: round-trip drops attachmentBytes + attachmentCaption, '
        'and re-rendered doc has no ImageAttachmentBlock', () {
      final inputs = NteInputs(
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
        attachmentBytes: Uint8List.fromList([1, 2, 3]),
        attachmentCaption: 'Evidence photo',
      );

      // Sanity: attachment renders before the round-trip.
      expect(
        const NteTemplate().build(inputs).whereType<ImageAttachmentBlock>().length,
        1,
      );

      final reloaded = NteInputs.fromJson(inputs.toJson());

      expect(reloaded.attachmentBytes, isNull);
      expect(reloaded.attachmentCaption, isNull);
      expect(
        const NteTemplate().build(reloaded).whereType<ImageAttachmentBlock>(),
        isEmpty,
      );
    });

    test('NOD: round-trip drops attachmentBytes + attachmentCaption, '
        'and re-rendered doc has no ImageAttachmentBlock', () {
      final inputs = NodInputs(
        employeeId: 'e1',
        employeeFullName: 'Bob',
        companyId: 'c1',
        companyName: 'X',
        effectiveDate: DateTime(2026, 6, 6),
        issueDate: DateTime(2026, 6, 5),
        attachmentBytes: Uint8List.fromList([1, 2, 3]),
        attachmentCaption: 'Damaged unit',
      );

      // Sanity: attachment renders before the round-trip.
      expect(
        const NodTemplate().build(inputs).whereType<ImageAttachmentBlock>().length,
        1,
      );

      final reloaded = NodInputs.fromJson(inputs.toJson());

      expect(reloaded.attachmentBytes, isNull);
      expect(reloaded.attachmentCaption, isNull);
      expect(
        const NodTemplate().build(reloaded).whereType<ImageAttachmentBlock>(),
        isEmpty,
      );
    });
  });
}
