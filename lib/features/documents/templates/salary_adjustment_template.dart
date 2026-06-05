import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../data/models/role_scorecard.dart';
import '../blocks/block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'salary_adjustment_inputs.dart';
import 'salary_adjustment_validate.dart';

/// One template, two modes:
///   - [SalaryAdjustmentType.salaryAdjustment]: pure pay change.
///   - [SalaryAdjustmentType.promotion]: role + pay change.
class SalaryAdjustmentTemplate
    extends DocumentTemplate<SalaryAdjustmentInputs> {
  const SalaryAdjustmentTemplate();

  @override
  String get id => 'salary_adjustment';

  @override
  String get name => 'Salary Adjustment / Promotion';

  @override
  String get description =>
      'Notice of salary adjustment, or promotion (role + salary change). '
      'One template, two modes.';

  @override
  IconData get icon => Icons.trending_up_outlined;

  @override
  int get version => 1;

  @override
  bool get supportsBulk => true;

  @override
  SalaryAdjustmentInputs emptyInputs() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstOfNextMonth = DateTime(now.year, now.month + 1, 1);
    return SalaryAdjustmentInputs(
      employeeId: '',
      employeeFullName: '',
      companyId: '',
      companyName: '',
      effectiveDate: firstOfNextMonth,
      issueDate: today,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  Future<SalaryAdjustmentInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstOfNextMonth = DateTime(now.year, now.month + 1, 1);

    // Fetch the current scorecard to get baseSalary + wageType + jobTitle.
    RoleScorecard? scorecard;
    if (e?.roleScorecardId != null && e!.roleScorecardId!.isNotEmpty) {
      try {
        scorecard = await ctx.ref.read(
          roleScorecardByIdProvider(e.roleScorecardId!).future,
        );
      } catch (_) {
        scorecard = null;
      }
    }

    return SalaryAdjustmentInputs(
      type: SalaryAdjustmentType.salaryAdjustment,
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? scorecard?.jobTitle ?? '',
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
      oldRoleScorecardId: e?.roleScorecardId,
      oldPosition: e?.jobTitle ?? scorecard?.jobTitle ?? '',
      oldSalary:
          e?.declaredWageOverride ?? scorecard?.baseSalary ?? Decimal.zero,
      salaryPeriod: scorecard?.wageType ?? 'MONTHLY',
      effectiveDate: firstOfNextMonth,
      issueDate: today,
    );
  }

  @override
  List<ValidationError> validate(SalaryAdjustmentInputs inputs) =>
      validateSalaryAdjustment(inputs);

  @override
  List<Block> build(SalaryAdjustmentInputs i) {
    final df = DateFormat('MMMM d, yyyy');
    final cf = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final periodLabel = i.salaryPeriod == 'DAILY'
        ? 'daily rate'
        : 'monthly salary';
    final salutation = _salutation(i.employeeGender, i.employeeFullName);
    final subject = i.type == SalaryAdjustmentType.promotion
        ? 'Notice of Promotion'
        : 'Notice of Salary Adjustment';

    final bodyText = i.type == SalaryAdjustmentType.promotion
        ? 'We are pleased to inform you that, effective '
              '${df.format(i.effectiveDate)}, you are being promoted from '
              '${i.oldPosition} to ${i.newPosition}. In line with this '
              'promotion, your $periodLabel will be adjusted from '
              '${cf.format(i.oldSalary.toDouble())} to '
              '${cf.format(i.newSalary.toDouble())}. ${i.reason}'
        : 'We are pleased to inform you that, effective '
              '${df.format(i.effectiveDate)}, your $periodLabel will be '
              'adjusted from ${cf.format(i.oldSalary.toDouble())} to '
              '${cf.format(i.newSalary.toDouble())}. ${i.reason}';

    return <Block>[
      LetterMetaBlock(
        date: i.issueDate,
        to: LetterParty(name: i.employeeFullName),
        position: i.employeePosition.isEmpty ? null : i.employeePosition,
        from: LetterParty(name: i.hrManagerName, subtitle: 'HR Manager'),
        subject: subject,
        showDividers: false,
      ),
      const SpacerBlock(12),
      ParagraphBlock('$salutation,'),
      const SpacerBlock(8),
      ParagraphBlock(bodyText),
      const SpacerBlock(12),
      const ParagraphBlock(
        'All other terms of your employment remain unchanged. Please '
        'acknowledge receipt of this letter below.',
      ),
      const SpacerBlock(40),
      MultiSignatureBlock([
        SignatoryParty(name: i.hrManagerName, role: 'HR Manager'),
        SignatoryParty(
          name: i.employeeFullName,
          role: 'Employee (Acknowledged)',
        ),
      ]),
    ];
  }
}

/// Honorific salutation. The codebase stores gender as free text (see
/// `Employee.honorific`), so we tolerate 'Male'/'M'/'MALE' and
/// 'Female'/'F'/'FEMALE'. Falls back to plain "Dear {lastName}" when
/// unknown.
String _salutation(String gender, String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  final lastName = parts.isEmpty ? '' : parts.last;
  final g = gender.trim().toLowerCase();
  if (g.startsWith('f')) return 'Dear Ms. $lastName';
  if (g.startsWith('m')) return 'Dear Mr. $lastName';
  return 'Dear $lastName';
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
