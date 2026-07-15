import 'package:supabase_flutter/supabase_flutter.dart';

/// Hard-deletes payroll adjuncts (penalties / cash advances / reimbursements)
/// via the `delete_*` RPCs (migration 20260715000002). Each RPC refuses when the
/// record has touched payroll and raises a coded exception; we translate those
/// into a user-facing [AdjunctDeleteException.message].
class AdjunctsRepository {
  AdjunctsRepository(this._client);

  final SupabaseClient _client;

  Future<void> deletePenalty(String id) =>
      _delete('delete_penalty', id, 'penalty');

  Future<void> deleteCashAdvance(String id) =>
      _delete('delete_cash_advance', id, 'cash advance');

  Future<void> deleteReimbursement(String id) =>
      _delete('delete_reimbursement', id, 'reimbursement');

  Future<void> _delete(String fn, String id, String noun) async {
    try {
      await _client.rpc(fn, params: {'p_id': id});
    } on PostgrestException catch (e) {
      throw AdjunctDeleteException(_friendly(e.message, noun));
    }
  }

  String _friendly(String raw, String noun) {
    if (raw.contains('RELEASED_PAYROLL')) {
      return "Can't delete — this $noun is already deducted/paid on a released "
          'payslip.';
    }
    if (raw.contains('ON_PAYROLL_RUN')) {
      return "Can't delete — this $noun is on an unreleased payroll run. "
          'Discard or recompute that run first.';
    }
    // NOT_FOUND / DELETE_FORBIDDEN (RLS) / anything else.
    return "Couldn't delete this $noun.";
  }
}

/// Thrown by [AdjunctsRepository] with a message safe to show the user.
class AdjunctDeleteException implements Exception {
  AdjunctDeleteException(this.message);

  final String message;

  @override
  String toString() => message;
}
