import 'document_template.dart';

class LiabilityWaiverInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeeAddress;
  final String companyId;
  final String companyName;
  final DateTime? dateOfEmployment;
  final DateTime? outingDate;
  final String outingLocation;
  final DateTime dateSigned;
  final String signingPlace;

  LiabilityWaiverInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeeAddress = '',
    required this.companyId,
    required this.companyName,
    this.dateOfEmployment,
    this.outingDate,
    this.outingLocation = '',
    required this.dateSigned,
    this.signingPlace = '',
  });

  factory LiabilityWaiverInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return LiabilityWaiverInputs(
      employeeId: json['employeeId'] as String? ?? '',
      employeeFullName: json['employeeFullName'] as String? ?? '',
      employeeAddress: json['employeeAddress'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      dateOfEmployment: parseDate(json['dateOfEmployment']),
      outingDate: parseDate(json['outingDate']),
      outingLocation: json['outingLocation'] as String? ?? '',
      dateSigned: parseDate(json['dateSigned']) ?? DateTime.now(),
      signingPlace: json['signingPlace'] as String? ?? '',
    );
  }

  LiabilityWaiverInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeeAddress,
    String? companyId,
    String? companyName,
    Object? dateOfEmployment = _undef,
    Object? outingDate = _undef,
    String? outingLocation,
    DateTime? dateSigned,
    String? signingPlace,
  }) =>
      LiabilityWaiverInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeeAddress: employeeAddress ?? this.employeeAddress,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        dateOfEmployment: identical(dateOfEmployment, _undef)
            ? this.dateOfEmployment
            : dateOfEmployment as DateTime?,
        outingDate: identical(outingDate, _undef)
            ? this.outingDate
            : outingDate as DateTime?,
        outingLocation: outingLocation ?? this.outingLocation,
        dateSigned: dateSigned ?? this.dateSigned,
        signingPlace: signingPlace ?? this.signingPlace,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
      };

  @override
  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'employeeFullName': employeeFullName,
        'employeeAddress': employeeAddress,
        'companyId': companyId,
        'companyName': companyName,
        'dateOfEmployment': dateOfEmployment?.toIso8601String(),
        'outingDate': outingDate?.toIso8601String(),
        'outingLocation': outingLocation,
        'dateSigned': dateSigned.toIso8601String(),
        'signingPlace': signingPlace,
      };
}

const _undef = Object();
