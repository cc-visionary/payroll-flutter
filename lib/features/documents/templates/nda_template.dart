import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/bullet_list_block.dart';
import '../blocks/emphasis_paragraph_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/lettered_list_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/party_block.dart';
import '../blocks/section_heading_block.dart';
import '../blocks/signature_line_block.dart';
import '../blocks/spacer_block.dart';
import '../blocks/title_block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'nda_inputs.dart';
import 'nda_validate.dart';

// Canonical NDA clause text lifted verbatim from
// `~/Downloads/Confidentiality and Non-Disclosure Agreement (Upon
// Employment).pdf`, mirrored in the design spec
// `docs/superpowers/specs/2026-05-23-nda-template-design.md`
// ("Canonical section text"). Inline-bold phrases are split across const
// fragments so build() can assemble them as EmphasisParagraphBlock spans.

// §1 PARTIES — intro (party sub-fields are data-driven, built inline).
const String _s1Intro =
    'This Confidentiality and Non-Disclosure Agreement ("Agreement") is '
    'entered into by and between:';

// §2 PURPOSE — P2 bolds "during employment and after the termination of
// employment".
const String _s2PurposeP1 =
    'In the course of employment, the Employee will have access to '
    'confidential, proprietary, and sensitive information belonging to the '
    'Company, its affiliates, clients, customers, suppliers, and partners.';
const String _s2PurposeP2Before =
    "This Agreement defines the Employee's obligation to protect such "
    'information ';
const String _s2PurposeP2Bold =
    'during employment and after the termination of employment';
const String _s2PurposeP2After =
    ', regardless of the cause or manner of separation.';

// §3 DEFINITION OF CONFIDENTIAL INFORMATION.
const String _s3Intro =
    '"Confidential Information" refers to any non-public information, whether '
    'oral, written, electronic, visual, or in any other form, disclosed to '
    'or accessed by the Employee by reason of employment, including but not '
    'limited to:';
const List<String> _s3Bullets = <String>[
  'Business strategies, plans, financial data, pricing, margins, forecasts, '
      'analytics, and reports',
  'Supplier lists, sourcing arrangements, contracts, inventory, logistics, '
      'and procurement data',
  'Customer and client information, databases, marketing plans, advertising '
      'accounts, voucher codes, and campaign results',
  'Product designs, specifications, formulas, prototypes, systems, software, '
      'source code, technical documentation, and workflows',
  'Trade secrets, know-how, SOPs, manuals, training materials, scripts, '
      'internal policies, and internal communications',
  'Employment, payroll, compensation, and human resources information',
  'Any information that a reasonable person would understand to be '
      'confidential or proprietary',
];
const String _s3Close =
    'Confidential Information need not be novel, patentable, copyrightable, '
    'or constitute a trade secret to be protected.';

// §4 EXCLUDED INFORMATION — intro bolds "not".
const String _s4IntroBefore = 'Confidential Information does ';
const String _s4IntroBold = 'not';
const String _s4IntroAfter = ' include information that:';
const List<String> _s4Lettered = <String>[
  'Is publicly available through no breach of this Agreement;',
  'Is independently developed by the Employee without use of Company '
      'resources or Confidential Information;',
  'Is lawfully obtained from a third party without breach of any duty of '
      'confidentiality; or',
  'Was already known to the Employee prior to disclosure, as evidenced by '
      'written records.',
];

// §5 EMPLOYEE OBLIGATIONS — sub-sections 5.1–5.5. 5.4 bolds "subject to
// applicable labor laws".
const String _s51 =
    'The Employee shall not disclose, publish, transmit, or make available '
    'any Confidential Information to any person or entity without the prior '
    'written consent of the Company.';
const String _s52 =
    'The Employee shall use Confidential Information solely for legitimate '
    'Company business purposes and shall not use such information for '
    'personal benefit or for the benefit of any third party or competing '
    'business.';
