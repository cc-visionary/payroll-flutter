import 'dart:typed_data';

import 'document_template.dart';

class CoeInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeeLastName;
  final String employeeHonorific;
  final String companyId;
  final String companyName;
  final String? companyAddress;
  final String? hrManagerName;
  final String position;
  final String place;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final DateTime dateIssued;
  final Uint8List? logoBytes;

  CoeInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeeLastName = '',
    this.employeeHonorific = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress,
    this.hrManagerName,
    required this.position,
    this.place = '',
    this.dateStart,
    this.dateEnd,
    required this.dateIssued,
    this.logoBytes,
  });

  CoeInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeeLastName,
    String? employeeHonorific,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    String? position,
    String? place,
    DateTime? dateStart,
    DateTime? dateEnd,
    DateTime? dateIssued,
    Uint8List? logoBytes,
  }) =>
      CoeInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeeLastName: employeeLastName ?? this.employeeLastName,
        employeeHonorific: employeeHonorific ?? this.employeeHonorific,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        position: position ?? this.position,
        place: place ?? this.place,
        dateStart: dateStart ?? this.dateStart,
        dateEnd: dateEnd ?? this.dateEnd,
        dateIssued: dateIssued ?? this.dateIssued,
        logoBytes: logoBytes ?? this.logoBytes,
      );

  @override
  Map<String, dynamic> toDebugMap() =>
      {'employeeId': employeeId, 'companyId': companyId, 'position': position};
}
