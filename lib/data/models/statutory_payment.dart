import 'package:decimal/decimal.dart';

/// One row in the `statutory_payments` ledger. Append-only with soft-void:
/// when an existing row is corrected, the repository inserts a NEW row and
/// stamps the old one with `voidedAt + voidedById + voidReason`. The view
/// `statutory_payments_paid_v` already filters voided rows out; client code
/// dealing with raw rows (View Payments dialog, audit) checks
/// [isVoided] explicitly.
class StatutoryPayment {
  final String id;
  final String hiringEntityId;
  final int periodYear;
  final int periodMonth;
  final String agency; // statutory_agency enum
  final DateTime paidOn;
  final String? referenceNo;
  final Decimal amountPaid;
  final String? paidById;
  final String? notes;
  final DateTime? voidedAt;
  final String? voidedById;
  final String? voidReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StatutoryPayment({
    required this.id,
    required this.hiringEntityId,
    required this.periodYear,
    required this.periodMonth,
    required this.agency,
    required this.paidOn,
    this.referenceNo,
    required this.amountPaid,
    this.paidById,
    this.notes,
    this.voidedAt,
    this.voidedById,
    this.voidReason,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isVoided => voidedAt != null;

  factory StatutoryPayment.fromRow(Map<String, dynamic> r) {
    Decimal d(Object? v) => Decimal.parse((v ?? '0').toString());
    DateTime parseDt(Object? v) => DateTime.parse(v as String);
    return StatutoryPayment(
      id: r['id'] as String,
      hiringEntityId: r['hiring_entity_id'] as String,
      periodYear: (r['period_year'] as num).toInt(),
      periodMonth: (r['period_month'] as num).toInt(),
      agency: r['agency'] as String,
      paidOn: parseDt(r['paid_on']),
      referenceNo: r['reference_no'] as String?,
      amountPaid: d(r['amount_paid']),
      paidById: r['paid_by_id'] as String?,
      notes: r['notes'] as String?,
      voidedAt: r['voided_at'] == null ? null : parseDt(r['voided_at']),
      voidedById: r['voided_by_id'] as String?,
      voidReason: r['void_reason'] as String?,
      createdAt: parseDt(r['created_at']),
      updatedAt: parseDt(r['updated_at']),
    );
  }
}
