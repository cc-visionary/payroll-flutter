import 'dart:typed_data';

import 'package:flutter_quill/quill_delta.dart';

import 'document_template.dart';

class NteCharge {
  final String title;
  final Delta body;
  const NteCharge({required this.title, required this.body});

  Map<String, dynamic> toJson() => {'title': title, 'body': body.toJson()};

  factory NteCharge.fromJson(Map<String, dynamic> json) => NteCharge(
    title: json['title'] as String,
    body: Delta.fromJson((json['body'] as List?) ?? const []),
  );
}

class NteInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeeFirstName;
  final String employeeLastName;
  final String employeeHonorific;
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
  final Uint8List? logoBytes;
  final Uint8List? attachmentBytes;
  final String? attachmentCaption;

  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;

  NteInputs({
    required this.employeeId,
    required this.employeeFullName,
    required this.employeeFirstName,
    required this.employeeLastName,
    this.employeeHonorific = '',
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
    this.logoBytes,
    this.attachmentBytes,
    this.attachmentCaption,
    this.companySignaturePngB64,
  });

  factory NteInputs.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) => DateTime.parse(v as String);

    return NteInputs(
      employeeId: json['employeeId'] as String,
      employeeFullName: json['employeeFullName'] as String,
      employeeFirstName: json['employeeFirstName'] as String,
      employeeLastName: json['employeeLastName'] as String,
      employeeHonorific: (json['employeeHonorific'] as String?) ?? '',
      employeePosition: json['employeePosition'] as String,
      employeeDepartment: json['employeeDepartment'] as String,
      companyId: json['companyId'] as String,
      companyName: json['companyName'] as String,
      companyAddress: json['companyAddress'] as String?,
      hrManagerName: json['hrManagerName'] as String?,
      dateIssued: parseDate(json['dateIssued']),
      responseDeadline: parseDate(json['responseDeadline']),
      subjectSubtopic: json['subjectSubtopic'] as String,
      charges: ((json['charges'] as List?) ?? const [])
          .map((e) => NteCharge.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      applicableViolations:
          ((json['applicableViolations'] as List?) ?? const [])
              .map((e) => e as String)
              .toList(),
      // logoBytes is intentionally excluded from toJson (binary), so it
      // cannot be reconstructed here; it stays null.
      companySignaturePngB64: json['companySignaturePngB64'] as String?,
    );
  }

  String get finalSubject {
    if (subjectSubtopic.trim().isEmpty) return 'Notice to Explain';
    return 'Notice to Explain — ${subjectSubtopic.trim()}';
  }

  NteInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeeFirstName,
    String? employeeLastName,
    String? employeeHonorific,
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
    Uint8List? logoBytes,
    Object? attachmentBytes = _undef,
    Object? attachmentCaption = _undef,
    String? companySignaturePngB64,
  }) => NteInputs(
    employeeId: employeeId ?? this.employeeId,
    employeeFullName: employeeFullName ?? this.employeeFullName,
    employeeFirstName: employeeFirstName ?? this.employeeFirstName,
    employeeLastName: employeeLastName ?? this.employeeLastName,
    employeeHonorific: employeeHonorific ?? this.employeeHonorific,
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
    applicableViolations: applicableViolations ?? this.applicableViolations,
    logoBytes: logoBytes ?? this.logoBytes,
    attachmentBytes: identical(attachmentBytes, _undef)
        ? this.attachmentBytes
        : attachmentBytes as Uint8List?,
    attachmentCaption: identical(attachmentCaption, _undef)
        ? this.attachmentCaption
        : attachmentCaption as String?,
    companySignaturePngB64:
        companySignaturePngB64 ?? this.companySignaturePngB64,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'companyId': companyId,
    'chargeCount': charges.length,
    'violationCount': applicableViolations.length,
    'companySignaturePngB64': companySignaturePngB64 == null
        ? null
        : '<png b64, ${companySignaturePngB64!.length} chars>',
  };

  @override
  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'employeeFullName': employeeFullName,
    'employeeFirstName': employeeFirstName,
    'employeeLastName': employeeLastName,
    'employeeHonorific': employeeHonorific,
    'employeePosition': employeePosition,
    'employeeDepartment': employeeDepartment,
    'companyId': companyId,
    'companyName': companyName,
    'companyAddress': companyAddress,
    'hrManagerName': hrManagerName,
    'dateIssued': dateIssued.toIso8601String(),
    'responseDeadline': responseDeadline.toIso8601String(),
    'subjectSubtopic': subjectSubtopic,
    'charges': charges.map((c) => c.toJson()).toList(),
    'applicableViolations': applicableViolations,
    'companySignaturePngB64': companySignaturePngB64,
  };
}

const _undef = Object();
