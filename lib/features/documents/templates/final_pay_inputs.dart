import 'package:decimal/decimal.dart';

import 'document_template.dart';

class FinalPayInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final DateTime? employeeHireDate;
  final DateTime? employeeSeparationDate;

  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;

  // Computation lines (all auto-filled, all HR-overridable)
  final Decimal lastNetPay;
  final Decimal thirteenthMonth;
  final Decimal unusedLeaveConversion;
  final Decimal outstandingCashAdvance;
  final Decimal otherDeductions;
  final String otherDeductionsLabel;

  // Per-line lock flags (true = HR has overridden, ignore provider refresh)
  final bool lastNetPayLocked;
  final bool thirteenthMonthLocked;
  final bool unusedLeaveConversionLocked;
  final bool outstandingCashAdvanceLocked;

  final DateTime computedAsOf;
  final DateTime releaseDate;

  FinalPayInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeHireDate,
    this.employeeSeparationDate,
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    Decimal? lastNetPay,
    Decimal? thirteenthMonth,
    Decimal? unusedLeaveConversion,
    Decimal? outstandingCashAdvance,
    Decimal? otherDeductions,
    this.otherDeductionsLabel = '',
    this.lastNetPayLocked = false,
    this.thirteenthMonthLocked = false,
    this.unusedLeaveConversionLocked = false,
    this.outstandingCashAdvanceLocked = false,
    required this.computedAsOf,
    required this.releaseDate,
  }) : lastNetPay = lastNetPay ?? Decimal.zero,
       thirteenthMonth = thirteenthMonth ?? Decimal.zero,
       unusedLeaveConversion = unusedLeaveConversion ?? Decimal.zero,
       outstandingCashAdvance = outstandingCashAdvance ?? Decimal.zero,
       otherDeductions = otherDeductions ?? Decimal.zero;

  Decimal get total =>
      lastNetPay +
      thirteenthMonth +
      unusedLeaveConversion -
      outstandingCashAdvance -
      otherDeductions;

  FinalPayInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    Object? employeeHireDate = _undef,
    Object? employeeSeparationDate = _undef,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Decimal? lastNetPay,
    Decimal? thirteenthMonth,
    Decimal? unusedLeaveConversion,
    Decimal? outstandingCashAdvance,
    Decimal? otherDeductions,
    String? otherDeductionsLabel,
    bool? lastNetPayLocked,
    bool? thirteenthMonthLocked,
    bool? unusedLeaveConversionLocked,
    bool? outstandingCashAdvanceLocked,
    DateTime? computedAsOf,
    DateTime? releaseDate,
  }) => FinalPayInputs(
    employeeId: employeeId ?? this.employeeId,
    employeeFullName: employeeFullName ?? this.employeeFullName,
    employeePosition: employeePosition ?? this.employeePosition,
    employeeHireDate: identical(employeeHireDate, _undef)
        ? this.employeeHireDate
        : employeeHireDate as DateTime?,
    employeeSeparationDate: identical(employeeSeparationDate, _undef)
        ? this.employeeSeparationDate
        : employeeSeparationDate as DateTime?,
    companyId: companyId ?? this.companyId,
    companyName: companyName ?? this.companyName,
    companyAddress: companyAddress ?? this.companyAddress,
    hrManagerName: hrManagerName ?? this.hrManagerName,
    lastNetPay: lastNetPay ?? this.lastNetPay,
    thirteenthMonth: thirteenthMonth ?? this.thirteenthMonth,
    unusedLeaveConversion: unusedLeaveConversion ?? this.unusedLeaveConversion,
    outstandingCashAdvance:
        outstandingCashAdvance ?? this.outstandingCashAdvance,
    otherDeductions: otherDeductions ?? this.otherDeductions,
    otherDeductionsLabel: otherDeductionsLabel ?? this.otherDeductionsLabel,
    lastNetPayLocked: lastNetPayLocked ?? this.lastNetPayLocked,
    thirteenthMonthLocked: thirteenthMonthLocked ?? this.thirteenthMonthLocked,
    unusedLeaveConversionLocked:
        unusedLeaveConversionLocked ?? this.unusedLeaveConversionLocked,
    outstandingCashAdvanceLocked:
        outstandingCashAdvanceLocked ?? this.outstandingCashAdvanceLocked,
    computedAsOf: computedAsOf ?? this.computedAsOf,
    releaseDate: releaseDate ?? this.releaseDate,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'separation': employeeSeparationDate?.toIso8601String(),
    'total': total.toString(),
  };
}

const _undef = Object();
