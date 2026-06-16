import 'document_template.dart';

enum NodDecision {
  reprimand,
  writtenWarning,
  suspension,
  termination,
  noAction,
}

extension NodDecisionX on NodDecision {
  String get label => switch (this) {
    NodDecision.reprimand => 'Reprimand',
    NodDecision.writtenWarning => 'Written Warning',
    NodDecision.suspension => 'Suspension',
    NodDecision.termination => 'Termination',
    NodDecision.noAction => 'No Action',
  };
}

class NodInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;
  final String employeeGender;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;

  final String? linkedNteDocumentId;
  final DateTime? nteDate;
  final String charges;
  final String employeeResponseSummary;
  final String findings;

  final NodDecision decision;
  final int suspensionDays;
  final DateTime effectiveDate;
  final DateTime issueDate;

  NodInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    this.employeeGender = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    this.linkedNteDocumentId,
    this.nteDate,
    this.charges = '',
    this.employeeResponseSummary = '',
    this.findings = '',
    this.decision = NodDecision.writtenWarning,
    this.suspensionDays = 0,
    required this.effectiveDate,
    required this.issueDate,
  });

  factory NodInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return NodInputs(
      employeeId: json['employeeId'] as String,
      employeeFullName: json['employeeFullName'] as String,
      employeePosition: (json['employeePosition'] as String?) ?? '',
      employeeGender: (json['employeeGender'] as String?) ?? '',
      companyId: json['companyId'] as String,
      companyName: json['companyName'] as String,
      companyAddress: (json['companyAddress'] as String?) ?? '',
      hrManagerName: (json['hrManagerName'] as String?) ?? '',
      linkedNteDocumentId: json['linkedNteDocumentId'] as String?,
      nteDate: parseDate(json['nteDate']),
      charges: (json['charges'] as String?) ?? '',
      employeeResponseSummary:
          (json['employeeResponseSummary'] as String?) ?? '',
      findings: (json['findings'] as String?) ?? '',
      decision: NodDecision.values.byName(json['decision'] as String),
      suspensionDays: (json['suspensionDays'] as num?)?.toInt() ?? 0,
      effectiveDate: parseDate(json['effectiveDate'])!,
      issueDate: parseDate(json['issueDate'])!,
    );
  }

  NodInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? employeeGender,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Object? linkedNteDocumentId = _undef,
    Object? nteDate = _undef,
    String? charges,
    String? employeeResponseSummary,
    String? findings,
    NodDecision? decision,
    int? suspensionDays,
    DateTime? effectiveDate,
    DateTime? issueDate,
  }) => NodInputs(
    employeeId: employeeId ?? this.employeeId,
    employeeFullName: employeeFullName ?? this.employeeFullName,
    employeePosition: employeePosition ?? this.employeePosition,
    employeeGender: employeeGender ?? this.employeeGender,
    companyId: companyId ?? this.companyId,
    companyName: companyName ?? this.companyName,
    companyAddress: companyAddress ?? this.companyAddress,
    hrManagerName: hrManagerName ?? this.hrManagerName,
    linkedNteDocumentId: identical(linkedNteDocumentId, _undef)
        ? this.linkedNteDocumentId
        : linkedNteDocumentId as String?,
    nteDate: identical(nteDate, _undef) ? this.nteDate : nteDate as DateTime?,
    charges: charges ?? this.charges,
    employeeResponseSummary:
        employeeResponseSummary ?? this.employeeResponseSummary,
    findings: findings ?? this.findings,
    decision: decision ?? this.decision,
    suspensionDays: suspensionDays ?? this.suspensionDays,
    effectiveDate: effectiveDate ?? this.effectiveDate,
    issueDate: issueDate ?? this.issueDate,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'decision': decision.name,
    'linkedNte': linkedNteDocumentId,
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
    'linkedNteDocumentId': linkedNteDocumentId,
    'nteDate': nteDate?.toIso8601String(),
    'charges': charges,
    'employeeResponseSummary': employeeResponseSummary,
    'findings': findings,
    'decision': decision.name,
    'suspensionDays': suspensionDays,
    'effectiveDate': effectiveDate.toIso8601String(),
    'issueDate': issueDate.toIso8601String(),
  };
}

const _undef = Object();
