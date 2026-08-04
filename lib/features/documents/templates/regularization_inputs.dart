import 'dart:typed_data';

import 'package:decimal/decimal.dart';

import 'document_template.dart';

class RegularizationInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeGender;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;
  final DateTime? hireDate;
  final DateTime regularizationDate;
  final Decimal baseSalary;
  final String salaryPeriod; // MONTHLY | DAILY
  final DateTime issueDate;
  final String performanceSummary;
  // Excluded from toJson — re-resolved from the entity at view time.
  final Uint8List? logoBytes;

  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;

  RegularizationInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeGender = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    this.hireDate,
    required this.regularizationDate,
    Decimal? baseSalary,
    this.salaryPeriod = 'MONTHLY',
    required this.issueDate,
    this.performanceSummary = '',
    this.logoBytes,
    this.companySignaturePngB64,
  }) : baseSalary = baseSalary ?? Decimal.zero;

  factory RegularizationInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    final baseSalaryRaw = json['baseSalary'] as String?;
    return RegularizationInputs(
      employeeId: json['employeeId'] as String? ?? '',
      employeeFullName: json['employeeFullName'] as String? ?? '',
      employeePosition: json['employeePosition'] as String? ?? '',
      employeeGender: json['employeeGender'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      companyAddress: json['companyAddress'] as String? ?? '',
      hrManagerName: json['hrManagerName'] as String? ?? '',
      hireDate: parseDate(json['hireDate']),
      regularizationDate:
          parseDate(json['regularizationDate']) ?? DateTime.now(),
      baseSalary: (baseSalaryRaw == null || baseSalaryRaw.isEmpty)
          ? Decimal.zero
          : Decimal.parse(baseSalaryRaw),
      salaryPeriod: json['salaryPeriod'] as String? ?? 'MONTHLY',
      issueDate: parseDate(json['issueDate']) ?? DateTime.now(),
      performanceSummary: json['performanceSummary'] as String? ?? '',
      companySignaturePngB64: json['companySignaturePngB64'] as String?,
    );
  }

  RegularizationInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeGender,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Object? hireDate = _undef,
    DateTime? regularizationDate,
    Decimal? baseSalary,
    String? salaryPeriod,
    DateTime? issueDate,
    String? performanceSummary,
    Uint8List? logoBytes,
    String? companySignaturePngB64,
  }) => RegularizationInputs(
    employeeId: employeeId ?? this.employeeId,
    employeeFullName: employeeFullName ?? this.employeeFullName,
    employeePosition: employeePosition ?? this.employeePosition,
    employeeGender: employeeGender ?? this.employeeGender,
    companyId: companyId ?? this.companyId,
    companyName: companyName ?? this.companyName,
    companyAddress: companyAddress ?? this.companyAddress,
    hrManagerName: hrManagerName ?? this.hrManagerName,
    hireDate: identical(hireDate, _undef)
        ? this.hireDate
        : hireDate as DateTime?,
    regularizationDate: regularizationDate ?? this.regularizationDate,
    baseSalary: baseSalary ?? this.baseSalary,
    salaryPeriod: salaryPeriod ?? this.salaryPeriod,
    issueDate: issueDate ?? this.issueDate,
    performanceSummary: performanceSummary ?? this.performanceSummary,
    logoBytes: logoBytes ?? this.logoBytes,
    companySignaturePngB64:
        companySignaturePngB64 ?? this.companySignaturePngB64,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'regularizationDate': regularizationDate.toIso8601String(),
    'companySignaturePngB64': companySignaturePngB64 == null
        ? null
        : '<png b64, ${companySignaturePngB64!.length} chars>',
  };

  @override
  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'employeeFullName': employeeFullName,
    'employeePosition': employeePosition,
    'employeeGender': employeeGender,
    'companyId': companyId,
    'companyName': companyName,
    'companyAddress': companyAddress,
    'hrManagerName': hrManagerName,
    'hireDate': hireDate?.toIso8601String(),
    'regularizationDate': regularizationDate.toIso8601String(),
    'baseSalary': baseSalary.toString(),
    'salaryPeriod': salaryPeriod,
    'issueDate': issueDate.toIso8601String(),
    'performanceSummary': performanceSummary,
    'companySignaturePngB64': companySignaturePngB64,
  };
}

const _undef = Object();
