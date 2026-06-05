import 'document_template.dart';

const String kDefaultTurnoverInstructions =
    'Please coordinate with your direct manager for proper turnover of pending tasks and Company property (laptop, ID, access cards, etc.).';

class ResignationAcceptanceInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeGender;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;

  final DateTime resignationDate;
  final DateTime lastDayOfWork;
  final DateTime issueDate;
  final String turnoverInstructions;
  final bool includeClearanceMention;
  final bool includeFinalPayMention;

  ResignationAcceptanceInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeGender = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    required this.resignationDate,
    required this.lastDayOfWork,
    required this.issueDate,
    this.turnoverInstructions = kDefaultTurnoverInstructions,
    this.includeClearanceMention = true,
    this.includeFinalPayMention = true,
  });

  ResignationAcceptanceInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeGender,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    DateTime? resignationDate,
    DateTime? lastDayOfWork,
    DateTime? issueDate,
    String? turnoverInstructions,
    bool? includeClearanceMention,
    bool? includeFinalPayMention,
  }) => ResignationAcceptanceInputs(
    employeeId: employeeId ?? this.employeeId,
    employeeFullName: employeeFullName ?? this.employeeFullName,
    employeePosition: employeePosition ?? this.employeePosition,
    employeeGender: employeeGender ?? this.employeeGender,
    companyId: companyId ?? this.companyId,
    companyName: companyName ?? this.companyName,
    companyAddress: companyAddress ?? this.companyAddress,
    hrManagerName: hrManagerName ?? this.hrManagerName,
    resignationDate: resignationDate ?? this.resignationDate,
    lastDayOfWork: lastDayOfWork ?? this.lastDayOfWork,
    issueDate: issueDate ?? this.issueDate,
    turnoverInstructions: turnoverInstructions ?? this.turnoverInstructions,
    includeClearanceMention:
        includeClearanceMention ?? this.includeClearanceMention,
    includeFinalPayMention:
        includeFinalPayMention ?? this.includeFinalPayMention,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'lastDayOfWork': lastDayOfWork.toIso8601String(),
  };
}
