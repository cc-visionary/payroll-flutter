import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/centered_signature_block.dart';
import '../blocks/emphasis_paragraph_block.dart';
import '../blocks/letterhead_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import '../blocks/title_block.dart';
import '../brand_logo.dart';
import 'document_template.dart';
import 'quitclaim_inputs.dart';
import 'quitclaim_validate.dart';

const _qcPara2 =
    'I hereby declare that I have no further claims whatsoever against my '
    'employer, its President, members of the Board, officers or any of its '
    'staff and that I hereby release and forever discharge all of them from '
    'any and all claims, demands, cause of action of whatever nature arising '
    'out of my employment with the latter;';
const _qcPara4 =
    'As such, I finally make manifest that I have no further claim(s) or '
    'cause of action against my employer nor against any person(s) connected '
    'with the administration and operation of the latter and forever release '
    'the latter from any and all liability.';
const _qcSubscribed =
    'SIGNED IN THE PRESENCE OF: _______________________   SUBSCRIBED AND '
    'SWORN to before me, _____________ at Manila City.';

class QuitclaimTemplate extends DocumentTemplate<QuitclaimInputs> {
  const QuitclaimTemplate();
  @override
  String get id => 'quitclaim';
  @override
  String get name => 'Quitclaim';
  @override
  String get description =>
      'Notarized release and quitclaim signed at separation.';
  @override
  IconData get icon => Icons.assignment_turned_in_outlined;
  @override
  int get version => 1;

  @override
  QuitclaimInputs emptyInputs() => QuitclaimInputs(
    employeeId: '',
    employeeFullName: '',
    companyId: '',
    companyName: '',
    finalPayAmount: Decimal.zero,
    dateSigned: DateTime.now(),
  );

  @override
  Future<QuitclaimInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    final co = ctx.company;
    if (emp == null) return emptyInputs();
    final logo = await loadCompanyLogoBytes(co);
    return QuitclaimInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeAddress: _composeAddress(
        emp.addressLine1,
        emp.addressLine2,
        emp.city,
        emp.province,
        emp.zipCode,
      ),
      civilStatus: 'single',
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      finalPayAmount: Decimal.zero,
      dateTerminated: emp.separationDate,
      dateSigned: DateTime.now(),
      placeSigned: co == null
          ? ''
          : _composeAddress(
              co.addressLine1,
              co.addressLine2,
              co.city,
              co.province,
              co.zipCode,
            ),
      logoBytes: logo,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];
  @override
  List<ValidationError> validate(QuitclaimInputs inputs) =>
      validateQuitclaim(inputs);

  @override
  List<Block> build(QuitclaimInputs i) {
    final fmt = DateFormat('MMMM d, yyyy');
    final amount = _formatPeso(i.finalPayAmount.toString());
    return [
      if (i.logoBytes != null || i.companyName.isNotEmpty)
        LetterheadBlock(logoBytes: i.logoBytes, companyName: i.companyName),
      const SpacerBlock(16),
      const TitleBlock('QUITCLAIM AND RELEASE', centered: true),
      const SpacerBlock(16),
      EmphasisParagraphBlock(
        spans: [
          const EmphasisSpan('I, '),
          EmphasisSpan(i.employeeFullName, bold: true),
          EmphasisSpan(', of legal age, ${i.civilStatus} and residing at '),
          EmphasisSpan(i.employeeAddress, italic: true),
          const EmphasisSpan(', for and in consideration of the amount of '),
          EmphasisSpan('₱$amount', bold: true),
          const EmphasisSpan(' (Sum of Last Pay) paid to me by '),
          EmphasisSpan(i.companyName, bold: true),
          const EmphasisSpan(
            ' and receipt of which is hereby acknowledged to my full and '
            'complete satisfaction, do hereby release and forever discharge '
            'said Company, its officers and stockholders from any and all '
            'claims arising out of and in connection with my dismissal.',
          ),
        ],
      ),
      const SpacerBlock(8),
      const ParagraphBlock(_qcPara2),
      const SpacerBlock(8),
      EmphasisParagraphBlock(
        spans: [
          const EmphasisSpan(
            'I acknowledge that my separation from the Company is due to my '
            'failure to qualify as a regular employee in accordance with the '
            'reasonable standards made known to me at the time of my '
            'engagement. I accept the results of the evaluation and the '
            'termination of my probationary employment effective ',
          ),
          EmphasisSpan(
            i.dateTerminated == null ? '—' : fmt.format(i.dateTerminated!),
            bold: true,
          ),
          const EmphasisSpan('.'),
        ],
      ),
      const SpacerBlock(8),
      const ParagraphBlock(_qcPara4),
      const SpacerBlock(8),
      ParagraphBlock(
        'IN WITNESS WHEREOF, I have hereunto signed these presents this '
        '${fmt.format(i.dateSigned)} at ${i.placeSigned}.',
      ),
      const SpacerBlock(40),
      const CenteredSignatureBlock('Name and signature of Employee'),
      const SpacerBlock(16),
      const ParagraphBlock(_qcSubscribed),
      const SpacerBlock(32),
      const ParagraphBlock('Doc. No. _____;'),
      const ParagraphBlock('Page No._____;'),
      const ParagraphBlock('Book No.______;'),
      const ParagraphBlock('Series of 20___.'),
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

String _formatPeso(String amount) {
  final parts = amount.split('.');
  final intPart = parts[0];
  final fracPart = parts.length > 1 ? parts[1] : '00';
  final padded = '${fracPart}00'.substring(0, 2);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '$buf.$padded';
}
