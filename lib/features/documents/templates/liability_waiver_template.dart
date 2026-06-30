import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/emphasis_paragraph_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/letterhead_block.dart';
import '../blocks/lettered_list_block.dart';
import '../blocks/signature_line_block.dart';
import '../blocks/spacer_block.dart';
import '../brand_logo.dart';
import '../providers.dart';
import 'document_template.dart';
import 'liability_waiver_inputs.dart';
import 'liability_waiver_validate.dart';

// Canonical clause text lifted verbatim from
// `~/Downloads/Liability Waiver for Company Outings Outside Metro Manila.pdf`.
// Confirm wording with the user before merge.

// §2 — acknowledgements (lettered a-e).
const List<String> _s2Acknowledgements = <String>[
  'I voluntarily accept the Company-sponsored Trip, the itinerary of which has been carefully explained to me by the Company.',
  'I hereby release, waive, discharge, and covenant not to sue the Company, including its incorporators, officers, employees, agents, and representatives, from any and all liability, claims, demands, actions, or causes of action whatsoever, arising out of or relating to any loss, damage, or injury, including death, that may be sustained by me or any of my personal property during the duration of the Trip.',
  'I further agree to indemnify and hold harmless the Company, its incorporators, officers, employees, agents, and representatives from any loss, liability, or costs they may incur as a result of my actions during the Trip.',
  'It is my express intent that this Travel Release and Waiver shall bind my family members, heirs, assigns, and personal representatives, if I am deceased, and shall be deemed as a release, waiver, discharge, and covenant not to sue the Company for any accident, injury, or loss that occurs during the Trip.',
  'I understand that this waiver does not release the Company from gross negligence or intentional misconduct.',
];

// §3 — affirmations (lettered a-c).
const List<String> _s3Affirmations = <String>[
  'I am physically fit and capable of participating in the Trip. I understand the risks involved and have not been advised otherwise by a medical professional.',
  'I will comply with all safety protocols, guidelines, and instructions provided by the Company during the Trip.',
  'I will assume full responsibility for any personal items I bring on the Trip and understand the Company is not liable for loss or theft of such items.',
];

// §4 — medical and emergency consent body (after the bold lead).
const String _s4MedicalConsent =
    'In the event of an emergency, I authorize the Company or its representatives to provide or arrange for emergency medical treatment, if deemed necessary. I understand that any medical expenses incurred will be my responsibility unless otherwise covered by insurance or the Company.';

