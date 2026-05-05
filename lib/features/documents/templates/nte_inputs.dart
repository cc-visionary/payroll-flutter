import 'package:flutter_quill/quill_delta.dart';

import 'document_template.dart';

class NteCharge {
  final String title;
  final Delta body;
  const NteCharge({required this.title, required this.body});
}

class NteInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeeFirstName;
  final String employeeLastName;
  final String employeePosition;
  final String employeeDepartment;
  final String companyId;
  final String companyName;
  final String? companyAddress;
  final String? hrManagerName;
  final DateTime dateIssued;
  final DateTime responseDeadline;
  final String subjectSubtopic;
  final List<NteCharge> charges;
  final List<String> applicableViolations;

  NteInputs({
    required this.employeeId,
    required this.employeeFullName,
    required this.employeeFirstName,
    required this.employeeLastName,
    required this.employeePosition,
    required this.employeeDepartment,
    required this.companyId,
    required this.companyName,
    this.companyAddress,
    this.hrManagerName,
    required this.dateIssued,
    required this.responseDeadline,
    required this.subjectSubtopic,
    required this.charges,
    required this.applicableViolations,
  });

  String get finalSubject {
    if (subjectSubtopic.trim().isEmpty) return 'Notice to Explain';
    return 'Notice to Explain — ${subjectSubtopic.trim()}';
  }

  NteInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeeFirstName,
    String? employeeLastName,
    String? employeePosition,
    String? employeeDepartment,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    DateTime? dateIssued,
    DateTime? responseDeadline,
    String? subjectSubtopic,
    List<NteCharge>? charges,
    List<String>? applicableViolations,
  }) =>
      NteInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeeFirstName: employeeFirstName ?? this.employeeFirstName,
        employeeLastName: employeeLastName ?? this.employeeLastName,
        employeePosition: employeePosition ?? this.employeePosition,
        employeeDepartment: employeeDepartment ?? this.employeeDepartment,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        dateIssued: dateIssued ?? this.dateIssued,
        responseDeadline: responseDeadline ?? this.responseDeadline,
        subjectSubtopic: subjectSubtopic ?? this.subjectSubtopic,
        charges: charges ?? this.charges,
        applicableViolations:
            applicableViolations ?? this.applicableViolations,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'chargeCount': charges.length,
        'violationCount': applicableViolations.length,
      };
}
