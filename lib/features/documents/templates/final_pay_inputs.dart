import 'dart:typed_data';

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
  // Excluded from toJson — re-resolved from the entity at view time.
  final Uint8List? logoBytes;

  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;

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
    this.logoBytes,
    this.companySignaturePngB64,
  }) : lastNetPay = lastNetPay ?? Decimal.zero,
       thirteenthMonth = thirteenthMonth ?? Decimal.zero,
       unusedLeaveConversion = unusedLeaveConversion ?? Decimal.zero,
       outstandingCashAdvance = outstandingCashAdvance ?? Decimal.zero,
       otherDeductions = otherDeductions ?? Decimal.zero;

  factory FinalPayInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    Decimal? parseDecimal(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return Decimal.parse(s);
    }

    return FinalPayInputs(
      employeeId: json['employeeId'] as String,
      employeeFullName: json['employeeFullName'] as String,
      employeePosition: (json['employeePosition'] as String?) ?? '',
      employeeHireDate: parseDate(json['employeeHireDate']),
      employeeSeparationDate: parseDate(json['employeeSeparationDate']),
      companyId: json['companyId'] as String,
      companyName: json['companyName'] as String,
      companyAddress: (json['companyAddress'] as String?) ?? '',
      hrManagerName: (json['hrManagerName'] as String?) ?? '',
      lastNetPay: parseDecimal(json['lastNetPay']),
      thirteenthMonth: parseDecimal(json['thirteenthMonth']),
      unusedLeaveConversion: parseDecimal(json['unusedLeaveConversion']),
      outstandingCashAdvance: parseDecimal(json['outstandingCashAdvance']),
      otherDeductions: parseDecimal(json['otherDeductions']),
      otherDeductionsLabel: (json['otherDeductionsLabel'] as String?) ?? '',
      lastNetPayLocked: (json['lastNetPayLocked'] as bool?) ?? false,
      thirteenthMonthLocked: (json['thirteenthMonthLocked'] as bool?) ?? false,
      unusedLeaveConversionLocked:
          (json['unusedLeaveConversionLocked'] as bool?) ?? false,
      outstandingCashAdvanceLocked:
          (json['outstandingCashAdvanceLocked'] as bool?) ?? false,
      computedAsOf: parseDate(json['computedAsOf'])!,
      releaseDate: parseDate(json['releaseDate'])!,
      companySignaturePngB64: json['companySignaturePngB64'] as String?,
    );
  }

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
    Uint8List? logoBytes,
    String? companySignaturePngB64,
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
    logoBytes: logoBytes ?? this.logoBytes,
    companySignaturePngB64:
        companySignaturePngB64 ?? this.companySignaturePngB64,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'separation': employeeSeparationDate?.toIso8601String(),
    'total': total.toString(),
    'companySignaturePngB64': companySignaturePngB64 == null
        ? null
        : '<png b64, ${companySignaturePngB64!.length} chars>',
  };

  @override
  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'employeeFullName': employeeFullName,
    'employeePosition': employeePosition,
    'employeeHireDate': employeeHireDate?.toIso8601String(),
    'employeeSeparationDate': employeeSeparationDate?.toIso8601String(),
    'companyId': companyId,
    'companyName': companyName,
    'companyAddress': companyAddress,
    'hrManagerName': hrManagerName,
    'lastNetPay': lastNetPay.toString(),
    'thirteenthMonth': thirteenthMonth.toString(),
    'unusedLeaveConversion': unusedLeaveConversion.toString(),
    'outstandingCashAdvance': outstandingCashAdvance.toString(),
    'otherDeductions': otherDeductions.toString(),
    'otherDeductionsLabel': otherDeductionsLabel,
    'lastNetPayLocked': lastNetPayLocked,
    'thirteenthMonthLocked': thirteenthMonthLocked,
    'unusedLeaveConversionLocked': unusedLeaveConversionLocked,
    'outstandingCashAdvanceLocked': outstandingCashAdvanceLocked,
    'computedAsOf': computedAsOf.toIso8601String(),
    'releaseDate': releaseDate.toIso8601String(),
    'companySignaturePngB64': companySignaturePngB64,
  };
}

const _undef = Object();
