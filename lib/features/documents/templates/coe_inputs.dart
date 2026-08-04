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

  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;

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
    this.companySignaturePngB64,
  });

  factory CoeInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return CoeInputs(
      employeeId: json['employeeId'] as String,
      employeeFullName: json['employeeFullName'] as String,
      employeeLastName: (json['employeeLastName'] as String?) ?? '',
      employeeHonorific: (json['employeeHonorific'] as String?) ?? '',
      companyId: json['companyId'] as String,
      companyName: json['companyName'] as String,
      companyAddress: json['companyAddress'] as String?,
      hrManagerName: json['hrManagerName'] as String?,
      position: json['position'] as String,
      place: (json['place'] as String?) ?? '',
      dateStart: parseDate(json['dateStart']),
      dateEnd: parseDate(json['dateEnd']),
      dateIssued: parseDate(json['dateIssued'])!,
      // logoBytes is intentionally excluded from toJson (binary), so it
      // cannot be reconstructed here; it stays null.
      companySignaturePngB64: json['companySignaturePngB64'] as String?,
    );
  }

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
    String? companySignaturePngB64,
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
        companySignaturePngB64:
            companySignaturePngB64 ?? this.companySignaturePngB64,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'position': position,
        'companySignaturePngB64': companySignaturePngB64 == null
            ? null
            : '<png b64, ${companySignaturePngB64!.length} chars>',
      };

  @override
  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'employeeFullName': employeeFullName,
        'employeeLastName': employeeLastName,
        'employeeHonorific': employeeHonorific,
        'companyId': companyId,
        'companyName': companyName,
        'companyAddress': companyAddress,
        'hrManagerName': hrManagerName,
        'position': position,
        'place': place,
        'dateStart': dateStart?.toIso8601String(),
        'dateEnd': dateEnd?.toIso8601String(),
        'dateIssued': dateIssued.toIso8601String(),
        'companySignaturePngB64': companySignaturePngB64,
      };
}
