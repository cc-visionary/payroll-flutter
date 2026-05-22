import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../core/pdf/interpolate.dart';
import '../../../data/models/role_scorecard.dart';

import '../blocks/block.dart';
import '../blocks/bullet_list_block.dart';
import '../blocks/emphasis_paragraph_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/lettered_list_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/numbered_list_block.dart';
import '../blocks/page_break_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/party_block.dart';
import '../blocks/section_heading_block.dart';
import '../blocks/spacer_block.dart';
import '../blocks/title_block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'employment_contract_inputs.dart';
import 'employment_contract_validate.dart';
import 'non_reg_template.dart' show defaultProbationaryEnd;

// Canonical clause text lifted verbatim from
// `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/Employment Contract
// Template_Vidal.pdf` (8 pages). Confirm wording with the user before
// merge (EC15 source-copy review).

const String _preambleIntro =
    'This Agreement entered into this {dateEntered}, at {place}, by and '
    'between:';

// EMPLOYER party — companyName rendered bold, address italic. EC9 assembles
// the EmphasisSpans from company data + these fixed connector fragments.
const String _employerPartyPrefix =
    ', a company duly organized and registered under the laws of the '
    'Philippines, with principal office address at ';
const String _employerPartyMid = ' herein represented by its ';
const String _employerPartySuffix = ', herein referred to as the "EMPLOYER"';

// EMPLOYEE party — employeeFullName bold, address italic.
const String _employeePartyPrefix = ', of legal age, with address at ';
const String _employeePartySuffix =
    ', hereinafter referred to as the "EMPLOYEE".';

const String _recital1 =
    'WHEREAS, the EMPLOYER is a corporation engaged in {industry};';
const String _recital2 =
    'WHEREAS, the EMPLOYEE has qualified in the pre-employment requirements '
    'conducted by the EMPLOYER;';
const String _recital3 =
    'WHEREAS, the EMPLOYER is interested in engaging the services of the '
    'EMPLOYEE as {position};';

const String _nowTherefore =
    'NOW, THEREFORE, for and in consideration of the foregoing premises, the '
    'parties hereby agree as follows:';

// §1 PROBATIONARY EMPLOYMENT
const String _s1ProbationaryEmployment =
    'Subject to the job performance, the EMPLOYER agrees to employ EMPLOYEE '
    'and EMPLOYEE agrees to remain in the employ of EMPLOYER on probation '
    'under the terms and conditions hereinafter set forth.';

// §2 JOB TITLE AND DESCRIPTION
const String _s2JobTitle =
    "The EMPLOYEE's probationary employment is as a {position}. A more "
    "specific description of the EMPLOYEE's duties, responsibilities and "
    'work hours is outlined in Annex "A" and made an integral part of this '
    'contract.';

// §3 PERIOD OF PROBATIONARY EMPLOYMENT — two paragraphs
const String _s3PeriodP1 =
    'The EMPLOYEE is employed on probationary status for a period of 6 '
    'months or 180 calendar days beginning on {probationStart} and ending '
    "on {probationEnd}. Prior to the expiration of the EMPLOYEE's "
    'probationary employment, he/she shall be notified in writing if he/she '
    'qualified as a regular employee.';
const String _s3PeriodP2 =
    'This employment is subject to the standards for regularization, which '
    'EMPLOYEE hereby acknowledges to have received and is aware of. These '
    'standards are outlined in Annex "B" which is made an integral part of '
    'this Contract.';

// §4 PROBATIONARY EVALUATION
const String _s4Evaluation =
    "The EMPLOYER will evaluate an employee's performance during the "
    "probationary period. The EMPLOYEE's immediate superior shall make "
    'evaluation or such other representative appointed by the EMPLOYER. The '
    'evaluation of the EMPLOYEE shall be made in writing. The EMPLOYEE '
    'agrees that it is the prerogative of the EMPLOYER to evaluate his/her '
    'performance and decide whether he/she is qualified to be a regular '
    'employee. If the EMPLOYEE fails to meet the standards for '
    'regularization set forth by the EMPLOYER, the EMPLOYER may terminate '
    'this Contract in accordance with the procedure prescribed by law or '
    'any applicable rules and regulations.';