class LiabilityWaiverTemplate
    extends DocumentTemplate<LiabilityWaiverInputs> {
  const LiabilityWaiverTemplate();

  @override
  String get id => 'liability_waiver';
  @override
  String get name => 'Liability Waiver (Company Outing)';
  @override
  String get description => 'Travel release & waiver for company outings.';
  @override
  IconData get icon => Icons.health_and_safety_outlined;
  @override
  int get version => 1;
  @override
  bool get supportsBulk => true;

  @override
  LiabilityWaiverInputs emptyInputs() => LiabilityWaiverInputs(
        employeeId: '',
        employeeFullName: '',
        employeeAddress: '',
        companyId: '',
        companyName: '',
        dateOfEmployment: null,
        outingDate: null,
        outingLocation: '',
        dateSigned: DateTime.now(),
        signingPlace: '',
      );

  @override
  Future<LiabilityWaiverInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();

    // Latest HIRE event seeds the date of employment; fall back to the
    // employee's hireDate. Wrapped so dev/test envs without Supabase
    // degrade gracefully (mirrors the Employment Contract autofill).
    Map<String, dynamic>? hireRow;
    try {
      hireRow = await ctx.ref.read(latestEmploymentEventProvider(
              (employeeId: emp.id, eventType: 'HIRE'))
          .future);
    } catch (_) {
      hireRow = null;
    }
    DateTime? eventDate(Map<String, dynamic>? r) {
      if (r == null) return null;
      final v = r['event_date'] as String?;
      return v == null ? null : DateTime.parse(v);
    }

    final dateOfEmployment = eventDate(hireRow) ?? emp.hireDate;

    final signingPlace = co == null
        ? ''
        : [co.city, co.province]
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .join(', ');

    final logo = await loadCompanyLogoBytes(co);
    return LiabilityWaiverInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeAddress: _composeAddress(
        emp.addressLine1,
        emp.addressLine2,
        emp.city,
        emp.province,
        emp.zipCode,
      ),
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      dateOfEmployment: dateOfEmployment,
      // Outing details are event-specific; entered manually.
      outingDate: null,
      outingLocation: '',
      dateSigned: today,
      signingPlace: signingPlace,
      logoBytes: logo,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(LiabilityWaiverInputs inputs) =>
      validateLiabilityWaiver(inputs);

  @override
  List<Block> build(LiabilityWaiverInputs i) {
    final fmt = DateFormat('MMMM d, yyyy');
    String dateOrDash(DateTime? d) => d == null ? '—' : fmt.format(d);
    final signed = i.dateSigned;

    return [
      if (i.logoBytes != null || i.companyName.isNotEmpty)
        LetterheadBlock(logoBytes: i.logoBytes, companyName: i.companyName),
      const SpacerBlock(16),
      // 1. Title — left-aligned bold heading (not a big centered TitleBlock).
      const HeadingBlock('Travel Release and Waiver'),
      const SpacerBlock(12),

      // 2. Intro.
      EmphasisParagraphBlock(spans: [
        const EmphasisSpan('I, '),
        EmphasisSpan(i.employeeFullName, bold: true),
        const EmphasisSpan(
            ', of legal age, Filipino, and a resident of '),
        EmphasisSpan(i.employeeAddress, bold: true),
        const EmphasisSpan(
            ', sworn in accordance with law, do hereby depose and state:'),
      ]),
      const SpacerBlock(8),

      // 3. Item 1 — employment + outing details.
      EmphasisParagraphBlock(spans: [
        const EmphasisSpan('1.   I am an employee of '),
        EmphasisSpan(i.companyName, bold: true),
        const EmphasisSpan(' since '),
        EmphasisSpan(dateOrDash(i.dateOfEmployment), bold: true),
        const EmphasisSpan(
            ', and the Company shall be granting me participation in the '),
        const EmphasisSpan('Company Outing', bold: true),
        const EmphasisSpan(' scheduled on '),
        EmphasisSpan(dateOrDash(i.outingDate), bold: true),
        const EmphasisSpan(' at '),
        EmphasisSpan(i.outingLocation, bold: true),
        const EmphasisSpan('.'),
      ]),
      const SpacerBlock(6),

      // 4. Item 2 — acknowledgements (lettered a-e).
      const EmphasisParagraphBlock(spans: [
        EmphasisSpan(
            '2.   In connection with the outing (hereafter referred to as '
            'the "Trip"), I acknowledge and affirm the following:'),
      ]),
      const SpacerBlock(4),
      const LetteredListBlock(_s2Acknowledgements),
      const SpacerBlock(4),

      // 5. Item 3 — affirmations (lettered a-c).
      const EmphasisParagraphBlock(spans: [
        EmphasisSpan('3.   I affirm that:'),
      ]),
      const SpacerBlock(4),
      const LetteredListBlock(_s3Affirmations),
      const SpacerBlock(4),

      // 6. Item 4 — medical and emergency consent (bold lead).
      const SpacerBlock(6),
      const EmphasisParagraphBlock(spans: [
        EmphasisSpan('4.   '),
        EmphasisSpan('Medical and Emergency Consent', bold: true),
        EmphasisSpan(': '),
        EmphasisSpan(_s4MedicalConsent),
      ]),
      const SpacerBlock(6),

      // 7. Item 5 — voluntary execution.
      const EmphasisParagraphBlock(spans: [
        EmphasisSpan(
            '5.   Finally, I declare that I have read this document entitled '),
        EmphasisSpan('Travel Release and Waiver', bold: true),
        EmphasisSpan(
            ', and I fully understand every word of it and its meaning. I '
            'affix my signature voluntarily and freely, with full and '
            'complete knowledge of the meaning and intent of this document '
            'under existing laws.'),
      ]),

      // 8. Witness clause with ordinal date + place.
      const SpacerBlock(16),
      EmphasisParagraphBlock(spans: [
        EmphasisSpan(
            'IN WITNESS WHEREOF, I have hereunto set my hand this '
            '${_ordinal(signed.day)} day of '
            '${DateFormat('MMMM').format(signed)} ${signed.year} at '),
        EmphasisSpan(i.signingPlace, bold: true),
        const EmphasisSpan('.'),
      ]),

      // 9. Signature line — name omitted for hand-signing.
      const SpacerBlock(40),
      const SignatureLineBlock([
        SignatoryLine(role: 'Signature over Printed Name / Date'),
      ]),
    ];
  }
}

/// Joins the individual nullable address parts into a single
/// comma-separated line, skipping any that are null or empty.
String _composeAddress(
  String? line1,
  String? line2,
  String? city,
  String? province,
  String? zipCode,
) =>
    [line1, line2, city, province, zipCode]
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .join(', ');

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
