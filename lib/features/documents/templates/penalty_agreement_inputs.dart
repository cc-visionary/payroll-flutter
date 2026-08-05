import 'dart:typed_data';

import 'package:decimal/decimal.dart';

import 'document_template.dart';

/// One line of the repayment schedule — a `penalty_installments` row reduced
/// to what the agreement prints. Carries its own JSON so a saved agreement
/// re-renders the exact schedule it was issued with, even if the underlying
/// installments are later deducted or edited.
class PenaltyInstallmentLine {
  final int number;
  final Decimal amount;
  final bool isDeducted;

  /// The payroll cut-off this installment is scheduled to come out on.
  /// Defaulted from [projectedCutoffDates] at autofill and overridable per row
  /// on the form. Null on legacy saved agreements, which print no date column.
  final DateTime? scheduledDate;

  const PenaltyInstallmentLine({
    required this.number,
    required this.amount,
    this.isDeducted = false,
    this.scheduledDate,
  });

  PenaltyInstallmentLine copyWith({DateTime? scheduledDate}) =>
      PenaltyInstallmentLine(
        number: number,
        amount: amount,
        isDeducted: isDeducted,
        scheduledDate: scheduledDate ?? this.scheduledDate,
      );

  Map<String, dynamic> toJson() => {
    'number': number,
    'amount': amount.toString(),
    'isDeducted': isDeducted,
    'scheduledDate': scheduledDate?.toIso8601String(),
  };

  factory PenaltyInstallmentLine.fromJson(Map<String, dynamic> json) =>
      PenaltyInstallmentLine(
        number: (json['number'] as num?)?.toInt() ?? 0,
        amount: Decimal.parse((json['amount'] as String?) ?? '0'),
        isDeducted: (json['isDeducted'] as bool?) ?? false,
        scheduledDate: switch (json['scheduledDate']) {
          final String s when s.isNotEmpty => DateTime.tryParse(s),
          _ => null,
        },
      );
}

class PenaltyAgreementInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeePosition;

  final String companyId;
  final String companyName;
  final String companyAddress;
  final String hrManagerName;

  /// The `penalties.id` this agreement documents. Null when the form was
  /// opened ad-hoc for an employee with no active penalty on file.
  final String? penaltyId;

  /// Free-text incident description (`penalties.custom_description`).
  final String description;
  final Decimal totalAmount;
  final DateTime effectiveDate;
  final String? remarks;

  /// The repayment schedule, ordered by installment number.
  final List<PenaltyInstallmentLine> installments;

  // Excluded from toJson — re-resolved from the entity at view time.
  final Uint8List? logoBytes;

  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;

  /// Base64 transparent-PNG signature of the SUBJECT employee (their own
  /// stored `employees.signature_png`). Null → blank wet-signature line,
  /// which is the correct rendering for an unsigned conforme.
  final String? employeeSignaturePngB64;

  PenaltyAgreementInputs({
    required this.employeeId,
    required this.employeeFullName,
    this.employeePosition = '',
    required this.companyId,
    required this.companyName,
    this.companyAddress = '',
    this.hrManagerName = '',
    this.penaltyId,
    this.description = '',
    Decimal? totalAmount,
    required this.effectiveDate,
    this.remarks,
    this.installments = const [],
    this.logoBytes,
    this.companySignaturePngB64,
    this.employeeSignaturePngB64,
  }) : totalAmount = totalAmount ?? Decimal.zero;

  factory PenaltyAgreementInputs.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    Decimal? parseDecimal(Object? v) {
      if (v == null) return null;
      final s = v as String;
      if (s.isEmpty) return null;
      return Decimal.parse(s);
    }

    return PenaltyAgreementInputs(
      employeeId: json['employeeId'] as String,
      employeeFullName: json['employeeFullName'] as String,
      employeePosition: (json['employeePosition'] as String?) ?? '',
      companyId: json['companyId'] as String,
      companyName: json['companyName'] as String,
      companyAddress: (json['companyAddress'] as String?) ?? '',
      hrManagerName: (json['hrManagerName'] as String?) ?? '',
      penaltyId: json['penaltyId'] as String?,
      description: (json['description'] as String?) ?? '',
      totalAmount: parseDecimal(json['totalAmount']),
      effectiveDate: parseDate(json['effectiveDate'])!,
      remarks: json['remarks'] as String?,
      installments: ((json['installments'] as List?) ?? const [])
          .map(
            (e) => PenaltyInstallmentLine.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      // logoBytes is intentionally excluded from toJson (binary), so it
      // cannot be reconstructed here; it stays null.
      companySignaturePngB64: json['companySignaturePngB64'] as String?,
      employeeSignaturePngB64: json['employeeSignaturePngB64'] as String?,
    );
  }

  /// Sum of the scheduled installment amounts. Must equal [totalAmount] for
  /// the agreement to validate.
  Decimal get scheduledTotal =>
      installments.fold(Decimal.zero, (sum, l) => sum + l.amount);

  PenaltyAgreementInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeePosition,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    Object? penaltyId = _undef,
    String? description,
    Decimal? totalAmount,
    DateTime? effectiveDate,
    Object? remarks = _undef,
    List<PenaltyInstallmentLine>? installments,
    Uint8List? logoBytes,
    String? companySignaturePngB64,
    String? employeeSignaturePngB64,
  }) => PenaltyAgreementInputs(
    employeeId: employeeId ?? this.employeeId,
    employeeFullName: employeeFullName ?? this.employeeFullName,
    employeePosition: employeePosition ?? this.employeePosition,
    companyId: companyId ?? this.companyId,
    companyName: companyName ?? this.companyName,
    companyAddress: companyAddress ?? this.companyAddress,
    hrManagerName: hrManagerName ?? this.hrManagerName,
    penaltyId: identical(penaltyId, _undef)
        ? this.penaltyId
        : penaltyId as String?,
    description: description ?? this.description,
    totalAmount: totalAmount ?? this.totalAmount,
    effectiveDate: effectiveDate ?? this.effectiveDate,
    remarks: identical(remarks, _undef) ? this.remarks : remarks as String?,
    installments: installments ?? this.installments,
    logoBytes: logoBytes ?? this.logoBytes,
    companySignaturePngB64:
        companySignaturePngB64 ?? this.companySignaturePngB64,
    employeeSignaturePngB64:
        employeeSignaturePngB64 ?? this.employeeSignaturePngB64,
  );

  @override
  Map<String, dynamic> toDebugMap() => {
    'employeeId': employeeId,
    'penaltyId': penaltyId,
    'totalAmount': totalAmount.toString(),
    'installmentCount': installments.length,
    'companySignaturePngB64': companySignaturePngB64 == null
        ? null
        : '<png b64, ${companySignaturePngB64!.length} chars>',
    'employeeSignaturePngB64': employeeSignaturePngB64 == null
        ? null
        : '<png b64, ${employeeSignaturePngB64!.length} chars>',
  };

  @override
  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'employeeFullName': employeeFullName,
    'employeePosition': employeePosition,
    'companyId': companyId,
    'companyName': companyName,
    'companyAddress': companyAddress,
    'hrManagerName': hrManagerName,
    'penaltyId': penaltyId,
    'description': description,
    'totalAmount': totalAmount.toString(),
    'effectiveDate': effectiveDate.toIso8601String(),
    'remarks': remarks,
    'installments': installments.map((l) => l.toJson()).toList(),
    'companySignaturePngB64': companySignaturePngB64,
    'employeeSignaturePngB64': employeeSignaturePngB64,
  };
}

const _undef = Object();
