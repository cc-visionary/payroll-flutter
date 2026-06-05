import 'package:decimal/decimal.dart';

import 'document_template.dart';

enum SalaryAdjustmentType { salaryAdjustment, promotion }

extension SalaryAdjustmentTypeX on SalaryAdjustmentType {
  String get label => switch (this) {
    SalaryAdjustmentType.salaryAdjustment => 'Salary Adjustment',
    SalaryAdjustmentType.promotion => 'Promotion',
  };
}

class SalaryAdjustmentInputs extends TemplateInputs {
  final SalaryAdjustmentType type;
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeGender; // 'MALE' | 'FEMALE' | '' — for salutation
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;
  // Promotion-only role-change fields
  final String? oldRoleScorecardId;
  final String? newRoleScorecardId;
  final String oldPosition;
  final String newPosition;
  // Salary (always)
  final Decimal oldSalary;
  final Decimal newSalary;
  final String salaryPeriod; // 'MONTHLY' | 'DAILY'
  final DateTime effectiveDate;
  final DateTime issueDate;
  final String reason;

  SalaryAdjustmentInputs({
    this.type = SalaryAdjustmentType.salaryAdjustment,
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeGender = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    this.oldRoleScorecardId,
    this.newRoleScorecardId,
    this.oldPosition = '',
    this.newPosition = '',
    Decimal? oldSalary,
    Decimal? newSalary,
    this.salaryPeriod = 'MONTHLY',
    required this.effectiveDate,
    required this.issueDate,
    this.reason = '',
  }) : oldSalary = oldSalary ?? Decimal.zero,
       newSalary = newSalary ?? Decimal.zero;

  SalaryAdjustmentInputs copyWith({
    SalaryAdjustmentType? type,
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeGender,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Object? oldRoleScorecardId = _undef,
    Object? newRoleScorecardId = _undef,
    String? oldPosition,
    String? newPosition,
    Decimal? oldSalary,
    Decimal? newSalary,
    String? salaryPeriod,
    DateTime? effectiveDate,
    DateTime? issueDate,
    String? reason,
  }) => SalaryAdjustmentInputs(
    type: type ?? this.type,
    employeeId: employeeId ?? this.employeeId,
    employeeFullName: employeeFullName ?? this.employeeFullName,
    employeePosition: employeePosition ?? this.employeePosition,
    employeeGender: employeeGender ?? this.employeeGender,
    companyId: companyId ?? this.companyId,
    companyName: companyName ?? this.companyName,
    companyAddress: companyAddress ?? this.companyAddress,
    hrManagerName: hrManagerName ?? this.hrManagerName,
    oldRoleScorecardId: identical(oldRoleScorecardId, _undef)
        ? this.oldRoleScorecardId
        : oldRoleScorecardId as String?,
    newRoleScorecardId: identical(newRoleScorecardId, _undef)
        ? this.newRoleScorecardId
        : newRoleScorecardId as String?,
    oldPosition: oldPosition ?? this.oldPosition,
    newPosition: newPosition ?? this.newPosition,
    oldSalary: oldSalary ?? this.oldSalary,
    newSalary: newSalary ?? this.newSalary,
    salaryPeriod: salaryPeriod ?? this.salaryPeriod,
    effectiveDate: effectiveDate ?? this.effectiveDate,
    issueDate: issueDate ?? this.issueDate,
    reason: reason ?? this.reason,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'type': type.name,
    'employeeId': employeeId,
    'effective': effectiveDate.toIso8601String(),
  };
}

const _undef = Object();
