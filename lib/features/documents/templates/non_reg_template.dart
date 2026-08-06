import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../core/pdf/signature_png.dart';
import '../brand_logo.dart';
import '../blocks/block.dart';
import '../blocks/emphasis_paragraph_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/labelled_bullet_list_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/letterhead_block.dart';
import '../blocks/page_break_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/section_heading_block.dart';
import '../blocks/signature_block.dart';
import '../blocks/spacer_block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'non_reg_inputs.dart';
import 'non_reg_validate.dart';

// Canonical legal copy lifted verbatim from
// `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/NOTICE OF
// NON-REGULARIZATION_VIDAL - Google Docs.pdf`. Confirm wording with the
// user before merge (Task 22).
const _specificallyLead =
    'Specifically, you failed to meet the agreed-upon standards in the '
    'following areas:';
const _finalPayText =
    'Please arrange to return your Company ID, access keys, and any other '
    'company property currently in your possession. Your Final Pay, '
    'including your pro-rated 13th-month pay, will be processed in '
    'accordance with Section 14 (Final Pay) of your contract and released '
    'upon completion of the clearance process.';
const _closingText =
    'We thank you for the time spent with the company and wish you the '
    'best in your future endeavors.';
const _acknowledgmentText =
    'I acknowledge receipt of this notice. I understand that my signature '
    'attests only to the receipt of this letter and not necessarily my '
    'agreement with its contents.';

/// PH Labor Code default: probationary period is six months from the
/// hire date. HR can override via the lock/unlock toggle if a longer
/// period was stipulated in the employment contract.
DateTime defaultProbationaryEnd(DateTime start) {
  // Add 6 calendar months. Dart's DateTime does this safely: if the
  // target month has no equivalent day-of-month, the constructor wraps
  // into the next month (e.g. Aug 31 + 6 mo → Mar 3 the next year). For
  // a probation-end calculation that overshoot is acceptable and rare.
  return DateTime(start.year, start.month + 6, start.day);
}

class NonRegTemplate extends DocumentTemplate<NonRegInputs> {
  const NonRegTemplate();

  @override
  String get id => 'non_reg';
  @override
  String get name => 'Notice of Non-Regularization';
  @override
  String get description =>
      'Issued when a probationary employee fails to regularize.';
  @override
  IconData get icon => Icons.person_off_outlined;
  @override
  int get version => 1;

  @override
  NonRegInputs emptyInputs() {
    final today = DateTime.now();
    return NonRegInputs(
      employeeId: '',
      employeeFullName: '',
      employeeLastName: '',
      employeePosition: '',
      companyId: '',
      companyName: '',
      dateIssued: today,
      salutationName: '',
      findings: const [],
    );
  }

  @override
  Future<NonRegInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();
    final logo = await loadCompanyLogoBytes(co);
    // Pull the latest HIRE event; fall back to employee.hireDate (already
    // on the Employee model) if no event row exists. Wrap in try/catch
    // so tests / dev environments without an initialized Supabase client
    // gracefully fall back to the model's hireDate. Consistent with
    // providers.dart::finalPayBreakdownProvider.
    Map<String, dynamic>? hireRow;
    try {
      hireRow = await ctx.ref.read(
        latestEmploymentEventProvider((
          employeeId: emp.id,
          eventType: 'HIRE',
        )).future,
      );
    } catch (_) {
      hireRow = null;
    }
    DateTime? eventDate(Map<String, dynamic>? r) {
      if (r == null) return null;
      final v = r['event_date'] as String?;
      return v == null ? null : DateTime.parse(v);
    }

    final probStart = eventDate(hireRow) ?? emp.hireDate;
    final probEnd = defaultProbationaryEnd(probStart);
    return NonRegInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeLastName: emp.lastName,
      employeePosition: emp.jobTitle ?? '',
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      hrManagerName: ctx.hrSignatory?.name ?? co?.hrManagerName,
      dateIssued: today,
      probationaryStart: probStart,
      probationaryEnd: probEnd,
      effectiveEndDate: probEnd,
      salutationName: emp.honorific.isEmpty
          ? emp.lastName
          : '${emp.honorific} ${emp.lastName}',
      findings: const [],
      logoBytes: logo,
      companySignaturePngB64: ctx.hrSignatory?.signaturePngB64,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(NonRegInputs inputs) => validateNonReg(inputs);