// §5 COMPENSATION — three paragraphs
const String _s5CompensationP1 =
    'The EMPLOYEE will be paid a basic salary of PHP {monthlySalary} per '
    '{salaryPeriod}, Philippine Currency payable in two installments, once on the '
    "15th and at the end of the month. The EMPLOYEE's salary will be paid "
    'either through ATM, in cash, by a bank check, or by a bank or postal '
    "transfer, from which shall be deducted, where applicable, the "
    "EMPLOYEE's social security contribution, withholding taxes and other "
    'government mandated deductions. Such rate does not include payment for '
    'OT during regular, rest day or holidays, which shall be paid '
    'separately as incurred.';
const String _s5CompensationP2 =
    'It is hereby further agreed, and the EMPLOYEE hereby acknowledges, '
    'that during the period of probationary employment, he/she shall not be '
    'entitled to the compensation and benefits extended by the EMPLOYER to '
    'its regular employees EXCEPT those herein aforestated and such '
    'benefits granted by law.';
const String _s5CompensationP3 =
    'Notwithstanding incidents when the EMPLOYER granted benefits, bonuses '
    'or allowance other than those defined in this contract, such incidents '
    'are not to be considered as an established practice or precedent and '
    'shall not form part of the benefits, bonuses and allowances due and '
    'demandable under this Contract of Employment.';

// §6 WORK HOURS
const String _s6WorkHours =
    'The EMPLOYEE shall work for a period of {workHoursPerDay} hours per day '
    'from {workDaysPerWeek}. In case of unusual volume of work, the '
    'EMPLOYER may require the EMPLOYEE to work on Sundays. Any work rendered '
    'in excess of {workHoursPerDay} hours per day shall be subject to '
    'payment of applicable overtime rate. Management prescribes the work '
    'schedule, and it reserves the right to change the schedule as it may '
    'deem necessary to meet operational requirements.';

// §7 ASSIGNMENT OF TASKS
const String _s7Assignment =
    "On signing this Contract, the EMPLOYEE recognizes EMPLOYER's right and "
    'prerogative, to assign and re-assign him/her to perform such other '
    "tasks within EMPLOYER's organization, in any branch or unit, as may be "
    'deemed necessary or in the interest of the service.';

// §8 MEDICAL/DRUG TESTS
const String _s8Medical =
    'By signing this contract, the EMPLOYEE consents and agrees to, upon '
    'request from the EMPLOYER, undergo at a government accredited institute '
    'to be nominated by the EMPLOYER, a medical/drug tests at the expense '
    'of the EMPLOYEE. This is to be carried out for the purposes of '
    "determining the EMPLOYEE's physical and mental fitness to perform the "
    'functions of his job.';

// §9 COMPANY RULES AND REGULATIONS — two paragraphs
const String _s9RulesP1 =
    'All existing as well as future rules and regulations issued by the '
    'EMPLOYER are hereby deemed incorporated with this Contract. The '
    'EMPLOYEE recognizes that by signing this Contract, he/she shall be '
    'bound by all such rules and regulations, which the EMPLOYER may issue '
    'from time to time.';
const String _s9RulesP2 =
    'On signing this Contract, the EMPLOYEE acknowledges his/her duty and '
    "responsibility to be aware of the EMPLOYER's rules and regulations "
    'regarding his/her employment and to fully comply with these in good '
    'faith.';

// §10 DEDUCTIONS FOR COMPANY-INCURRED COSTS
const String _s10DeductionsIntro =
    'The EMPLOYEE agrees and acknowledges that the EMPLOYER has the right to '
    "deduct from the EMPLOYEE's salary any amounts corresponding to costs "
    'or expenses incurred by the EMPLOYER as a direct result of the '
    "EMPLOYEE's actions, negligence, or non-compliance with company "
    'policies, provided that such deductions are reasonable, duly '
    'documented, and in accordance with applicable laws and regulations. '
    'This includes, but is not limited to:';
