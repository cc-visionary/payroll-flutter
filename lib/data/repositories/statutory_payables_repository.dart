import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/statutory_payable.dart';
import '../models/statutory_payment.dart';

/// Read + write surface for the Statutory Payables Ledger feature.
///
/// Reads come from three views — `statutory_payables_due_v` for what is
/// owed, `statutory_payments_paid_v` for the rolled-up paid totals, and
/// `statutory_payable_breakdown_v` for per-employee detail. Writes flow
/// through the append-only `statutory_payments` table.
class StatutoryPayablesRepository {
  final SupabaseClient _client;
  StatutoryPayablesRepository(this._client);

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Fetch every payable for the supplied period range. The view aggregates
  /// at (brand × month × agency); we filter by year+month bounds rather than
  /// dates because pay_periods.end_date.month is the canonical period.
  Future<List<StatutoryPayable>> listPayables({
    required int fromYear,
    required int fromMonth,
    required int toYear,
    required int toMonth,
  }) async {
    final fromKey = fromYear * 100 + fromMonth;
    final toKey = toYear * 100 + toMonth;
    final rows = await _client
        .from('statutory_payables_due_v')
        .select() as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .map(StatutoryPayable.fromRow)
        .where((p) {
          final key = p.periodYear * 100 + p.periodMonth;
          return key >= fromKey && key <= toKey;
        })
        .toList();
  }

  /// Sum of non-voided payments per (brand × month × agency) within range.
  Future<List<StatutoryPaymentSummary>> listPaidSummaries({
    required int fromYear,
    required int fromMonth,
    required int toYear,
    required int toMonth,
  }) async {
    final fromKey = fromYear * 100 + fromMonth;
    final toKey = toYear * 100 + toMonth;
    final rows = await _client
        .from('statutory_payments_paid_v')
        .select() as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .map(StatutoryPaymentSummary.fromRow)
        .where((p) {
          final key = p.periodYear * 100 + p.periodMonth;
          return key >= fromKey && key <= toKey;
        })
        .toList();
  }

  /// All payment ledger rows (including voided ones) for one
  /// (brand × period × agency). Used by the View Payments dialog so HR
  /// can see the full audit trail and act on individual entries.
  Future<List<StatutoryPayment>> listPayments({
    required String hiringEntityId,
    required int periodYear,
    required int periodMonth,
    required StatutoryAgency agency,
  }) async {
    final rows = await _client
        .from('statutory_payments')
        .select()
        .eq('hiring_entity_id', hiringEntityId)
        .eq('period_year', periodYear)
        .eq('period_month', periodMonth)
        .eq('agency', agency.dbValue)
        .order('paid_on', ascending: false)
        .order('created_at', ascending: false) as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .map(StatutoryPayment.fromRow)
        .toList();
  }

  /// Per-employee breakdown for one (brand × period × agency). Source of
  /// truth for both the on-screen drawer and the XLSX export — they render
  /// the same shape so they can never drift.
  Future<List<StatutoryPayableBreakdownRow>> listBreakdown({
    required String hiringEntityId,
    required int periodYear,
    required int periodMonth,
    required StatutoryAgency agency,
  }) async {
    final rows = await _client
        .from('statutory_payable_breakdown_v')
        .select()
        .eq('hiring_entity_id', hiringEntityId)
        .eq('period_year', periodYear)
        .eq('period_month', periodMonth)
        .eq('agency', agency.dbValue) as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .map(StatutoryPayableBreakdownRow.fromRow)
        .toList();
  }

  /// Fetch the breakdown for an entire (brand × period) — every agency at
  /// once. The XLSX exporter prefers a single round-trip over five.
  Future<List<StatutoryPayableBreakdownRow>> listBreakdownForBrandPeriod({
    required String hiringEntityId,
    required int periodYear,
    required int periodMonth,
  }) async {
    final rows = await _client
        .from('statutory_payable_breakdown_v')
        .select()
        .eq('hiring_entity_id', hiringEntityId)
        .eq('period_year', periodYear)
        .eq('period_month', periodMonth) as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .map(StatutoryPayableBreakdownRow.fromRow)
        .toList();
  }

  /// Count of active employees with NULL hiring_entity_id (for the
  /// "Unassigned" warning chip + deep link).
  Future<int> unassignedEmployeeCount(String companyId) async {
    final rows = await _client
        .from('employees')
        .select('id')
        .eq('company_id', companyId)
        .isFilter('hiring_entity_id', null)
        .isFilter('deleted_at', null);
    return (rows as List<dynamic>).length;
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Append a new payment row. Returns the inserted row so callers can show
  /// it in a confirmation toast / log it.
  Future<StatutoryPayment> insertPayment({
    required String hiringEntityId,
    required int periodYear,
    required int periodMonth,
    required StatutoryAgency agency,
    required DateTime paidOn,
    String? referenceNo,
    required Decimal amountPaid,
    String? paidById,
    String? notes,
  }) async {
    final row = await _client
        .from('statutory_payments')
        .insert({
          'hiring_entity_id': hiringEntityId,
          'period_year': periodYear,
          'period_month': periodMonth,
          'agency': agency.dbValue,
          'paid_on': paidOn.toIso8601String().substring(0, 10),
          'reference_no': referenceNo,
          'amount_paid': amountPaid.toString(),
          'paid_by_id': paidById,
          'notes': notes,
        })
        .select()
        .single();
    return StatutoryPayment.fromRow(row);
  }

  /// Edit a payment by inserting a corrected new row and soft-voiding the
  /// prior one with the supplied reason. Returns the new payment.
  ///
  /// The two writes happen sequentially without a server-side transaction
  /// (Supabase PostgREST doesn't expose multi-statement transactions to
  /// the client). If the second write fails, the first remains and the
  /// new + old payments coexist — surfaceable as a "Partial" or
  /// "Overpaid" state until manually cleaned up. Acceptable for v1; a
  /// follow-up RPC could wrap both in a single Postgres function.
  Future<StatutoryPayment> updatePayment({
    required String existingPaymentId,
    required String hiringEntityId,
    required int periodYear,
    required int periodMonth,
    required StatutoryAgency agency,
    required DateTime paidOn,
    String? referenceNo,
    required Decimal amountPaid,
    String? paidById,
    String? notes,
    required String voidReason,
    String? voidedById,
  }) async {
    final inserted = await insertPayment(
      hiringEntityId: hiringEntityId,
      periodYear: periodYear,
      periodMonth: periodMonth,
      agency: agency,
      paidOn: paidOn,
      referenceNo: referenceNo,
      amountPaid: amountPaid,
      paidById: paidById,
      notes: notes,
    );
    await voidPayment(
      paymentId: existingPaymentId,
      voidReason: voidReason,
      voidedById: voidedById,
    );
    return inserted;
  }

  /// Soft-void a payment with a required reason. The view filters voided
  /// rows out automatically; the View Payments dialog still shows them so
  /// HR can audit who voided what and why.
  Future<void> voidPayment({
    required String paymentId,
    required String voidReason,
    String? voidedById,
  }) async {
    await _client.from('statutory_payments').update({
      'voided_at': DateTime.now().toUtc().toIso8601String(),
      'voided_by_id': voidedById,
      'void_reason': voidReason,
    }).eq('id', paymentId);
  }
}

final statutoryPayablesRepositoryProvider =
    Provider<StatutoryPayablesRepository>(
        (ref) => StatutoryPayablesRepository(Supabase.instance.client));
