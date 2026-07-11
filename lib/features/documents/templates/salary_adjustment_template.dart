import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../data/models/compensation_change.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/repositories/compensation_change_repository.dart';
import '../blocks/block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/letterhead_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import '../brand_logo.dart';
import '../providers.dart';
import 'document_template.dart';
import 'salary_adjustment_inputs.dart';
import 'salary_adjustment_validate.dart';

/// Working days per month used to estimate monthly pay on DAILY-rate notices.
/// Mirrors payroll's `standardWorkDaysPerMonth` (compute_service.dart).
const kStandardWorkDaysPerMonth = 26;

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

    final logo = await loadCompanyLogoBytes(c);

    // If a compensation change exists for this employee, render the notice
    // from it (exact prev/new snapshots) rather than inferring from the
    // scorecard alone. When the workflow threaded a specific change id via
    // [ctx.compensationChangeId], render THAT change (so an older change's
    // notice doesn't render the newest one's numbers). Otherwise the newest
    // non-cancelled change (by createdAt) wins.
    CompensationChange? change;
    try {
      final all = await ctx.ref.read(
        compensationChangesByEmployeeProvider(e?.id ?? '').future,
      );
      final linkedId = ctx.compensationChangeId;
      if (linkedId != null) {
        for (final cc in all) {
          if (cc.id == linkedId) {
            change = cc;
            break;
          }
        }
      }
      change ??= all
          .where((cc) => cc.status != 'CANCELLED')
          .fold<CompensationChange?>(
            null,
            (best, cc) =>
                best == null || cc.createdAt.isAfter(best.createdAt)
                    ? cc
                    : best,
          );
    } catch (_) {
      change = null;
    }

    final mode = change == null
        ? SalaryAdjustmentType.salaryAdjustment
        : _modeForChangeType(change.changeType);

    // Resolve the new position's title from the change's target scorecard,
    // mirroring the lookup used for the old position's scorecard above.
    RoleScorecard? newScorecard;
    final newScorecardId = change?.newScorecardId;
    if (newScorecardId != null && newScorecardId.isNotEmpty) {
      try {
        newScorecard = await ctx.ref.read(
          roleScorecardByIdProvider(newScorecardId).future,
        );
      } catch (_) {
        newScorecard = null;
      }
    }

    return SalaryAdjustmentInputs(
      type: mode,
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
      workDaysPerMonth: kStandardWorkDaysPerMonth,
      oldRoleScorecardId: change?.prevScorecardId ?? e?.roleScorecardId,
      newRoleScorecardId: change?.newScorecardId,
      oldPosition: e?.jobTitle ?? scorecard?.jobTitle ?? '',
      newPosition: newScorecard?.jobTitle ?? '',
      oldSalary: change?.prevBaseSalary ??
          e?.declaredWageOverride ??
          scorecard?.baseSalary ??
          Decimal.zero,
      newSalary: change?.newBaseSalary ?? Decimal.zero,
      salaryPeriod: change?.newWageType ?? scorecard?.wageType ?? 'MONTHLY',
      effectiveDate: change?.effectiveDate ?? firstOfNextMonth,
      issueDate: today,
      reason: change?.reason ?? '',
      logoBytes: logo,
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
    // On DAILY notices, help the employee estimate monthly pay. 26 is the
    // divisor payroll actually uses, so the figure reconciles with the payslip.
    final estimateClause = i.salaryPeriod == 'DAILY'
        ? ' (estimated at ${i.workDaysPerMonth} working days per month)'
        : '';
    final salutation = _salutation(i.employeeGender, i.employeeFullName);
    final subject = switch (i.type) {
      SalaryAdjustmentType.promotion => 'Notice of Promotion',
      SalaryAdjustmentType.lateral => 'Notice of Lateral Transfer',
      SalaryAdjustmentType.demotion => 'Notice of Change in Role',
      SalaryAdjustmentType.salaryAdjustment => 'Notice of Salary Adjustment',
    };

    final bodyText = switch (i.type) {
      SalaryAdjustmentType.promotion =>
        'We are pleased to inform you that, effective '
            '${df.format(i.effectiveDate)}, you are being promoted from '
            '${i.oldPosition} to ${i.newPosition}. In line with this '
            'promotion, your $periodLabel will be adjusted from '
            '${cf.format(i.oldSalary.toDouble())} to '
            '${cf.format(i.newSalary.toDouble())}$estimateClause. ${i.reason}',
      SalaryAdjustmentType.lateral =>
        'We wish to inform you that, effective '
            '${df.format(i.effectiveDate)}, you are being transferred from '
            '${i.oldPosition} to ${i.newPosition}. Your $periodLabel remains '
            'unchanged at ${cf.format(i.oldSalary.toDouble())}$estimateClause. '
            '${i.reason}',
      SalaryAdjustmentType.demotion =>
        'We wish to inform you that, effective '
            '${df.format(i.effectiveDate)}, your role will change from '
            '${i.oldPosition} to ${i.newPosition}, and your $periodLabel '
            'will be adjusted from ${cf.format(i.oldSalary.toDouble())} to '
            '${cf.format(i.newSalary.toDouble())}$estimateClause. ${i.reason}',
      SalaryAdjustmentType.salaryAdjustment =>
        'We are pleased to inform you that, effective '
            '${df.format(i.effectiveDate)}, your $periodLabel will be '
            'adjusted from ${cf.format(i.oldSalary.toDouble())} to '
            '${cf.format(i.newSalary.toDouble())}$estimateClause. ${i.reason}',
    };

    return <Block>[
      if (i.logoBytes != null || i.companyName.isNotEmpty)
        LetterheadBlock(
          logoBytes: i.logoBytes,
          companyName: i.companyName,
          companyAddress: i.companyAddress.isEmpty ? null : i.companyAddress,
        ),
      const SpacerBlock(16),
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

/// Maps a `compensation_changes.change_type` value to the notice mode it
/// should render as. SALARY_INCREASE/SALARY_DECREASE both render as the
/// plain salary-adjustment notice.
SalaryAdjustmentType _modeForChangeType(String changeType) =>
    switch (changeType) {
      'PROMOTION' => SalaryAdjustmentType.promotion,
      'LATERAL_TRANSFER' => SalaryAdjustmentType.lateral,
      'DEMOTION' => SalaryAdjustmentType.demotion,
      _ => SalaryAdjustmentType.salaryAdjustment,
    };
