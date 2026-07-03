import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../core/pdf/interpolate.dart';
import '../brand_logo.dart';
import '../blocks/block.dart';
import '../blocks/bullet_list_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/image_attachment_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/memo_acknowledgment_block.dart';
import '../blocks/memo_header_block.dart';
import '../blocks/page_break_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/rich_text_block.dart';
import '../blocks/section_heading_block.dart';
import '../blocks/signature_block.dart';
import '../blocks/spacer_block.dart';
import 'document_template.dart';
import 'nte_inputs.dart';
import 'nte_validate.dart';

// PLACEHOLDER — engineer MUST replace with canonical wording from JAM
// employee record PDFs in Phase 8 Task 40.
const _nteIntroText =
    'It has come to the attention of management that you may have engaged '
    'in conduct that warrants investigation. The specific charges are '
    'detailed below.';
const _nteResponseInstructions =
    'You are required to submit a written explanation no later than '
    '{responseDeadline}. Failure to respond within this period will be '
    'taken as a waiver of your right to be heard, and the company may '
    'proceed with the appropriate disciplinary action based on the '
    'available evidence.';

class NteTemplate extends DocumentTemplate<NteInputs> {
  const NteTemplate();

  @override
  String get id => 'nte';
  @override
  String get name => 'Notice to Explain';
  @override
  String get description =>
      'Disciplinary notice with charges and applicable violations.';
  @override
  IconData get icon => Icons.report_outlined;
  @override
  int get version => 1;

  @override
  NteInputs emptyInputs() {
    final today = DateTime.now();
    return NteInputs(
      employeeId: '',
      employeeFullName: '',
      employeeFirstName: '',
      employeeLastName: '',
      employeePosition: '',
      employeeDepartment: '',
      companyId: '',
      companyName: '',
      dateIssued: today,
      responseDeadline: today.add(const Duration(days: 5)),
      subjectSubtopic: '',
      charges: const [],
      applicableViolations: const [],
    );
  }

  @override
  Future<NteInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();
    final logo = await loadCompanyLogoBytes(co);
    return NteInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeFirstName: emp.firstName,
      employeeLastName: emp.lastName,
      employeeHonorific: emp.honorific,
      employeePosition: emp.jobTitle ?? '',
      employeeDepartment: '',
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      hrManagerName: co?.hrManagerName,
      dateIssued: today,
      responseDeadline: today.add(const Duration(days: 5)),
      subjectSubtopic: '',
      charges: const [],
      applicableViolations: const [],
      logoBytes: logo,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(NteInputs inputs) => validateNte(inputs);

  @override
  List<Block> build(NteInputs i) {
    final fmt = DateFormat('MMMM d, yyyy');
    final blocks = <Block>[];
    blocks.add(MemoHeaderBlock(
      titleText: 'NOTICE TO EXPLAIN',
      companyName: i.companyName,
      companyAddress: i.companyAddress,
      date: i.dateIssued,
      to: LetterParty(
        name: i.employeeFullName,
        subtitle: [
          if (i.employeePosition.isNotEmpty) i.employeePosition,
          if (i.employeeDepartment.isNotEmpty) i.employeeDepartment,
        ].join(' · '),
      ),
      from: LetterParty(
        name: i.hrManagerName ?? '',
        subtitle: 'HR Manager',
      ),
      subject: i.finalSubject,
      salutation: i.employeeLastName.isEmpty
          ? null
          : '${i.employeeHonorific.isEmpty ? 'Mr./Ms.' : i.employeeHonorific} ${i.employeeLastName}',
      logoBytes: i.logoBytes,
    ));
    blocks.add(const SpacerBlock(16));
    blocks.add(const ParagraphBlock(_nteIntroText));
    blocks.add(const SpacerBlock(8));
    for (var idx = 0; idx < i.charges.length; idx++) {
      blocks.add(SectionHeadingBlock(
        number: idx + 1,
        title: i.charges[idx].title,
      ));
      blocks.add(RichTextBlock(i.charges[idx].body));
      blocks.add(const SpacerBlock(8));
    }
    blocks.add(const ParagraphBlock(
      'The above acts may constitute violations of the following Company policies:',
    ));
    blocks.add(BulletListBlock(i.applicableViolations));
    blocks.add(const SpacerBlock(8));
    blocks.add(ParagraphBlock(
      interpolate(
        _nteResponseInstructions,
        {'responseDeadline': fmt.format(i.responseDeadline)},
        lenient: true,
      ),
    ));
    blocks.add(const SpacerBlock(24));
    blocks.add(SignatureBlock(
      name: i.hrManagerName,
      role: 'HR Manager — ${i.companyName}',
      date: i.dateIssued,
    ));
    blocks.add(const SpacerBlock(24));
    blocks.add(const MemoAcknowledgmentBlock());
    if (i.attachmentBytes != null) {
      blocks.add(const PageBreakBlock());
      blocks.add(const HeadingBlock('Attachment'));
      blocks.add(const SpacerBlock(8));
      blocks.add(ImageAttachmentBlock(
        i.attachmentBytes!,
        caption: i.attachmentCaption,
      ));
    }
    return blocks;
  }
}

String _addressOf(dynamic co) {
  final parts = [
    co.addressLine1,
    co.addressLine2,
    [co.city, co.province, co.zipCode]
        .where((s) => s != null && (s as String).isNotEmpty)
        .join(', '),
  ].where((s) => s != null && (s as String).isNotEmpty).cast<String>().toList();
  return parts.join(' · ');
}
