import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/company_header_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/key_value_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'final_pay_inputs.dart';
import 'final_pay_validate.dart';

class FinalPayTemplate extends DocumentTemplate<FinalPayInputs> {
  const FinalPayTemplate();

  @override
  String get id => 'final_pay';

  @override
  String get name => 'Final Pay Computation';

  @override
  String get description =>
      'Itemized final-pay disclosure for a separated employee. Auto-computes '
      'from payroll engine; HR can override any line. Required by DOLE Labor '
      'Advisory 06-20.';

  @override
  IconData get icon => Icons.payments_outlined;

  @override
  int get version => 1;

  @override
  bool get supportsBulk => false;

  @override
  FinalPayInputs emptyInputs() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return FinalPayInputs(
      employeeId: '',
      employeeFullName: '',
      companyId: '',
      companyName: '',
      computedAsOf: today,
      releaseDate: today.add(const Duration(days: 30)),
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) {
    final e = ctx.employee;
    if (e == null) return const [];
    final inactive = e.employmentStatus != 'ACTIVE' || e.separationDate != null;
    if (!inactive) {
      return const [Gate('Final Pay is only valid for separated employees.')];
    }
    return const [];
  }

  @override
  Future<FinalPayInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    FinalPayBreakdown? bd;
    if (e != null) {
      try {
        bd = await ctx.ref.read(finalPayBreakdownProvider(e.id).future);
      } catch (_) {
        bd = null;
      }
    }

    return FinalPayInputs(
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
      employeeHireDate: e?.hireDate,
      employeeSeparationDate: e?.separationDate,
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
      lastNetPay: bd?.lastNetPay ?? Decimal.zero,
      thirteenthMonth: bd?.thirteenthMonth ?? Decimal.zero,
      unusedLeaveConversion: bd?.unusedLeaveConversion ?? Decimal.zero,
      outstandingCashAdvance: bd?.outstandingCashAdvance ?? Decimal.zero,
      computedAsOf: today,
      releaseDate: today.add(const Duration(days: 30)),
    );
  }

  @override
  List<ValidationError> validate(FinalPayInputs inputs) =>
      validateFinalPay(inputs);

  @override
  List<Block> build(FinalPayInputs i) {
    final dateFmt = DateFormat('MMMM d, yyyy');
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    String fmtMoney(Decimal d) => money.format(d.toDouble());
    String fmtDeduction(Decimal d) => '(${fmtMoney(d)})';

    final separation = i.employeeSeparationDate;
    final separationStr = separation == null ? '—' : dateFmt.format(separation);
    final releaseStr = dateFmt.format(i.releaseDate);

    final hasOtherDeductions = i.otherDeductions > Decimal.zero;
    final otherLabel = i.otherDeductionsLabel.trim().isEmpty
        ? 'Other deductions'
        : i.otherDeductionsLabel.trim();

    final rows = <KeyValueRow>[
      KeyValueRow('Last salary (pro-rated)', fmtMoney(i.lastNetPay)),
      KeyValueRow('13th month pay (pro-rated)', fmtMoney(i.thirteenthMonth)),
      KeyValueRow('Unused leave conversion', fmtMoney(i.unusedLeaveConversion)),
      KeyValueRow(
        'Less: Outstanding cash advances',
        fmtDeduction(i.outstandingCashAdvance),
      ),
      if (hasOtherDeductions)
        KeyValueRow('Less: $otherLabel', fmtDeduction(i.otherDeductions)),
      KeyValueRow('TOTAL FINAL PAY', fmtMoney(i.total)),
    ];

    return [
      // Letterhead.
      CompanyHeaderBlock(
        name: i.companyName,
        address: i.companyAddress.isEmpty ? null : i.companyAddress,
      ),
      const SpacerBlock(16),

      // Letter meta: date, recipient, subject.
      LetterMetaBlock(
        date: i.computedAsOf,
        to: LetterParty(name: i.employeeFullName),
        position: i.employeePosition.isEmpty ? null : i.employeePosition,
        subject: 'Final Pay Computation Breakdown',
        from: LetterParty(name: i.hrManagerName, subtitle: 'HR Manager'),
        showDividers: false,
      ),
      const SpacerBlock(16),

      // Intro paragraph.
      ParagraphBlock(
        'Per DOLE Labor Advisory 06-20, this document discloses the '
        'computation of your final pay following separation effective '
        '$separationStr.',
      ),
      const SpacerBlock(16),

      // Computation section.
      const HeadingBlock('Computation'),
      const SpacerBlock(8),
      KeyValueBlock(rows, labelWidth: 220),
      const SpacerBlock(16),

      // Release paragraph.
      ParagraphBlock(
        'The release date is $releaseStr. Please report to HR with valid '
        'ID to claim. Any disputes should be raised in writing within '
        'seven (7) days of receipt.',
      ),

      // Signature block — HR + Employee Acknowledged.
      const SpacerBlock(40),
      MultiSignatureBlock([
        SignatoryParty(
          name: i.hrManagerName,
          role: 'HR Manager',
          date: i.computedAsOf,
        ),
        SignatoryParty(
          name: i.employeeFullName,
          role: 'Employee (Acknowledged)',
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
