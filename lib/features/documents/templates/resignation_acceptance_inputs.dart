import 'dart:typed_data';

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
  // Excluded from toJson — re-resolved from the entity at view time.
  final Uint8List? logoBytes;

  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;

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
    this.logoBytes,
    this.companySignaturePngB64,
  });

  factory ResignationAcceptanceInputs.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? v) {
      if (v == null) return DateTime.now();
      final s = v as String;
      if (s.isEmpty) return DateTime.now();
      return DateTime.tryParse(s) ?? DateTime.now();
    }

    return ResignationAcceptanceInputs(
      employeeId: json['employeeId'] as String? ?? '',
      employeeFullName: json['employeeFullName'] as String? ?? '',
      employeePosition: json['employeePosition'] as String? ?? '',
      employeeGender: json['employeeGender'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      companyAddress: json['companyAddress'] as String? ?? '',
      hrManagerName: json['hrManagerName'] as String? ?? '',
      resignationDate: parseDate(json['resignationDate']),
      lastDayOfWork: parseDate(json['lastDayOfWork']),
      issueDate: parseDate(json['issueDate']),
      turnoverInstructions:
          json['turnoverInstructions'] as String? ??
          kDefaultTurnoverInstructions,
      includeClearanceMention:
          json['includeClearanceMention'] as bool? ?? true,
      includeFinalPayMention: json['includeFinalPayMention'] as bool? ?? true,
      companySignaturePngB64: json['companySignaturePngB64'] as String?,
    );
  }

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
    Uint8List? logoBytes,
    String? companySignaturePngB64,
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
    logoBytes: logoBytes ?? this.logoBytes,
    companySignaturePngB64:
        companySignaturePngB64 ?? this.companySignaturePngB64,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'lastDayOfWork': lastDayOfWork.toIso8601String(),
    'companySignaturePngB64': companySignaturePngB64 == null
        ? null
        : '<png b64, ${companySignaturePngB64!.length} chars>',
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
    'resignationDate': resignationDate.toIso8601String(),
    'lastDayOfWork': lastDayOfWork.toIso8601String(),
    'issueDate': issueDate.toIso8601String(),
    'turnoverInstructions': turnoverInstructions,
    'includeClearanceMention': includeClearanceMention,
    'includeFinalPayMention': includeFinalPayMention,
    'companySignaturePngB64': companySignaturePngB64,
  };
}
