import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../core/pdf/interpolate.dart';
import '../brand_logo.dart';
import '../blocks/block.dart';
import '../blocks/company_header_block.dart';
import '../blocks/logo_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/signature_block.dart';
import '../blocks/spacer_block.dart';
import '../blocks/title_block.dart';
import 'coe_gates.dart';
import 'coe_inputs.dart';
import 'coe_validate.dart';
import 'document_template.dart';

// PLACEHOLDER — engineer MUST replace with canonical wording from
// JAM employee record PDFs in Phase 8 Task 40. Confirm with user.
const _coeBodyText =
    'This is to certify that {employeeFullName} was employed with '
    '{companyName} as {position} from {dateStart} to {dateEnd}.';

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
        companyId: '',
        companyName: '',
        position: '',
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
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      hrManagerName: co?.hrManagerName,
      position: emp.jobTitle ?? '',
      dateStart: emp.hireDate,
      dateEnd: emp.separationDate,
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
    return [
      if (i.logoBytes != null) LogoBlock(i.logoBytes!),
      if (i.logoBytes != null) const SpacerBlock(12),
      CompanyHeaderBlock(name: i.companyName, address: i.companyAddress),
      const SpacerBlock(24),
      const TitleBlock('CERTIFICATE OF EMPLOYMENT'),
      const SpacerBlock(24),
      const ParagraphBlock('TO WHOM IT MAY CONCERN:'),
      const SpacerBlock(12),
      ParagraphBlock(
        interpolate(
          _coeBodyText,
          {
            'employeeFullName': i.employeeFullName,
            'position': i.position,
            'companyName': i.companyName,
            'dateStart': i.dateStart == null ? '—' : fmt.format(i.dateStart!),
            'dateEnd': i.dateEnd == null ? '—' : fmt.format(i.dateEnd!),
          },
          lenient: true,
        ),
      ),
      ParagraphBlock(
        'This certification is issued upon the request of ${i.employeeFullName} '
        'for whatever legal purpose it may serve.',
      ),
      const SpacerBlock(48),
      SignatureBlock(
        name: i.hrManagerName,
        role: 'HR Manager — ${i.companyName}',
        date: DateTime.now(),
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
