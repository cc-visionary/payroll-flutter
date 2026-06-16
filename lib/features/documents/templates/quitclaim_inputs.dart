import 'package:decimal/decimal.dart';
import 'document_template.dart';

class QuitclaimInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeeAddress;
  final String civilStatus;      // e.g. 'single', 'married'
  final String companyId;
  final String companyName;
  final Decimal finalPayAmount;
  final DateTime? dateTerminated;
  final DateTime dateSigned;
  final String placeSigned;      // where the document is signed (company address)

  QuitclaimInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeeAddress = '',
    this.civilStatus = 'single',
    required this.companyId,
    required this.companyName,
    required this.finalPayAmount,
    this.dateTerminated,
    required this.dateSigned,
    this.placeSigned = '',
  });

  factory QuitclaimInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return QuitclaimInputs(
      employeeId: json['employeeId'] as String,
      employeeFullName: json['employeeFullName'] as String,
      employeeAddress: (json['employeeAddress'] as String?) ?? '',
      civilStatus: (json['civilStatus'] as String?) ?? 'single',
      companyId: json['companyId'] as String,
      companyName: json['companyName'] as String,
      finalPayAmount: Decimal.parse(json['finalPayAmount'] as String),
      dateTerminated: parseDate(json['dateTerminated']),
      dateSigned: parseDate(json['dateSigned'])!,
      placeSigned: (json['placeSigned'] as String?) ?? '',
    );
  }

  QuitclaimInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeeAddress,
    String? civilStatus,
    String? companyId,
    String? companyName,
    Decimal? finalPayAmount,
    Object? dateTerminated = _undef,
    DateTime? dateSigned,
    String? placeSigned,
  }) =>
      QuitclaimInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeeAddress: employeeAddress ?? this.employeeAddress,
        civilStatus: civilStatus ?? this.civilStatus,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        finalPayAmount: finalPayAmount ?? this.finalPayAmount,
        dateTerminated: identical(dateTerminated, _undef)
            ? this.dateTerminated
            : dateTerminated as DateTime?,
        dateSigned: dateSigned ?? this.dateSigned,
        placeSigned: placeSigned ?? this.placeSigned,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'finalPayAmount': finalPayAmount.toString(),
      };

  @override
  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'employeeFullName': employeeFullName,
        'employeeAddress': employeeAddress,
        'civilStatus': civilStatus,
        'companyId': companyId,
        'companyName': companyName,
        'finalPayAmount': finalPayAmount.toString(),
        'dateTerminated': dateTerminated?.toIso8601String(),
        'dateSigned': dateSigned.toIso8601String(),
        'placeSigned': placeSigned,
      };
}

const _undef = Object();