const String _s53 =
    'The Employee shall exercise reasonable care, not less than the care '
    'used to protect their own confidential information, to prevent '
    'unauthorized access, loss, misuse, or disclosure of Confidential '
    'Information.';
const String _s54P1Before =
    'Upon request or upon termination of employment, and ';
const String _s54P1Bold = 'subject to applicable labor laws';
const String _s54P1After =
    ', the Employee shall immediately return or permanently delete all '
    'Company property and Confidential Information, including documents, '
    'files, devices, storage media, credentials, access keys, and copies '
    'thereof.';
const String _s54P2 =
    'The Company may require written certification that no copies remain in '
    "the Employee's possession or control.";
const String _s55 =
    'The Employee shall promptly notify the Company upon discovery of any '
    'actual or suspected unauthorized disclosure, loss, or misuse of '
    'Confidential Information.';

// §6 DURATION OF OBLIGATIONS (SURVIVAL) — bolds the survival phrase.
const String _s6Before =
    'The obligations under this Agreement shall survive the termination of '
    'employment ';
const String _s6Bold =
    'for as long as the Confidential Information remains confidential and '
    'proprietary';
const String _s6After =
    ', and shall cease to apply once such information enters the public '
    'domain through no breach of this Agreement.';

// §7 USE OF GENERAL SKILLS AND EXPERIENCE.
const String _s7 =
    'Nothing in this Agreement shall be construed to prohibit the Employee '
    'from using general skills, knowledge, experience, or expertise acquired '
    'during employment, provided that no Confidential Information of the '
    'Company is disclosed or misused.';

// §8 COMPULSORY OR LEGALLY REQUIRED DISCLOSURE.
const String _s8 =
    'The Employee may disclose Confidential Information if required by law, '
    'regulation, court order, or government authority, provided that the '
    'Employee, to the extent legally permissible, promptly notifies the '
    'Company prior to such disclosure to allow the Company to seek '
    'protective measures.';

// §9 OWNERSHIP OF INFORMATION.
const String _s9 =
    'All Confidential Information remains the exclusive property of the '
    'Company. No license, ownership interest, or other rights are granted to '
    'the Employee except as strictly necessary to perform assigned duties '
    'during employment.';

// §10 RELATIONSHIP TO EMPLOYMENT CONTRACT — P2 bolds "after employment".
const String _s10P1 =
    'This Agreement supplements, and does not replace, any confidentiality '
    "obligations under the Employee's Employment Contract or Company "
    'policies.';
const String _s10P2Before =
    'In the event of inconsistency, this Agreement shall govern '
    'confidentiality obligations ';
const String _s10P2Bold = 'after employment';
const String _s10P2After = '.';

// §11 REMEDIES.
const String _s11P1 =
    'The Employee acknowledges that unauthorized disclosure or misuse of '
    'Confidential Information may cause irreparable harm to the Company.';
const String _s11P2 = 'Accordingly, the Company shall be entitled to:';
const List<String> _s11Bullets = <String>[
  'Injunctive relief',
  'Damages (actual, consequential, and exemplary where applicable)',
  "Attorney's fees and costs",
  'Any other remedies available under law or equity',
];
const String _s11Close = 'without the necessity of posting bond.';

// §12 NO WAIVER OF LABOR RIGHTS.
const String _s12 =
    'Nothing in this Agreement shall be interpreted as a waiver of any '
    'rights or benefits granted to the Employee under the Labor Code of the '
    'Philippines, DOLE issuances, or other applicable labor laws.';

// §13 SEVERABILITY.
const String _s13 =
    'If any provision of this Agreement is held to be invalid or '
    'unenforceable, the remaining provisions shall remain in full force and '
    'effect.';

// §14 GOVERNING LAW AND VENUE — bolds "Republic of the Philippines".
const String _s14Before =
    'This Agreement shall be governed by and construed in accordance with '
    'the laws of the ';
const String _s14Bold = 'Republic of the Philippines';
const String _s14After =
    '. Any dispute arising from this Agreement shall be filed with the '
    'proper courts of competent jurisdiction in the Philippines.';