const List<String> _s10DeductionsBullets = <String>[
  "Damage to or loss of company property due to the EMPLOYEE's negligence.",
  'Unauthorized expenses charged to the company.',
  'Costs arising from failure to return company-issued items such as IDs, '
      'uniforms, tools, or equipment upon termination of employment.',
];
const String _s10DeductionsClose =
    'The EMPLOYER will notify the EMPLOYEE in writing before implementing '
    'any deductions, providing a detailed account of the costs and the '
    'reason for the deduction.';

// §11 DISCIPLINARY MEASURES
const String _s11Disciplinary =
    "On signing this Contract, the EMPLOYEE hereby recognizes the EMPLOYER's "
    'right to impose disciplinary measures or sanctions, which may include, '
    'but are not limited to, termination of employment, suspensions, fines, '
    'salary deductions, withdrawal of benefits, loss of privileges, for any '
    'and all infraction, act or omission, irrespective of whether such '
    'infraction, act or omission constitutes a ground for termination.';

// §12 NON-COMPETE AGREEMENT
const String _s12NonCompeteIntro =
    'The EMPLOYEE agrees that for a period of {nonCompeteMonths} months '
    'following the termination of their employment, they will not:';
const List<String> _s12NonCompeteBullets = <String>[
  'Directly or indirectly engage in any business or activity that competes '
      'with the business of the EMPLOYER within the Philippines.',
  "Solicit or attempt to solicit any of the EMPLOYER's clients, customers, "
      'or employees for purposes that would result in competition with the '
      'EMPLOYER.',
];
const String _s12NonCompeteP2 =
    'The EMPLOYEE acknowledges that this non-compete clause is reasonable in '
    'scope and duration and is necessary to protect the legitimate business '
    'interests of the EMPLOYER, including but not limited to the protection '
    'of trade secrets, confidential information, and customer '
    'relationships.';
const String _s12NonCompeteP3 =
    'If the EMPLOYEE breaches this non-compete clause, the EMPLOYER reserves '
    'the right to pursue legal remedies, including but not limited to '
    'injunctive relief and damages.';

// §13 TERMINATION OF EMPLOYMENT
const String _s13TerminationIntro =
    'Aside from the just and authorized causes for the termination of '
    'employment enumerated in Arts. 282 to 284 of the Labor Code, the '
    'following acts and/or omissions of the EMPLOYEE shall, without '
    'limitation, similarly constitute just and authorized grounds for the '
    'termination of employment by the EMPLOYER and/or grounds for the '
    'EMPLOYER to impose disciplinary measures on the EMPLOYEE:';
const List<String> _s13TerminationGrounds = <String>[
  "Intentional or unintentional violation of the EMPLOYER's policies, "
      'rules, and regulations as embodied in the Code of Discipline;',
  'Commission of an act which effects a loss of confidence on the part of '
      "the EMPLOYER with regard to the EMPLOYEE's ability to satisfactorily "
      'perform the duties and requirements of his/her employment',
  'In the event of the EMPLOYEE being incapacitated by ill health, '
      'accident or physical or mental incapacity from fully performing '
      'his/her duties with the EMPLOYER for an aggregate period of ninety '
      '(90) days in any one calendar year, such incapacity being duly '
      "certified as such by the EMPLOYER's appointed doctor;",
  'Failure of the EMPLOYEE to pass two (2) consecutive evaluations of '
      'his/her work performance; and',
  "Failure of the EMPLOYEE to successfully pass the EMPLOYER's standards "
      'for regularization specified under Annex "B" hereof and under other '
      'rules, regulations, and policies of the EMPLOYER; and',
  'Other similar acts, omissions, and/or events.',
];
const String _s13TerminationClose =
    'The Contract of employment may be terminated by the EMPLOYER for any '
    'of the foregoing grounds and by observing the due process requirements '
    'of the law. In the event that the EMPLOYEE wishes to terminate this '
    'Contract of Employment for any reason, he/she must give thirty (30) '
    'days written notice to EMPLOYER prior to the effective date of '
    'termination. Upon termination of this employment, the EMPLOYEE shall '
    "promptly account for, return, and deliver to the EMPLOYER at the "
    "EMPLOYER's main office, his/her I.D. Cards, Code of Discipline manual, "
    "Employee Handbook and all the EMPLOYER's property, which may have been "
    'assigned or entrusted to his/her care or custody.';

