import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;
// `asData` is an extension on AsyncValue — needed in scope for the gate's
// synchronous, fail-open read of the employee's active penalty.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/pdf/signature_png.dart';
import '../blocks/block.dart';
import '../blocks/heading_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/letterhead_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import '../blocks/table_block.dart';
import '../brand_logo.dart';
import '../providers.dart';
import 'document_template.dart';
import 'penalty_agreement_inputs.dart';
import 'penalty_agreement_validate.dart';

class PenaltyAgreementTemplate
    extends DocumentTemplate<PenaltyAgreementInputs> {
  const PenaltyAgreementTemplate();

  @override
  String get id => 'penalty_agreement';

  @override
  String get name => 'Penalty Repayment Agreement';

  @override
  String get description =>
      'Written authorization for a salary deduction repaying an assessed '
      'penalty, with the full installment schedule. Labor Code Art. 113 '
      'requires the employee\'s written consent before deducting.';

  @override
  IconData get icon => Icons.receipt_long_outlined;

  @override
  int get version => 1;

  @override
  PenaltyAgreementInputs emptyInputs() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return PenaltyAgreementInputs(
      employeeId: '',
      employeeFullName: '',
      companyId: '',
      companyName: '',
      effectiveDate: today,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) {
    final e = ctx.employee;
    if (e == null) return const [];
    // `read` (not `watch`) — gates is synchronous, so a cold cache resolves to
    // AsyncLoading. Fail OPEN in that case: only a RESOLVED "no active
    // penalty" blocks the template, never an unfinished lookup.
    final resolved = ctx.ref
        .read(penaltyForAgreementProvider((employeeId: e.id, penaltyId: null)))
        .asData;
    if (resolved != null && resolved.value == null) {
      return const [
        Gate(
          'This employee has no active penalty on record to draft an '
          'agreement for.',
        ),
      ];
    }
    return const [];
  }

  @override
  Future<PenaltyAgreementInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    PenaltyRecord? p;
    if (e != null) {
      try {
        p = await ctx.ref.read(
          penaltyForAgreementProvider((
            employeeId: e.id,
            penaltyId: ctx.penaltyId,
          )).future,
        );
      } catch (_) {
        p = null;
      }
    }

    final logo = await loadCompanyLogoBytes(c);

    return PenaltyAgreementInputs(
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
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
      penaltyId: p?.id,
      description: p?.description ?? '',
      totalAmount: p?.totalAmount ?? Decimal.zero,
      effectiveDate: p?.effectiveDate ?? today,
      remarks: p?.remarks,
      installments: [
        for (final r in p?.installments ?? const <PenaltyInstallmentRow>[])
          PenaltyInstallmentLine(
            number: r.number,
            amount: r.amount,
            isDeducted: r.isDeducted,
          ),
      ],
      logoBytes: logo,
      companySignaturePngB64: ctx.hrSignatory?.signaturePngB64,
      employeeSignaturePngB64: e?.signaturePngB64,
    );
  }

  @override
  List<ValidationError> validate(PenaltyAgreementInputs inputs) =>
      validatePenaltyAgreement(inputs);

  @override
  List<Block> build(PenaltyAgreementInputs i) {
    final dateFmt = DateFormat('MMMM d, yyyy');
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    String fmtMoney(Decimal d) => money.format(d.toDouble());

    final effectiveStr = dateFmt.format(i.effectiveDate);
    final incident = i.description.trim().isEmpty
        ? 'the incident on record'
        : i.description.trim();
    final count = i.installments.length;
    final installmentWord = count == 1 ? 'installment' : 'installments';
    final employer = i.companyName.trim().isEmpty
        ? 'the Company'
        : i.companyName.trim();
    final remarks = (i.remarks ?? '').trim();

    final rows = <List<String>>[
      for (final l in i.installments)
        [
          l.number.toString(),
          fmtMoney(l.amount),
          l.isDeducted ? 'Deducted' : 'Scheduled',
        ],
    ];

    return [
      // Letterhead.
      if (i.logoBytes != null || i.companyName.isNotEmpty)
        LetterheadBlock(
          logoBytes: i.logoBytes,
          companyName: i.companyName,
          companyAddress: i.companyAddress.isEmpty ? null : i.companyAddress,
        ),
      const SpacerBlock(16),

      // Letter meta: date, recipient, subject.
      LetterMetaBlock(
        date: i.effectiveDate,
        to: LetterParty(name: i.employeeFullName),
        position: i.employeePosition.isEmpty ? null : i.employeePosition,
        subject: 'Penalty Repayment Agreement',
        from: LetterParty(name: i.hrManagerName, subtitle: 'HR Manager'),
        showDividers: false,
      ),
      const SpacerBlock(16),

      // Intro paragraph — the incident and the amount assessed.
      ParagraphBlock(
        'This agreement covers the penalty assessed against you in connection '
        'with $incident. The total amount payable is ${fmtMoney(i.totalAmount)}, '
        'effective $effectiveStr, to be repaid over $count $installmentWord as '
        'scheduled below.',
      ),
      const SpacerBlock(16),

      // Repayment schedule.
      const HeadingBlock('Repayment Schedule'),
      const SpacerBlock(8),
      TableBlock(
        headers: const ['Installment', 'Amount', 'Status'],
        rows: rows,
      ),
      const SpacerBlock(16),

      // Authorization paragraph — the Art. 113 written consent.
      ParagraphBlock(
        'I authorize $employer to deduct the amounts shown in the schedule '
        'above from my salary on the corresponding payroll cut-offs, until the '
        'total of ${fmtMoney(i.totalAmount)} is fully repaid. I confirm that I '
        'have read and understood this agreement, that I enter into it '
        'voluntarily, and that the deductions above are made with my written '
        'consent.',
      ),
      if (remarks.isNotEmpty) ...[
        const SpacerBlock(12),
        ParagraphBlock('Remarks: $remarks'),
      ],

      // Signature block — HR + Employee Conforme.
      const SpacerBlock(40),
      MultiSignatureBlock([
        SignatoryParty(
          name: i.hrManagerName,
          role: 'HR Manager',
          date: i.effectiveDate,
          signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),
        ),
        SignatoryParty(
          name: i.employeeFullName,
          role: 'Employee (Conforme)',
          signatureImage: decodeSignaturePngB64(i.employeeSignaturePngB64),
        ),
      ]),
    ];
  }
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
