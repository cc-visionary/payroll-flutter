import 'dart:typed_data';

import 'document_template.dart';

class CoeInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String companyId;
  final String companyName;
  final String? companyAddress;
  final String? hrManagerName;
  final String position;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final Uint8List? logoBytes;

  CoeInputs({
    required this.employeeId,
    required this.employeeFullName,
    required this.companyId,
    required this.companyName,
    this.companyAddress,
    this.hrManagerName,
    required this.position,
    this.dateStart,
    this.dateEnd,
    this.logoBytes,
  });

  CoeInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    String? position,
    DateTime? dateStart,
    DateTime? dateEnd,
    Uint8List? logoBytes,
  }) =>
      CoeInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        position: position ?? this.position,
        dateStart: dateStart ?? this.dateStart,
        dateEnd: dateEnd ?? this.dateEnd,
        logoBytes: logoBytes ?? this.logoBytes,
      );

  @override
  Map<String, dynamic> toDebugMap() =>
      {'employeeId': employeeId, 'companyId': companyId, 'position': position};
}