// §14 FINAL PAY
const String _s14FinalPay =
    "It is also hereby agreed that in case of termination of the EMPLOYEE's "
    'employment for whatever causes, the EMPLOYER shall have the right, and '
    'the EMPLOYEE hereby authorize the EMPLOYER, to withhold the '
    "EMPLOYEE's last salary or any other benefits accrued in the EMPLOYEE's "
    'favor, pending liquidation of whatever obligations which the EMPLOYEE '
    'may have with the EMPLOYER without prejudice to the right of the '
    'EMPLOYER to demand, collect, and recover from the EMPLOYEE any balance '
    'remaining thereafter.';

// §15 CONFIDENTIALITY
const String _s15Confidentiality =
    "It is the EMPLOYEE's responsibility to ensure that no information "
    'gained by virtue of employment with the EMPLOYER or by virtue of '
    "his/her assignment to the EMPLOYER's clients is disclosed to outsiders "
    'unless the disclosure is for necessary business purposes and pursuant '
    'to properly approved and written agreements. Confidential information '
    'is any information belonging to EMPLOYER or its clients that could be '
    'used by people outside the company to the detriment of the EMPLOYER or '
    'its clients. The EMPLOYEE should take appropriate steps in handling '
    'all EMPLOYER business information in order to minimize the possibility '
    'of unauthorized disclosure.';

// §16 SEPARABILITY CLAUSE
const String _s16Separability =
    'If any provisions of this document shall be construed to be illegal or '
    'invalid, they shall not affect the legality, validity, and '
    'enforceability of the other provisions of this document; the illegal '
    'or invalid provision shall be deleted from this document and no longer '
    'incorporated herein but all other provisions of this document shall '
    'continue.';

// §17 ENTIRE AGREEMENT
const String _s17EntireAgreement =
    'This Contract represents the entire agreement between the EMPLOYER and '
    'the EMPLOYEE and supersedes all previous oral and written '
    'communications, representations or agreements between the parties. Any '
    'amendments or modifications to this contract must be made in writing '
    'and signed by both parties.';

const String _witnessClause =
    'IN WITNESS WHEREOF, the parties have executed this document as of the '
    'date and place first mentioned.';

const String _annexAHeader =
    'Annex A: Duties, Responsibilities, and Work Hours';

// Section titles in order (§1..§17), for EC9 to pair with SectionHeadingBlock.
const List<String> _sectionTitles = <String>[
  'PROBATIONARY EMPLOYMENT',
  'JOB TITLE AND DESCRIPTION',
  'PERIOD OF PROBATIONARY EMPLOYMENT',
  'PROBATIONARY EVALUATION',
  'COMPENSATION',
  'WORK HOURS',
  'ASSIGNMENT OF TASKS',
  'MEDICAL/DRUG TESTS',
  'COMPANY RULES AND REGULATIONS',
  'DEDUCTIONS FOR COMPANY-INCURRED COSTS',
  'DISCIPLINARY MEASURES',
  'NON-COMPETE AGREEMENT',
  'TERMINATION OF EMPLOYMENT',
  'FINAL PAY',
  'CONFIDENTIALITY',
  'SEPARABILITY CLAUSE',
  'ENTIRE AGREEMENT',
];

