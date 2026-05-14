import 'document_template.dart';

class SubFinding {
  final String title;
  final String body;
  const SubFinding({required this.title, required this.body});
}

class FindingSection {
  final String title;
  final String standard;
  final String finding;
  final List<SubFinding> subFindings;
  const FindingSection({
    required this.title,
    required this.standard,
    required this.finding,
    this.subFindings = const [],
  });
}

class NonRegInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeeLastName;
  final String employeePosition;
  final String companyId;
  final String companyName;
  final String? companyAddress;
  final String? hrManagerName;
  final DateTime dateIssued;
  final DateTime? probationaryStart;
  final DateTime? probationaryEnd;
  final DateTime? effectiveEndDate;
  final String salutationName;
  final String noteOnScope;
  final List<FindingSection> findings;
  final String witnessName;

  NonRegInputs({
    required this.employeeId,
    required this.employeeFullName,
    required this.employeeLastName,
    required this.employeePosition,
    required this.companyId,
    required this.companyName,
    this.companyAddress,
    this.hrManagerName,
    required this.dateIssued,
    this.probationaryStart,
    this.probationaryEnd,
    this.effectiveEndDate,
    required this.salutationName,
    this.noteOnScope = '',
    required this.findings,
    this.witnessName = '',
  });

  NonRegInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeeLastName,
    String? employeePosition,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    DateTime? dateIssued,
    DateTime? probationaryStart,
    DateTime? probationaryEnd,
    DateTime? effectiveEndDate,
    String? salutationName,
    String? noteOnScope,
    List<FindingSection>? findings,
    String? witnessName,
  }) =>
      NonRegInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeeLastName: employeeLastName ?? this.employeeLastName,
        employeePosition: employeePosition ?? this.employeePosition,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        dateIssued: dateIssued ?? this.dateIssued,
        probationaryStart: probationaryStart ?? this.probationaryStart,
        probationaryEnd: probationaryEnd ?? this.probationaryEnd,
        effectiveEndDate: effectiveEndDate ?? this.effectiveEndDate,
        salutationName: salutationName ?? this.salutationName,
        noteOnScope: noteOnScope ?? this.noteOnScope,
        findings: findings ?? this.findings,
        witnessName: witnessName ?? this.witnessName,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'findingCount': findings.length,
        'subFindingCount':
            findings.fold<int>(0, (n, f) => n + f.subFindings.length),
      };
}