// §15 ENTIRE AGREEMENT.
const String _s15 =
    'This Agreement constitutes the entire agreement between the Parties '
    'concerning confidentiality obligations during and after employment and '
    'supersedes all prior oral or written agreements on this subject.';

// §16 ACKNOWLEDGMENT — last bullet bolds "condition of employment".
const String _s16Intro =
    'By signing below, the Employee acknowledges that he/she:';
const List<String> _s16PlainBullets = <String>[
  'Has read and fully understood this Agreement',
  'Entered into this Agreement voluntarily',
  'Had the opportunity to seek independent legal advice',
];
const String _s16LastBulletBefore =
    'Understands that execution of this Agreement is a ';
const String _s16LastBulletBold = 'condition of employment';
const String _s16WitnessClause =
    'IN WITNESS WHEREOF, the Parties have executed this Agreement on the '
    'date first written above.';

// Section titles in order (§1..§16).
const List<String> _sectionTitles = <String>[
  'PARTIES',
  'PURPOSE',
  'DEFINITION OF CONFIDENTIAL INFORMATION',
  'EXCLUDED INFORMATION',
  'EMPLOYEE OBLIGATIONS',
  'DURATION OF OBLIGATIONS (SURVIVAL)',
  'USE OF GENERAL SKILLS AND EXPERIENCE',
  'COMPULSORY OR LEGALLY REQUIRED DISCLOSURE',
  'OWNERSHIP OF INFORMATION',
  'RELATIONSHIP TO EMPLOYMENT CONTRACT',
  'REMEDIES',
  'NO WAIVER OF LABOR RIGHTS',
  'SEVERABILITY',
  'GOVERNING LAW AND VENUE',
  'ENTIRE AGREEMENT',
  'ACKNOWLEDGMENT',
];

class NdaTemplate extends DocumentTemplate<NdaInputs> {
  const NdaTemplate();
  @override
  String get id => 'nda';
  @override
  String get name => 'Confidentiality & Non-Disclosure Agreement';
  @override
  String get description => 'NDA signed upon employment.';
  @override
  IconData get icon => Icons.lock_outline;
  @override
  int get version => 1;
  @override
  bool get supportsBulk => true;

  @override
  NdaInputs emptyInputs() => NdaInputs(
        employeeId: '',
        employeeFullName: '',
        companyId: '',
        companyName: '',
      );

