import 'dart:typed_data';

import 'document_template.dart';

class SubFinding {
  final String title;
  final String body;
  const SubFinding({required this.title, required this.body});

  factory SubFinding.fromJson(Map<String, dynamic> json) => SubFinding(
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'title': title, 'body': body};
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

  factory FindingSection.fromJson(Map<String, dynamic> json) => FindingSection(
    title: json['title'] as String? ?? '',
    standard: json['standard'] as String? ?? '',
    finding: json['finding'] as String? ?? '',
    subFindings: ((json['subFindings'] as List?) ?? const [])
        .map((e) => SubFinding.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'standard': standard,
    'finding': finding,
    'subFindings': subFindings.map((s) => s.toJson()).toList(),
  };
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
  final Uint8List? logoBytes;

  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;

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
    this.logoBytes,
    this.companySignaturePngB64,
  });

  /// Inverse of [toJson]. `logoBytes` is intentionally absent from the JSON
  /// snapshot, so it is left null here. Nullable date/string fields preserve
  /// nulls; `noteOnScope` / `witnessName` fall back to their constructor
  /// defaults if the key is missing or null.
  factory NonRegInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return NonRegInputs(
      employeeId: json['employeeId'] as String? ?? '',
      employeeFullName: json['employeeFullName'] as String? ?? '',
      employeeLastName: json['employeeLastName'] as String? ?? '',
      employeePosition: json['employeePosition'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      companyAddress: json['companyAddress'] as String?,
      hrManagerName: json['hrManagerName'] as String?,
      dateIssued: parseDate(json['dateIssued']) ?? DateTime.now(),
      probationaryStart: parseDate(json['probationaryStart']),
      probationaryEnd: parseDate(json['probationaryEnd']),
      effectiveEndDate: parseDate(json['effectiveEndDate']),
      salutationName: json['salutationName'] as String? ?? '',
      noteOnScope: json['noteOnScope'] as String? ?? '',
      findings: ((json['findings'] as List?) ?? const [])
          .map(
            (e) => FindingSection.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      witnessName: json['witnessName'] as String? ?? '',
      companySignaturePngB64: json['companySignaturePngB64'] as String?,
    );
  }

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
    Uint8List? logoBytes,
    String? companySignaturePngB64,
  }) => NonRegInputs(
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
    logoBytes: logoBytes ?? this.logoBytes,
    companySignaturePngB64:
        companySignaturePngB64 ?? this.companySignaturePngB64,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'companyId': companyId,
    'findingCount': findings.length,
    'subFindingCount': findings.fold<int>(
      0,
      (n, f) => n + f.subFindings.length,
    ),
    'companySignaturePngB64': companySignaturePngB64 == null
        ? null
        : '<png b64, ${companySignaturePngB64!.length} chars>',
  };

  @override
  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'employeeFullName': employeeFullName,
    'employeeLastName': employeeLastName,
    'employeePosition': employeePosition,
    'companyId': companyId,
    'companyName': companyName,
    'companyAddress': companyAddress,
    'hrManagerName': hrManagerName,
    'dateIssued': dateIssued.toIso8601String(),
    'probationaryStart': probationaryStart?.toIso8601String(),
    'probationaryEnd': probationaryEnd?.toIso8601String(),
    'effectiveEndDate': effectiveEndDate?.toIso8601String(),
    'salutationName': salutationName,
    'noteOnScope': noteOnScope,
    'findings': findings.map((f) => f.toJson()).toList(),
    'witnessName': witnessName,
    'companySignaturePngB64': companySignaturePngB64,
  };
}
