import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../brand_logo.dart';
import '../blocks/block.dart';
import '../blocks/heading_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/memo_header_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import 'document_template.dart';
import 'resignation_acceptance_inputs.dart';
import 'resignation_acceptance_validate.dart';

class ResignationAcceptanceTemplate
    extends DocumentTemplate<ResignationAcceptanceInputs> {
  const ResignationAcceptanceTemplate();

  @override
  String get id => 'resignation_acceptance';

  @override
  String get name => 'Resignation Acceptance';

  @override
  String get description =>
      'Formal HR acceptance of a resignation. Includes turnover, clearance, '
      'and final-pay disclosures.';

  @override
  IconData get icon => Icons.exit_to_app_outlined;

  @override
  int get version => 1;

  @override
  bool get supportsBulk => true;

  @override
  ResignationAcceptanceInputs emptyInputs() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ResignationAcceptanceInputs(
      employeeId: '',
      employeeFullName: '',
      companyId: '',
      companyName: '',
      resignationDate: today,
      lastDayOfWork: today.add(const Duration(days: 30)),
      issueDate: today,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  Future<ResignationAcceptanceInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logo = await loadCompanyLogoBytes(c);
    return ResignationAcceptanceInputs(
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
      hrManagerName: c?.hrManagerName ?? '',
      resignationDate: today,
      lastDayOfWork: today.add(const Duration(days: 30)),
      issueDate: today,
      logoBytes: logo,
    );
  }

  @override
  List<ValidationError> validate(ResignationAcceptanceInputs inputs) =>
      validateResignationAcceptance(inputs);

  @override
  List<Block> build(ResignationAcceptanceInputs i) {
    final df = DateFormat('MMMM d, yyyy');
    final honorific = _honorific(i.employeeGender);

    final blocks = <Block>[
      MemoHeaderBlock(
        titleText: 'ACCEPTANCE OF RESIGNATION',
        companyName: i.companyName,
        companyAddress: i.companyAddress,
        date: i.issueDate,
        to: LetterParty(
          name: i.employeeFullName,
          subtitle: i.employeePosition.isEmpty ? null : i.employeePosition,
        ),
        from: LetterParty(name: i.hrManagerName, subtitle: 'HR Manager'),
        subject: 'Acceptance of Resignation',
        salutation: i.employeeFullName.isEmpty
            ? null
            : '$honorific ${_lastName(i.employeeFullName)},',
        logoBytes: i.logoBytes,
      ),
      const SpacerBlock(16),
      ParagraphBlock(
        'This acknowledges receipt of your resignation letter dated '
        '${df.format(i.resignationDate)}. ${i.companyName} formally accepts '
        'your resignation, effective ${df.format(i.lastDayOfWork)} as your '
        'last day of work.',
      ),
      const SpacerBlock(12),
      const HeadingBlock('Turnover'),
      ParagraphBlock(i.turnoverInstructions),
    ];

    if (i.includeClearanceMention) {
      blocks.add(const SpacerBlock(8));
      blocks.add(
        const ParagraphBlock(
          'Please complete the company Clearance Form prior to your last day. '
          'Your Certificate of Employment and Quitclaim will be released upon '
          'clearance completion.',
        ),
      );
    }

    if (i.includeFinalPayMention) {
      blocks.add(const SpacerBlock(8));
      blocks.add(
        ParagraphBlock(
          'Your final pay will be released within thirty (30) days from '
          '${df.format(i.lastDayOfWork)} in accordance with DOLE Labor '
          'Advisory 06-20.',
        ),
      );
    }

    blocks.add(const SpacerBlock(12));
    blocks.add(
      ParagraphBlock(
        'We thank you for your contributions to ${i.companyName} and wish you '
        'success in your future endeavors. Please acknowledge receipt below.',
      ),
    );
    blocks.add(const SpacerBlock(40));
    blocks.add(
      MultiSignatureBlock([
        SignatoryParty(name: i.hrManagerName, role: 'HR Manager'),
        SignatoryParty(
          name: i.employeeFullName,
          role: 'Employee (Acknowledged)',
        ),
      ]),
    );

    return blocks;
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
