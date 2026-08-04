import 'dart:typed_data';

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
  // Excluded from toJson — re-resolved from the entity at view time.
  final Uint8List? logoBytes;

  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;

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
    this.logoBytes,
    this.companySignaturePngB64,
  });

  /// Inverse of [toJson]. `effectiveDate` preserves null; the optional string
  /// fields fall back to their constructor defaults when the key is missing or
  /// null (`authorizedSignatoryRole` defaults to 'Authorized Signatory').
  factory NdaInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return NdaInputs(
      employeeId: json['employeeId'] as String? ?? '',
      employeeFullName: json['employeeFullName'] as String? ?? '',
      employeePosition: json['employeePosition'] as String? ?? '',
      employeeHomeAddress: json['employeeHomeAddress'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      companyAddress: json['companyAddress'] as String? ?? '',
      effectiveDate: parseDate(json['effectiveDate']),
      authorizedSignatoryName: json['authorizedSignatoryName'] as String? ?? '',
      authorizedSignatoryRole:
          json['authorizedSignatoryRole'] as String? ?? 'Authorized Signatory',
      companySignaturePngB64: json['companySignaturePngB64'] as String?,
    );
  }

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
    Uint8List? logoBytes,
    String? companySignaturePngB64,
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
        logoBytes: logoBytes ?? this.logoBytes,
        companySignaturePngB64:
            companySignaturePngB64 ?? this.companySignaturePngB64,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'position': employeePosition,
        'companySignaturePngB64': companySignaturePngB64 == null
            ? null
            : '<png b64, ${companySignaturePngB64!.length} chars>',
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
        'companySignaturePngB64': companySignaturePngB64,
      };
}

const _undef = Object();
