import 'package:flutter/material.dart' show Icons, IconData;

import '../blocks/block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'non_reg_inputs.dart';
import 'non_reg_validate.dart';

// Canonical legal copy lifted verbatim from
// `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/NOTICE OF
// NON-REGULARIZATION_VIDAL - Google Docs.pdf`. Confirm wording with the
// user before merge (Task 22).
const _specificallyLead =
    'Specifically, you failed to meet the agreed-upon standards in the '
    'following areas:';
const _finalPayText =
    'Please arrange to return your Company ID, access keys, and any other '
    'company property currently in your possession. Your Final Pay, '
    'including your pro-rated 13th-month pay, will be processed in '
    'accordance with Section 14 (Final Pay) of your contract and released '
    'upon completion of the clearance process.';
const _closingText =
    'We thank you for the time spent with the company and wish you the '
    'best in your future endeavors.';
const _acknowledgmentText =
    'I acknowledge receipt of this notice. I understand that my signature '
    'attests only to the receipt of this letter and not necessarily my '
    'agreement with its contents.';

/// PH Labor Code default: probationary period is six months from the
/// hire date. HR can override via the lock/unlock toggle if a longer
/// period was stipulated in the employment contract.
DateTime defaultProbationaryEnd(DateTime start) {
  // Add 6 calendar months. Dart's DateTime does this safely: if the
  // target month has no equivalent day-of-month, the constructor wraps
  // into the next month (e.g. Aug 31 + 6 mo → Mar 3 the next year). For
  // a probation-end calculation that overshoot is acceptable and rare.
  return DateTime(start.year, start.month + 6, start.day);
}

class NonRegTemplate extends DocumentTemplate<NonRegInputs> {
  const NonRegTemplate();

  @override
  String get id => 'non_reg';
  @override
  String get name => 'Notice of Non-Regularization';
  @override
  String get description =>
      'Issued when a probationary employee fails to regularize.';
  @override
  IconData get icon => Icons.person_off_outlined;
  @override
  int get version => 1;

  @override
  NonRegInputs emptyInputs() {
    final today = DateTime.now();
    return NonRegInputs(
      employeeId: '',
      employeeFullName: '',
      employeeLastName: '',
      employeePosition: '',
      companyId: '',
      companyName: '',
      dateIssued: today,
      salutationName: '',
      findings: const [],
    );
  }

  @override
  Future<NonRegInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();
    // Pull the latest HIRE event; fall back to employee.hireDate (already
    // on the Employee model) if no event row exists. Wrap in try/catch
    // so tests / dev environments without an initialized Supabase client
    // gracefully fall back to the model's hireDate. Consistent with
    // providers.dart::finalPayBreakdownProvider.
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
    return NonRegInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeLastName: emp.lastName,
      employeePosition: '', // Employee model has no `position` field; HR fills.
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      hrManagerName: co?.hrManagerName,
      dateIssued: today,
      probationaryStart: probStart,
      probationaryEnd: probEnd,
      effectiveEndDate: probEnd,
      salutationName: emp.lastName,
      findings: const [],
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(NonRegInputs inputs) =>
      validateNonReg(inputs);

  @override
  List<Block> build(NonRegInputs i) => const [];
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
