import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../blocks/block.dart';
import '../blocks/company_header_block.dart';
import '../blocks/key_value_block.dart';
import '../blocks/multi_signature_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/spacer_block.dart';
import '../blocks/title_block.dart';
import '../../../core/pdf/interpolate.dart';
import 'document_template.dart';
import 'quitclaim_inputs.dart';
import 'quitclaim_validate.dart';

// PLACEHOLDER — engineer MUST replace with canonical wording from
// [06] LUXIUM/[02] HR/[02] Employee Records/JAM/ Quitclaim source PDF
// before Phase 8 Task 40 ships. Confirm with the user.
const String _quitclaimBodyText =
    'I, {employeeFullName}, of legal age, hereby acknowledge receipt from '
    '{companyName} of the sum of ₱ {finalPayAmount} representing my final '
    'pay. In consideration of the foregoing, I hereby release, waive, and '
    'forever discharge {companyName}, its officers, directors, '
    'shareholders, agents, and employees from any and all claims, demands, '
    'damages, actions, causes of action, or suits of any kind whatsoever, '
    'whether in law or equity, which I now have or may hereafter have '
    'arising out of my employment with {companyName} or its termination.';

class QuitclaimTemplate extends DocumentTemplate<QuitclaimInputs> {
  const QuitclaimTemplate();

  @override
  String get id => 'quitclaim';
  @override
  String get name => 'Quitclaim';
  @override
  String get description =>
      'Release, waiver, and quitclaim issued at separation.';
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
        dateSigned: DateTime.now(),
        finalPayAmount: Decimal.zero,
      );

  @override
  Future<QuitclaimInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    final co = ctx.company;
    if (emp == null) return emptyInputs();
    // Date Terminated comes straight off the Employee row, which is the
    // source of truth (separationDate is set when a separation is
    // confirmed). We do NOT query employment_events here — the event_type
    // enum has no 'SEPARATION' member (it uses SEPARATION_CONFIRMED /
    // SEPARATION_INITIATED), and the employee row already carries the
    // authoritative date.
    return QuitclaimInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      companySignatoryName: co?.legalSignatoryName,
      companySignatoryRole: co?.legalSignatoryRole,
      dateTerminated: emp.separationDate,
      dateSigned: DateTime.now(),
      finalPayAmount: Decimal.zero,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(QuitclaimInputs inputs) =>
      validateQuitclaim(inputs);

  @override
  List<Block> build(QuitclaimInputs i) {
    final dateFmt = DateFormat('MMMM d, yyyy');
    final amountStr = _formatPeso(i.finalPayAmount.toString());
    return [
      CompanyHeaderBlock(name: i.companyName, address: i.companyAddress),
      const SpacerBlock(24),
      const TitleBlock('RELEASE, WAIVER, AND QUITCLAIM'),
      const SpacerBlock(16),
      KeyValueBlock([
        KeyValueRow('Full Name', i.employeeFullName),
        KeyValueRow('Final Pay', '₱ $amountStr'),
        KeyValueRow('Company', i.companyName),
        KeyValueRow(
          'Date Terminated',
          i.dateTerminated == null ? '—' : dateFmt.format(i.dateTerminated!),
        ),
        KeyValueRow('Date Signed', dateFmt.format(i.dateSigned)),
      ]),
      const SpacerBlock(16),
      ParagraphBlock(
        interpolate(
          _quitclaimBodyText,
          {
            'employeeFullName': i.employeeFullName,
            'finalPayAmount': amountStr,
            'companyName': i.companyName,
          },
          lenient: true,
        ),
      ),
      const SpacerBlock(48),
      MultiSignatureBlock([
        SignatoryParty(
          name: i.employeeFullName,
          role: 'Employee',
          date: i.dateSigned,
        ),
        SignatoryParty(
          name: i.companySignatoryName,
          role: i.companySignatoryRole == null
              ? 'For ${i.companyName}'
              : '${i.companySignatoryRole} — ${i.companyName}',
          date: i.dateSigned,
        ),
      ]),
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

String _formatPeso(String amount) {
  // Format with grouping commas + 2 decimal places.
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