  @override
  List<Block> build(NonRegInputs i) {
    final fmt = DateFormat('MMMM d, yyyy');
    final blocks = <Block>[];

    if (i.logoBytes != null || i.companyName.isNotEmpty) {
      blocks.add(
        LetterheadBlock(
          logoBytes: i.logoBytes,
          companyName: i.companyName,
          companyAddress: (i.companyAddress?.isEmpty ?? true)
              ? null
              : i.companyAddress,
        ),
      );
    }
    blocks.add(const SpacerBlock(16));

    // 1-2. Meta + spacer.
    blocks.add(
      LetterMetaBlock(
        date: i.dateIssued,
        to: LetterParty(name: i.employeeFullName),
        position: i.employeePosition.isEmpty ? null : i.employeePosition,
        from: LetterParty(name: i.hrManagerName ?? ''),
        subject: null,
        showDividers: false,
      ),
    );
    blocks.add(const SpacerBlock(16));

    // 3-4. Subject heading + spacer.
    blocks.add(const HeadingBlock('SUBJECT: NOTICE OF NON-REGULARIZATION'));
    blocks.add(const SpacerBlock(12));

    // 5-6. Salutation + spacer.
    blocks.add(ParagraphBlock('Dear ${i.salutationName},'));
    blocks.add(const SpacerBlock(8));

    // 7. Intro paragraph 1 — bold dates inline.
    final ps = i.probationaryStart;
    final pe = i.probationaryEnd;
    blocks.add(
      EmphasisParagraphBlock(
        spans: [
          const EmphasisSpan(
            'This letter serves as formal notification regarding the status '
            'of your probationary employment, which commenced on ',
          ),
          EmphasisSpan(ps == null ? '—' : fmt.format(ps), bold: true),
          const EmphasisSpan(' and is scheduled to end on '),
          EmphasisSpan(pe == null ? '—' : fmt.format(pe), bold: true),
          const EmphasisSpan('.'),
        ],
      ),
    );

    // 8. Intro paragraph 2 — bold Section 4 + Annex B references inline.
    blocks.add(
      const EmphasisParagraphBlock(
        spans: [
          EmphasisSpan('As stipulated in '),
          EmphasisSpan('Section 4 (Probationary Evaluation)', bold: true),
          EmphasisSpan(
            ' of your Employment Contract, the Company has evaluated your '
            'performance against the ',
          ),
          EmphasisSpan('Standards for Regularization', bold: true),
          EmphasisSpan(
            ' (Annex B). After a comprehensive review, we regret to inform '
            'you that you have not met the reasonable standards required to '
            'qualify for regular employment.',
          ),
        ],
      ),
    );

    // 9. Optional note on scope.
    if (i.noteOnScope.trim().isNotEmpty) {
      blocks.add(
        EmphasisParagraphBlock(
          spans: [
            const EmphasisSpan('Note on Scope of Evaluation: ', bold: true),
            EmphasisSpan(i.noteOnScope.trim()),
          ],
        ),
      );
    }

    // 10. Specifically lead-in.
    blocks.add(const ParagraphBlock(_specificallyLead));

    // 11. Findings loop.
    for (var idx = 0; idx < i.findings.length; idx++) {
      final f = i.findings[idx];
      blocks.add(const SpacerBlock(12));
      blocks.add(SectionHeadingBlock(number: idx + 1, title: f.title));
      blocks.add(
        LabelledBulletListBlock(
          items: [
            LabelledBulletItem(leadBold: 'Standard', body: f.standard),
            LabelledBulletItem(
              leadBold: 'Finding',
              body: f.finding,
              children: [
                for (final s in f.subFindings)
                  LabelledBulletItem(leadBold: s.title, body: s.body),
              ],
            ),
          ],
        ),
      );
    }

    // 12-13. Decision heading + spacer.
    blocks.add(const SpacerBlock(16));
    blocks.add(const HeadingBlock('DECISION'));

    // 14. Decision paragraph with bold effectiveEndDate.
    final ee = i.effectiveEndDate;
    blocks.add(
      EmphasisParagraphBlock(
        spans: [
          const EmphasisSpan(
            'In view of the foregoing, your probationary employment will '
            'not be regularized and will cease effective at the close of '
            'business hours on ',
          ),
          EmphasisSpan(ee == null ? '—' : fmt.format(ee), bold: true),
          const EmphasisSpan('.'),
        ],
      ),
    );

    // 15-16. Final pay + closing.
    blocks.add(const ParagraphBlock(_finalPayText));
    blocks.add(const ParagraphBlock(_closingText));

    // 17-20. Sincerely + HR signature.
    blocks.add(const SpacerBlock(24));
    blocks.add(const ParagraphBlock('Sincerely,'));
    blocks.add(const SpacerBlock(40));
    blocks.add(
      SignatureBlock(
        name: i.hrManagerName,
        role: 'HR Manager\n${i.companyName}',
        date: i.dateIssued,
        signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),
      ),
    );

    // 21-30. Acknowledgment page.
    blocks.add(const PageBreakBlock());
    blocks.add(const HeadingBlock('ACKNOWLEDGMENT OF RECEIPT'));
    blocks.add(const SpacerBlock(8));
    blocks.add(const ParagraphBlock(_acknowledgmentText));
    blocks.add(const SpacerBlock(40));
    blocks.add(SignatureBlock(name: i.employeeFullName, role: '', date: null));
    blocks.add(const SpacerBlock(24));
    blocks.add(const ParagraphBlock('Witnessed by:'));
    blocks.add(const SpacerBlock(40));
    blocks.add(
      SignatureBlock(
        name: i.witnessName.isEmpty ? null : i.witnessName,
        role: '',
        date: null,
      ),
    );

    return blocks;
  }
}

String _addressOf(dynamic co) {
  final parts = [
    co.addressLine1,
    co.addressLine2,
    [
      co.city,
      co.province,
      co.zipCode,
    ].where((s) => s != null && (s as String).isNotEmpty).join(', '),
  ].where((s) => s != null && (s as String).isNotEmpty).cast<String>().toList();
  return parts.join(' · ');
}
