import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../core/pdf/signature_png.dart';
import '../brand_logo.dart';
import '../blocks/block.dart';
import '../blocks/heading_block.dart';
import '../blocks/image_attachment_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/memo_header_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/page_break_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import 'document_template.dart';
import 'nod_inputs.dart';
import 'nod_validate.dart';

class NodTemplate extends DocumentTemplate<NodInputs> {
  const NodTemplate();

  @override
  String get id => 'nod';

  @override
  String get name => 'Notice of Decision';

  @override
  String get description =>
      'Disciplinary decision following an NTE. Optional link to the originating '
      'NTE auto-fills dates/charges. Closes the Labor Code Art. 297-299 '
      'due-process chain.';

  @override
  IconData get icon => Icons.gavel_outlined;

  @override
  int get version => 1;

  @override
  bool get supportsBulk => false;

  @override
  NodInputs emptyInputs() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return NodInputs(
      employeeId: '',
      employeeFullName: '',
      companyId: '',
      companyName: '',
      issueDate: today,
      effectiveDate: today,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  Future<NodInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logo = await loadCompanyLogoBytes(c);
    return NodInputs(
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
      employeeGender: e?.gender ?? '',
      companyId: c?.id ?? '',
      companyName: c?.name ?? '',
      companyAddress: c == null
          ? ''
          : _composeAddress(
              c.addressLine1,
              c.addressLine2,
              c.city,
              c.province,
              c.zipCode,
            ),
      hrManagerName: ctx.hrSignatory?.name ?? c?.hrManagerName ?? '',
      issueDate: today,
      effectiveDate: today,
      logoBytes: logo,
      companySignaturePngB64: ctx.hrSignatory?.signaturePngB64,
    );
  }

  @override
  List<ValidationError> validate(NodInputs inputs) => validateNod(inputs);

  @override
  List<Block> build(NodInputs i) {
    final df = DateFormat('MMMM d, yyyy');
    final honorific = _honorific(i.employeeGender);
    final nteDateStr = i.nteDate != null ? df.format(i.nteDate!) : '___';
    return <Block>[
      MemoHeaderBlock(
        titleText: 'NOTICE OF DECISION',
        companyName: i.companyName,
        companyAddress: i.companyAddress,
        date: i.issueDate,
        to: LetterParty(
          name: i.employeeFullName,
          subtitle: i.employeePosition.isEmpty ? null : i.employeePosition,
        ),
        from: LetterParty(name: i.hrManagerName, subtitle: 'HR Manager'),
        subject: 'Notice of Decision',
        salutation: i.employeeFullName.isEmpty
            ? null
            : '$honorific ${_lastName(i.employeeFullName)},',
        logoBytes: i.logoBytes,
      ),
      const SpacerBlock(16),
      ParagraphBlock(
        'This Notice of Decision is issued in response to the Notice to '
        'Explain dated $nteDateStr, and your written explanation received '
        'thereafter.',
      ),
      const SpacerBlock(12),
      const HeadingBlock('Charges'),
      ParagraphBlock(i.charges),
      const SpacerBlock(8),
      const HeadingBlock('Employee Response'),
      ParagraphBlock(i.employeeResponseSummary),
      const SpacerBlock(8),
      const HeadingBlock('Findings'),
      ParagraphBlock(i.findings),
      const SpacerBlock(8),
      const HeadingBlock('Decision'),
      ParagraphBlock(_decisionText(i, df)),
      const SpacerBlock(12),
      const ParagraphBlock(
        'You may appeal this decision in writing within five (5) working days '
        'of receipt. Please acknowledge receipt below.',
      ),
      const SpacerBlock(40),
      MultiSignatureBlock([
        SignatoryParty(
          name: i.hrManagerName,
          role: 'HR Manager',
          signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),
        ),
        SignatoryParty(
          name: i.employeeFullName,
          role: 'Employee (Acknowledged)',
        ),
      ]),
      if (i.attachmentBytes != null) ...[
        const PageBreakBlock(),
        const HeadingBlock('Annex A'),
        const SpacerBlock(8),
        ImageAttachmentBlock(
          i.attachmentBytes!,
          caption: i.attachmentCaption,
        ),
      ],
    ];
  }
}

String _honorific(String gender) {
  final g = gender.trim().toLowerCase();
  if (g.startsWith('f')) return 'Ms.';
  if (g.startsWith('m')) return 'Mr.';
  return 'Mr./Ms.';
}

String _lastName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? fullName : parts.last;
}

String _composeAddress(
  String? l1,
  String? l2,
  String? city,
  String? prov,
  String? zip,
) {
  final tail = [
    city,
    prov,
    zip,
  ].where((s) => s != null && s.isNotEmpty).join(', ');
  return [
    l1,
    l2,
    tail,
  ].where((s) => s != null && s.isNotEmpty).cast<String>().join(', ');
}

String _decisionText(NodInputs i, DateFormat df) {
  switch (i.decision) {
    case NodDecision.reprimand:
      return 'After careful consideration, management has decided to issue a '
          'written reprimand for the above infractions.';
    case NodDecision.writtenWarning:
      return 'After careful consideration, management has decided to issue a '
          'written warning. Any repeat offense may result in stronger '
          'disciplinary action.';
    case NodDecision.suspension:
      return 'After careful consideration, management has decided to impose a '
          '${i.suspensionDays}-day suspension without pay, effective '
          '${df.format(i.effectiveDate)}.';
    case NodDecision.termination:
      return 'After careful consideration, management has decided to terminate '
          'your employment effective ${df.format(i.effectiveDate)}, in '
          'accordance with Article 297 of the Labor Code of the Philippines.';
    case NodDecision.noAction:
      return 'After review, management has decided that no further '
          'disciplinary action is warranted at this time.';
  }
}
