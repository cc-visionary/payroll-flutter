import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../brand_logo.dart';
import '../blocks/block.dart';
import '../blocks/emphasis_paragraph_block.dart';
import '../blocks/logo_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import '../blocks/title_block.dart';
import 'coe_gates.dart';
import 'coe_inputs.dart';
import 'coe_validate.dart';
import 'document_template.dart';

class CoeTemplate extends DocumentTemplate<CoeInputs> {
  const CoeTemplate();

  @override
  String get id => 'coe';
  @override
  String get name => 'Certificate of Employment';
  @override
  String get description => 'Issued only after an employee has separated.';
  @override
  IconData get icon => Icons.workspace_premium_outlined;
  @override
  int get version => 1;

  @override
  CoeInputs emptyInputs() => CoeInputs(
        employeeId: '',
        employeeFullName: '',
        employeeLastName: '',
        employeeHonorific: '',
        companyId: '',
        companyName: '',
        position: '',
        place: '',
        dateIssued: DateTime.now(),
      );

  @override
  Future<CoeInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final logo = await loadBrandLogoBytes(
      companyName: co?.name,
      code: co?.code,
    );
    // Dates come straight off the Employee row, which is the source of
    // truth (hireDate is set at onboarding; separationDate is set when a
    // separation is confirmed). We do NOT query employment_events here —
    // the event_type enum has no 'SEPARATION' member (it uses
    // SEPARATION_CONFIRMED / SEPARATION_INITIATED), and the employee row
    // already carries the authoritative dates.
    return CoeInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeLastName: emp.lastName,
      employeeHonorific: emp.honorific,
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      hrManagerName: co?.hrManagerName,
      position: emp.jobTitle ?? '',
      place: co == null ? '' : _addressOf(co),
      dateStart: emp.hireDate,
      dateEnd: emp.separationDate,
      dateIssued: DateTime.now(),
      logoBytes: logo,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) {
    final emp = ctx.employee;
    if (emp == null) return const [];
    return computeCoeGates(
      hasSeparationEvent: false,
      employmentStatus: emp.employmentStatus,
    );
  }

  @override
  List<ValidationError> validate(CoeInputs inputs) => validateCoe(inputs);

  @override
  List<Block> build(CoeInputs i) {
    final fmt = DateFormat('MMMM d, yyyy');
    final issued = i.dateIssued;
    final honor = i.employeeHonorific.isEmpty ? 'Mr./Ms.' : i.employeeHonorific;
    final start = i.dateStart == null ? '—' : fmt.format(i.dateStart!);
    final end = i.dateEnd == null ? '—' : fmt.format(i.dateEnd!);
    return [
      if (i.logoBytes != null)
        LogoBlock(i.logoBytes!, height: 100, alignment: pw.Alignment.center),
      if (i.logoBytes != null) const SpacerBlock(16),
      const TitleBlock('CERTIFICATE OF EMPLOYMENT', centered: true),
      const SpacerBlock(16),
      const EmphasisParagraphBlock(
        spans: [EmphasisSpan('To Whom It May Concern:', bold: true)],
        align: pw.TextAlign.center,
      ),
      const SpacerBlock(8),
      ParagraphBlock(
        'This is to certify that ${i.employeeFullName} was an employee of '
        '${i.companyName.toUpperCase()} From $start up to $end as '
        '${i.position.toUpperCase()}.',
        align: pw.TextAlign.center,
      ),
      const SpacerBlock(12),
      ParagraphBlock(
        'This certification is issued to $honor ${i.employeeLastName} as part '
        "of the Company's standard post-employment clearance and exit "
        'procedures.',
        align: pw.TextAlign.center,
      ),
      const SpacerBlock(12),
      ParagraphBlock(
        'Given this ${_ordinal(issued.day)} day of '
        '${DateFormat('MMMM').format(issued)} ${issued.year} at ${i.place}.',
        align: pw.TextAlign.center,
      ),
      const SpacerBlock(48),
      EmphasisParagraphBlock(
        spans: [EmphasisSpan((i.hrManagerName ?? '').toUpperCase(), bold: true)],
        align: pw.TextAlign.center,
      ),
      const EmphasisParagraphBlock(
        spans: [EmphasisSpan('HR MANAGER', bold: true)],
        align: pw.TextAlign.center,
      ),
    ];
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

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}