  @override
  Future<NdaInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    DateTime? hireDate;
    try {
      final row = await ctx.ref.read(latestEmploymentEventProvider(
              (employeeId: emp.id, eventType: 'HIRE'))
          .future);
      final v = row?['event_date'] as String?;
      hireDate = v == null ? null : DateTime.parse(v);
    } catch (_) {
      hireDate = null;
    }
    return NdaInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeePosition: emp.jobTitle ?? '',
      employeeHomeAddress: _composeAddress(emp.addressLine1, emp.addressLine2,
          emp.city, emp.province, emp.zipCode),
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null
          ? ''
          : _composeAddress(co.addressLine1, co.addressLine2, co.city,
              co.province, co.zipCode),
      effectiveDate: hireDate ?? emp.hireDate,
      authorizedSignatoryName: (co?.legalSignatoryName?.isNotEmpty == true)
          ? co!.legalSignatoryName!
          : (co?.hrManagerName ?? ''),
      authorizedSignatoryRole: (co?.legalSignatoryRole?.isNotEmpty == true)
          ? co!.legalSignatoryRole!
          : 'Authorized Signatory',
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];
  @override
  List<ValidationError> validate(NdaInputs inputs) => validateNda(inputs);
  @override
  List<Block> build(NdaInputs i) {
    final fmt = DateFormat('MMMM d, yyyy');
    final effective =
        i.effectiveDate == null ? '________________' : fmt.format(i.effectiveDate!);

    final blocks = <Block>[];

    blocks.add(const TitleBlock(
      'Confidentiality & Non-Disclosure Agreement',
      centered: true,
    ));
    blocks.add(const SpacerBlock(16));

    // §1 PARTIES (data-driven).
    blocks.add(SectionHeadingBlock(number: 1, title: _sectionTitles[0]));
    blocks.add(const ParagraphBlock(_s1Intro));
    blocks.add(const SpacerBlock(6));
    blocks.add(PartyBlock(spans: [
      const EmphasisSpan('Employer:  ', bold: true),
      EmphasisSpan(i.companyName, bold: true),
      EmphasisSpan(
          ', a corporation duly organized and existing under Philippine laws, '
          'with principal office at ${i.companyAddress} ('),
      const EmphasisSpan('"Company"', bold: true),
      const EmphasisSpan(').'),
    ]));
    blocks.add(const SpacerBlock(6));
    blocks.add(PartyBlock(spans: [
      const EmphasisSpan('Name: ', bold: true),
      EmphasisSpan(i.employeeFullName),
    ]));
    blocks.add(PartyBlock(spans: [
      const EmphasisSpan('Position/Role: ', bold: true),
      EmphasisSpan(i.employeePosition),
    ]));
    blocks.add(PartyBlock(spans: [
      const EmphasisSpan('Home Address: ', bold: true),
      EmphasisSpan(i.employeeHomeAddress),
      const EmphasisSpan(' ('),
      const EmphasisSpan('"Employee"', bold: true),
      const EmphasisSpan(').'),
    ]));
    blocks.add(const SpacerBlock(6));
    blocks.add(PartyBlock(spans: [
      const EmphasisSpan('Effective Date: ', bold: true),
      EmphasisSpan(effective),
      const EmphasisSpan(' (Start Date of Employment)'),
    ]));

    // §2..§16 — numbered sections of canonical text.
    void section(int n, List<Block> body) {
      blocks.add(const SpacerBlock(12));
      blocks.add(SectionHeadingBlock(number: n, title: _sectionTitles[n - 1]));
      blocks.addAll(body);
    }

    // §2 PURPOSE.
    section(2, const [
      ParagraphBlock(_s2PurposeP1),
      SpacerBlock(6),
      EmphasisParagraphBlock(spans: [
        EmphasisSpan(_s2PurposeP2Before),
        EmphasisSpan(_s2PurposeP2Bold, bold: true),
        EmphasisSpan(_s2PurposeP2After),
      ]),
    ]);

    // §3 DEFINITION OF CONFIDENTIAL INFORMATION.
    section(3, const [
      ParagraphBlock(_s3Intro),
      SpacerBlock(4),
      BulletListBlock(_s3Bullets),
      SpacerBlock(4),
      ParagraphBlock(_s3Close),
    ]);

    // §4 EXCLUDED INFORMATION.
    section(4, const [
      EmphasisParagraphBlock(spans: [
        EmphasisSpan(_s4IntroBefore),
        EmphasisSpan(_s4IntroBold, bold: true),
        EmphasisSpan(_s4IntroAfter),
      ]),
      SpacerBlock(4),
      LetteredListBlock(_s4Lettered),
    ]);

    // §5 EMPLOYEE OBLIGATIONS — sub-headings 5.1–5.5.
    section(5, const [
      HeadingBlock('5.1 Non-Disclosure'),
      ParagraphBlock(_s51),
      SpacerBlock(6),
      HeadingBlock('5.2 Non-Use'),
      ParagraphBlock(_s52),
      SpacerBlock(6),
      HeadingBlock('5.3 Safekeeping'),
      ParagraphBlock(_s53),
      SpacerBlock(6),
      HeadingBlock('5.4 Return or Deletion of Company Property'),
      EmphasisParagraphBlock(spans: [
        EmphasisSpan(_s54P1Before),
        EmphasisSpan(_s54P1Bold, bold: true),
        EmphasisSpan(_s54P1After),
      ]),
      SpacerBlock(6),
      ParagraphBlock(_s54P2),
      SpacerBlock(6),
      HeadingBlock('5.5 Notification of Breach'),
      ParagraphBlock(_s55),
    ]);

    // §6 DURATION OF OBLIGATIONS (SURVIVAL).
    section(6, const [
      EmphasisParagraphBlock(spans: [
        EmphasisSpan(_s6Before),
        EmphasisSpan(_s6Bold, bold: true),
        EmphasisSpan(_s6After),
      ]),
    ]);

    // §7 USE OF GENERAL SKILLS AND EXPERIENCE.
    section(7, const [ParagraphBlock(_s7)]);

    // §8 COMPULSORY OR LEGALLY REQUIRED DISCLOSURE.
    section(8, const [ParagraphBlock(_s8)]);

    // §9 OWNERSHIP OF INFORMATION.
    section(9, const [ParagraphBlock(_s9)]);

    // §10 RELATIONSHIP TO EMPLOYMENT CONTRACT.
    section(10, const [
      ParagraphBlock(_s10P1),
      SpacerBlock(6),
      EmphasisParagraphBlock(spans: [
        EmphasisSpan(_s10P2Before),
        EmphasisSpan(_s10P2Bold, bold: true),
        EmphasisSpan(_s10P2After),
      ]),
    ]);

    // §11 REMEDIES.
    section(11, const [
      ParagraphBlock(_s11P1),
      SpacerBlock(6),
      ParagraphBlock(_s11P2),
      SpacerBlock(4),
      BulletListBlock(_s11Bullets),
      SpacerBlock(4),
      ParagraphBlock(_s11Close),
    ]);

    // §12 NO WAIVER OF LABOR RIGHTS.
    section(12, const [ParagraphBlock(_s12)]);

    // §13 SEVERABILITY.
    section(13, const [ParagraphBlock(_s13)]);

    // §14 GOVERNING LAW AND VENUE.
    section(14, const [
      EmphasisParagraphBlock(spans: [
        EmphasisSpan(_s14Before),
        EmphasisSpan(_s14Bold, bold: true),
        EmphasisSpan(_s14After),
      ]),
    ]);

    // §15 ENTIRE AGREEMENT.
    section(15, const [ParagraphBlock(_s15)]);

    // §16 ACKNOWLEDGMENT — plain bullets + a bold-bearing last bullet.
    section(16, [
      const ParagraphBlock(_s16Intro),
      const SpacerBlock(4),
      const BulletListBlock(_s16PlainBullets),
      // Last acknowledgment item carries an inline-bold phrase, so it renders
      // as its own EmphasisParagraphBlock with a leading bullet glyph rather
      // than inside the plain BulletListBlock above.
      EmphasisParagraphBlock(spans: const [
        EmphasisSpan('•  '),
        EmphasisSpan(_s16LastBulletBefore),
        EmphasisSpan(_s16LastBulletBold, bold: true),
      ]),
    ]);

    // Witness clause.
    blocks.add(const SpacerBlock(24));
    blocks.add(const ParagraphBlock(_s16WitnessClause));

    // Two-column signature block. Header ("For the Company" / "Recipient"),
    // signature line, name, role, and "Date:" line all live inside a single
    // SignatureLineBlock so each column is one aligned stack — the columns
    // share the same Expanded width and line up exactly.
    blocks.add(const SpacerBlock(24));
    blocks.add(SignatureLineBlock(
      [
        SignatoryLine(
          header: 'For the Company',
          name: i.authorizedSignatoryName,
          role: i.authorizedSignatoryRole,
        ),
        SignatoryLine(
          header: 'Recipient',
          name: i.employeeFullName,
          role: 'Signature over Printed Name',
        ),
      ],
      row: true,
      showDate: true,
    ));

    return blocks;
  }
}

String _composeAddress(
    String? l1, String? l2, String? city, String? prov, String? zip) {
  final tail = [city, prov, zip].where((s) => s != null && s.isNotEmpty).join(', ');
  return [l1, l2, tail]
      .where((s) => s != null && s.isNotEmpty)
      .cast<String>()
      .join(', ');
}
