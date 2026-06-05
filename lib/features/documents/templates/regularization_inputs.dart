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
  }) : baseSalary = baseSalary ?? Decimal.zero;

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
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'regularizationDate': regularizationDate.toIso8601String(),
  };
}

const _undef = Object();
