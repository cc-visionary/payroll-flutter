import 'package:decimal/decimal.dart';

import 'document_template.dart';

class QuitclaimInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String companyId;
  final String companyName;
  final String? companyAddress;
  final String? companySignatoryName;
  final String? companySignatoryRole;
  final DateTime? dateTerminated;
  final DateTime dateSigned;
  final Decimal finalPayAmount;

  QuitclaimInputs({
    required this.employeeId,
    required this.employeeFullName,
    required this.companyId,
    required this.companyName,
    this.companyAddress,
    this.companySignatoryName,
    this.companySignatoryRole,
    this.dateTerminated,
    required this.dateSigned,
    required this.finalPayAmount,
  });

  QuitclaimInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? companyId,
    String? companyName,
    String? companyAddress,
    Object? companySignatoryName = _undef,
    Object? companySignatoryRole = _undef,
    Object? dateTerminated = _undef,
    DateTime? dateSigned,
    Decimal? finalPayAmount,
  }) {
    return QuitclaimInputs(
      employeeId: employeeId ?? this.employeeId,
      employeeFullName: employeeFullName ?? this.employeeFullName,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      companyAddress: companyAddress ?? this.companyAddress,
      companySignatoryName: identical(companySignatoryName, _undef)
          ? this.companySignatoryName
          : companySignatoryName as String?,
      companySignatoryRole: identical(companySignatoryRole, _undef)
          ? this.companySignatoryRole
          : companySignatoryRole as String?,
      dateTerminated: identical(dateTerminated, _undef)
          ? this.dateTerminated
          : dateTerminated as DateTime?,
      dateSigned: dateSigned ?? this.dateSigned,
      finalPayAmount: finalPayAmount ?? this.finalPayAmount,
    );
  }

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'finalPayAmount': finalPayAmount.toString(),
      };
}

const _undef = Object();
