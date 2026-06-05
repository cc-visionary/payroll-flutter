import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Icons, IconData;

import '../blocks/block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'final_pay_inputs.dart';
import 'final_pay_validate.dart';

class FinalPayTemplate extends DocumentTemplate<FinalPayInputs> {
  const FinalPayTemplate();

  @override
  String get id => 'final_pay';

  @override
  String get name => 'Final Pay Computation';

  @override
  String get description =>
      'Itemized final-pay disclosure for a separated employee. Auto-computes '
      'from payroll engine; HR can override any line. Required by DOLE Labor '
      'Advisory 06-20.';

  @override
  IconData get icon => Icons.payments_outlined;

  @override
  int get version => 1;

  @override
  bool get supportsBulk => false;

  @override
  FinalPayInputs emptyInputs() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return FinalPayInputs(
      employeeId: '',
      employeeFullName: '',
      companyId: '',
      companyName: '',
      computedAsOf: today,
      releaseDate: today.add(const Duration(days: 30)),
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) {
    final e = ctx.employee;
    if (e == null) return const [];
    final inactive = e.employmentStatus != 'ACTIVE' || e.separationDate != null;
    if (!inactive) {
      return const [Gate('Final Pay is only valid for separated employees.')];
    }
    return const [];
  }

  @override
  Future<FinalPayInputs> autofill(AutofillContext ctx) async {
    final e = ctx.employee;
    final c = ctx.company;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    FinalPayBreakdown? bd;
    if (e != null) {
      try {
        bd = await ctx.ref.read(finalPayBreakdownProvider(e.id).future);
      } catch (_) {
        bd = null;
      }
    }

    return FinalPayInputs(
      employeeId: e?.id ?? '',
      employeeFullName: e?.fullName ?? '',
      employeePosition: e?.jobTitle ?? '',
      employeeHireDate: e?.hireDate,
      employeeSeparationDate: e?.separationDate,
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
      lastNetPay: bd?.lastNetPay ?? Decimal.zero,
      thirteenthMonth: bd?.thirteenthMonth ?? Decimal.zero,
      unusedLeaveConversion: bd?.unusedLeaveConversion ?? Decimal.zero,
      outstandingCashAdvance: bd?.outstandingCashAdvance ?? Decimal.zero,
      computedAsOf: today,
      releaseDate: today.add(const Duration(days: 30)),
    );
  }

  @override
  List<ValidationError> validate(FinalPayInputs inputs) =>
      validateFinalPay(inputs);

  @override
  List<Block> build(FinalPayInputs inputs) {
    // Implemented in Task 4.
    return const [];
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