class EmploymentContractTemplate
    extends DocumentTemplate<EmploymentContractInputs> {
  const EmploymentContractTemplate();

  @override
  String get id => 'employment_contract';
  @override
  String get name => 'Employment Contract';
  @override
  String get description =>
      'Probationary employment agreement with Annex A duties.';
  @override
  IconData get icon => Icons.assignment_outlined;
  @override
  int get version => 1;

  @override
  EmploymentContractInputs emptyInputs() {
    final today = DateTime.now();
    return EmploymentContractInputs(
      employeeId: '',
      employeeFullName: '',
      employeeAddress: '',
      companyId: '',
      companyName: '',
      companyAddress: '',
      representativeName: '',
      representativeRole: 'People Manager',
      place: '',
      dateEntered: today,
      industry: 'Retail Industry',
      position: '',
      monthlySalary: '',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Saturday',
      nonCompeteMonths: 24,
      employerSignatoryName: '',
      employerSignatoryRole: '',
      responsibilities: const [],
      kpis: const [],
    );
  }

  @override
  Future<EmploymentContractInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();

    // Role scorecard drives Annex A (mission, duties, KPIs) plus salary
    // and work-schedule defaults. Best-effort: a missing/unreadable
    // scorecard (e.g. no Supabase client in tests) falls back to the
    // template defaults below.
    RoleScorecard? scorecard;
    final scorecardId = emp.roleScorecardId;
    if (scorecardId != null && scorecardId.isNotEmpty) {
      try {
        scorecard = await ctx.ref
            .read(roleScorecardByIdProvider(scorecardId).future);
      } catch (_) {
        scorecard = null;
      }
    }

    // Latest HIRE event seeds the probation start; fall back to the
    // employee's hireDate. Wrapped so dev/test envs without Supabase
    // degrade gracefully (mirrors the Non-Reg autofill pattern).
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

    final probStart = eventDate(hireRow) ?? emp.hireDate;
    final probEnd = defaultProbationaryEnd(probStart);

    final repName = co?.hrManagerName ?? '';
    final repRole = (co?.legalSignatoryRole?.isNotEmpty == true)
        ? co!.legalSignatoryRole!
        : 'People Manager';

    final place = <String?>[co?.city, co?.province, 'Philippines']
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .join(', ');

    final salary = scorecard?.baseSalary;
    final monthlySalary = salary == null
        ? ''
        : NumberFormat('#,##0', 'en_US').format(salary.toDouble());

    String periodFromWageType(String? wt) {
      switch ((wt ?? '').toUpperCase()) {
        case 'DAILY':
          return 'day';
        case 'HOURLY':
          return 'hour';
        default:
          return 'month';
      }
    }

    return EmploymentContractInputs(
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
      companyAddress: _composeAddress(
        co?.addressLine1,
        co?.addressLine2,
        co?.city,
        co?.province,
        co?.zipCode,
      ),
      representativeName: repName,
      representativeRole: repRole,
      place: place,
      dateEntered: today,
      industry: 'Retail Industry',
      position: emp.jobTitle ?? scorecard?.jobTitle ?? '',
      probationStart: probStart,
      probationEnd: probEnd,
      monthlySalary: monthlySalary,
      salaryPeriod: periodFromWageType(scorecard?.wageType),
      workHoursPerDay: scorecard?.workHoursPerDay ?? 8,
      workDaysPerWeek: scorecard?.workDaysPerWeek ?? 'Monday to Saturday',
      nonCompeteMonths: 24,
      employerSignatoryName: repName,
      employerSignatoryRole: repRole,
      missionStatement: scorecard?.missionStatement ?? '',
      responsibilities: scorecard == null
          ? const []
          : scorecard.responsibilities
              .map((r) =>
                  ContractResponsibility(area: r.area, tasks: r.tasks))
              .toList(),
      kpis: scorecard == null
          ? const []
          : scorecard.kpis
              .map((k) =>
                  ContractKpi(metric: k.metric, frequency: k.frequency))
              .toList(),
      logoBytes: null,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(EmploymentContractInputs inputs) =>
      validateEmploymentContract(inputs);

  @override
  List<Block> build(EmploymentContractInputs i) {
    final fmt = DateFormat('MMMM d, yyyy');
    String dateOrDash(DateTime? d) => d == null ? '—' : fmt.format(d);

    final blocks = <Block>[];

    // 2-3. Title.
    blocks.add(const TitleBlock('EMPLOYMENT CONTRACT', centered: true));
    blocks.add(const SpacerBlock(16));

    // 4-5. Preamble intro (date + place).
    blocks.add(ParagraphBlock(interpolate(
      _preambleIntro,
      {'dateEntered': fmt.format(i.dateEntered), 'place': i.place},
      lenient: true,
    )));
    blocks.add(const SpacerBlock(12));

    // 6. EMPLOYER party — bold company name, italic address, normal-weight
    // representative role/name, with the fixed connector fragments between.
    blocks.add(PartyBlock(spans: [
      EmphasisSpan(i.companyName, bold: true),
      const EmphasisSpan(_employerPartyPrefix),
      EmphasisSpan(i.companyAddress, italic: true),
      const EmphasisSpan(_employerPartyMid),
      EmphasisSpan('${i.representativeRole}, ${i.representativeName}'),
      const EmphasisSpan(_employerPartySuffix),
    ]));
    blocks.add(const SpacerBlock(12));

    // 8-9. Centered "- and -" connector.
    blocks.add(const TitleBlock('- and -', centered: true));
    blocks.add(const SpacerBlock(12));

    // 10-11. EMPLOYEE party — bold name, italic address.
    blocks.add(PartyBlock(spans: [
      EmphasisSpan(i.employeeFullName, bold: true),
      const EmphasisSpan(_employeePartyPrefix),
      EmphasisSpan(i.employeeAddress, italic: true),
      const EmphasisSpan(_employeePartySuffix),
    ]));
    blocks.add(const SpacerBlock(24));

    // 12-13. WITNESSETH recitals.
    blocks.add(const TitleBlock('WITNESSETH THAT:', centered: true));
    blocks.add(const SpacerBlock(8));
    blocks.add(NumberedListBlock([
      interpolate(_recital1, {'industry': i.industry}, lenient: true),
      _recital2,
      interpolate(_recital3, {'position': i.position}, lenient: true),
    ]));
    blocks.add(const SpacerBlock(8));
    blocks.add(const ParagraphBlock(_nowTherefore));

    // 17. The 17 numbered clauses.
    void section(int n, List<Block> body) {
      blocks.add(const SpacerBlock(12));
      blocks.add(SectionHeadingBlock(number: n, title: _sectionTitles[n - 1]));
      blocks.addAll(body);
    }

    section(1, const [ParagraphBlock(_s1ProbationaryEmployment)]);
    section(2, [
      ParagraphBlock(
          interpolate(_s2JobTitle, {'position': i.position}, lenient: true)),
    ]);
    section(3, [
      ParagraphBlock(interpolate(
        _s3PeriodP1,
        {
          'probationStart': dateOrDash(i.probationStart),
          'probationEnd': dateOrDash(i.probationEnd),
        },
        lenient: true,
      )),
      const SpacerBlock(8),
      const ParagraphBlock(_s3PeriodP2),
    ]);
    section(4, const [ParagraphBlock(_s4Evaluation)]);
    section(5, [
      ParagraphBlock(interpolate(
          _s5CompensationP1,
          {'monthlySalary': i.monthlySalary, 'salaryPeriod': i.salaryPeriod},
          lenient: true)),
      const SpacerBlock(6),
      const ParagraphBlock(_s5CompensationP2),
      const SpacerBlock(6),
      const ParagraphBlock(_s5CompensationP3),
    ]);
    section(6, [
      ParagraphBlock(interpolate(
        _s6WorkHours,
        {
          'workHoursPerDay': '${i.workHoursPerDay}',
          'workDaysPerWeek': i.workDaysPerWeek,
        },
        lenient: true,
      )),
    ]);
    section(7, const [ParagraphBlock(_s7Assignment)]);
    section(8, const [ParagraphBlock(_s8Medical)]);
    section(9, const [
      ParagraphBlock(_s9RulesP1),
      SpacerBlock(6),
      ParagraphBlock(_s9RulesP2),
    ]);
    section(10, const [
      ParagraphBlock(_s10DeductionsIntro),
      BulletListBlock(_s10DeductionsBullets),
      ParagraphBlock(_s10DeductionsClose),
    ]);
    section(11, const [ParagraphBlock(_s11Disciplinary)]);
    section(12, [
      ParagraphBlock(interpolate(
          _s12NonCompeteIntro, {'nonCompeteMonths': '${i.nonCompeteMonths}'},
          lenient: true)),
      const BulletListBlock(_s12NonCompeteBullets),
      const ParagraphBlock(_s12NonCompeteP2),
      const ParagraphBlock(_s12NonCompeteP3),
    ]);
    section(13, const [
      ParagraphBlock(_s13TerminationIntro),
      LetteredListBlock(_s13TerminationGrounds),
      ParagraphBlock(_s13TerminationClose),
    ]);
    section(14, const [ParagraphBlock(_s14FinalPay)]);
    section(15, const [ParagraphBlock(_s15Confidentiality)]);
    section(16, const [ParagraphBlock(_s16Separability)]);
    section(17, const [ParagraphBlock(_s17EntireAgreement)]);

    // 18-19. Witness clause.
    blocks.add(const SpacerBlock(24));
    blocks.add(const ParagraphBlock(_witnessClause));

    // 20-23. Employer signature line + signatories.
    blocks.add(const SpacerBlock(24));
    blocks.add(ParagraphBlock(i.companyName));
    blocks.add(const ParagraphBlock('By:'));
    blocks.add(const SpacerBlock(40));
    blocks.add(MultiSignatureBlock([
      SignatoryParty(
        name: i.employerSignatoryName,
        role: i.employerSignatoryRole,
        date: null,
      ),
      SignatoryParty(
        name: i.employeeFullName,
        role: i.position,
        date: null,
      ),
    ]));

    // 24-27. Witnesses.
    blocks.add(const SpacerBlock(24));
    blocks.add(const ParagraphBlock('SIGNED IN THE PRESENCE OF:'));
    blocks.add(const SpacerBlock(40));
    blocks.add(MultiSignatureBlock([
      SignatoryParty(
        name: i.witness1Name,
        role: i.witness1Role,
        date: null,
      ),
      SignatoryParty(
        name: i.witness2Name,
        role: i.witness2Role,
        date: null,
      ),
    ]));

    // 28. Page break before Annex A.
    blocks.add(const PageBreakBlock());

    // 29-31. Annex A header + position title.
    blocks.add(const TitleBlock(_annexAHeader));
    blocks.add(const SpacerBlock(12));
    blocks.add(EmphasisParagraphBlock(spans: [
      const EmphasisSpan('Position Title: ', bold: true),
      EmphasisSpan(i.position),
    ]));

    // 32. Mission statement (optional).
    if (i.missionStatement.isNotEmpty) {
      blocks.add(const SpacerBlock(8));
      blocks.add(ParagraphBlock(i.missionStatement));
    }

    // 33-34. Duties and Responsibilities. Each area renders as a bold
    // label (EmphasisParagraphBlock) followed by a bullet list of tasks —
    // cleaner than LabelledBulletListBlock's "label: body" colon format.
    blocks.add(const SpacerBlock(12));
    blocks.add(const HeadingBlock('Duties and Responsibilities'));
    for (final r in i.responsibilities) {
      blocks.add(EmphasisParagraphBlock(spans: [
        EmphasisSpan(r.area, bold: true),
      ]));
      blocks.add(BulletListBlock(r.tasks));
      blocks.add(const SpacerBlock(6));
    }

    // 35. Key Performance Indicators (optional).
    if (i.kpis.isNotEmpty) {
      blocks.add(const SpacerBlock(12));
      blocks.add(const HeadingBlock('Key Performance Indicators'));
      blocks.add(BulletListBlock(
        [for (final k in i.kpis) '${k.metric} — ${k.frequency}'],
      ));
    }

    // 36. Work Hours.
    blocks.add(const SpacerBlock(12));
    blocks.add(const HeadingBlock('Work Hours'));
    blocks.add(ParagraphBlock(
        '${i.workHoursPerDay} hours per day, ${i.workDaysPerWeek}.'));

    return blocks;
  }
}

/// Joins the individual nullable address parts into a single
/// comma-separated line, skipping any that are null or empty. Unlike
/// `_addressOf` in other templates (which renders a `·`-separated block),
/// the contract recital wants one inline address string.
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
