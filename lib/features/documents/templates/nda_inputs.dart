import 'document_template.dart';

class NdaInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeHomeAddress;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final DateTime? effectiveDate;
  final String authorizedSignatoryName;
  final String authorizedSignatoryRole;

  NdaInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeHomeAddress = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.effectiveDate,
    this.authorizedSignatoryName = '',
    this.authorizedSignatoryRole = 'Authorized Signatory',
  });

  NdaInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeHomeAddress,
    String? companyId,
    String? companyName,
    String? companyAddress,
    Object? effectiveDate = _undef,
    String? authorizedSignatoryName,
    String? authorizedSignatoryRole,
  }) =>
      NdaInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeePosition: employeePosition ?? this.employeePosition,
        employeeHomeAddress: employeeHomeAddress ?? this.employeeHomeAddress,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        effectiveDate: identical(effectiveDate, _undef)
            ? this.effectiveDate
            : effectiveDate as DateTime?,
        authorizedSignatoryName:
            authorizedSignatoryName ?? this.authorizedSignatoryName,
        authorizedSignatoryRole:
            authorizedSignatoryRole ?? this.authorizedSignatoryRole,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'position': employeePosition,
      };

  @override
  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'employeeFullName': employeeFullName,
        'employeePosition': employeePosition,
        'employeeHomeAddress': employeeHomeAddress,
        'companyId': companyId,
        'companyName': companyName,
        'companyAddress': companyAddress,
        'effectiveDate': effectiveDate?.toIso8601String(),
        'authorizedSignatoryName': authorizedSignatoryName,
        'authorizedSignatoryRole': authorizedSignatoryRole,
      };
}

const _undef = Object();
