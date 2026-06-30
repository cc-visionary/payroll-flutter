import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../data/models/role_scorecard.dart';
import '../brand_logo.dart';
import '../blocks/block.dart';
import '../blocks/bullet_list_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/memo_header_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'regularization_inputs.dart';
import 'regularization_validate.dart';

class RegularizationTemplate extends DocumentTemplate<RegularizationInputs> {
  const RegularizationTemplate();

  @override
  String get id => 'regularization';

  @override
  String get name => 'Probationary Regularization';

  @override
  String get description =>
      'Confirms an employee\'s transition from probationary to regular status.';

  @override
  IconData get icon => Icons.verified_outlined;

  @override
  int get version => 1;

  @override
  bool get supportsBulk => true;

  @override
  RegularizationInputs emptyInputs() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return RegularizationInputs(
      employeeId: '',
      employeeFullName: '',
      companyId: '',
      companyName: '',
      regularizationDate: today,
      baseSalary: Decimal.zero,
      issueDate: today,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) {
    final e = ctx.employee;
    if (e != null && e.employmentType != 'PROBATIONARY') {
      return const [
        Gate('Regularization is only valid for probationary employees.'),
      ];
    }
    return const [];
  }

  @override
  Future<RegularizationInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

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
    return RegularizationInputs(
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
      hireDate: e?.hireDate,
      regularizationDate: today,
      baseSalary:
          e?.declaredWageOverride ?? scorecard?.baseSalary ?? Decimal.zero,
      salaryPeriod: scorecard?.wageType ?? 'MONTHLY',
      issueDate: today,
      logoBytes: logo,
    );
  }

  @override
  List<ValidationError> validate(RegularizationInputs inputs) =>
      validateRegularization(inputs);

  @override
  List<Block> build(RegularizationInputs i) {
    final df = DateFormat('MMMM d, yyyy');
    final cf = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final hireStr = i.hireDate != null ? df.format(i.hireDate!) : '___';
    final salaryLine = i.salaryPeriod == 'DAILY'
        ? 'Daily rate: ${cf.format(i.baseSalary.toDouble())}'
        : 'Monthly salary: ${cf.format(i.baseSalary.toDouble())}';
    final honorific = _honorific(i.employeeGender);

    final blocks = <Block>[
      MemoHeaderBlock(
        titleText: 'CONFIRMATION OF REGULARIZATION',
        companyName: i.companyName,
        companyAddress: i.companyAddress,
        date: i.issueDate,
        to: LetterParty(
          name: i.employeeFullName,
          subtitle: i.employeePosition.isEmpty ? null : i.employeePosition,
        ),
        from: LetterParty(name: i.hrManagerName, subtitle: 'HR Manager'),
        subject: 'Confirmation of Regularization',
        salutation: i.employeeFullName.isEmpty
            ? null
            : '$honorific ${_lastName(i.employeeFullName)},',
        logoBytes: i.logoBytes,
      ),
      const SpacerBlock(16),
      ParagraphBlock(
        'Congratulations! Following a comprehensive review of your '
        'performance during your probationary period (from $hireStr to '
        '${df.format(i.regularizationDate)}), ${i.companyName} is pleased '
        'to confirm your regularization effective '
        '${df.format(i.regularizationDate)}.',
      ),
    ];

    if (i.performanceSummary.trim().isNotEmpty) {
      blocks.add(const SpacerBlock(12));
      blocks.add(const HeadingBlock('Performance Summary'));
      blocks.add(ParagraphBlock(i.performanceSummary));
    }

    blocks.add(const SpacerBlock(12));
    blocks.add(const HeadingBlock('Terms'));
    blocks.add(
      BulletListBlock([
        'Effective date: ${df.format(i.regularizationDate)}',
        'Position: ${i.employeePosition}',
        salaryLine,
        'All other terms and benefits per your existing Employment Contract apply.',
      ]),
    );
    blocks.add(const SpacerBlock(12));
    blocks.add(
      ParagraphBlock(
        'We look forward to your continued contribution to ${i.companyName}. '
        'Please acknowledge receipt below.',
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
