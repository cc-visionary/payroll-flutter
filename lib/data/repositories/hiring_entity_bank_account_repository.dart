import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hiring_entity_bank_account.dart';

class HiringEntityBankAccountRepository {
  final SupabaseClient _client;
  HiringEntityBankAccountRepository(this._client);

  /// All company bank accounts for every hiring entity in the user's
  /// company — Settings screen renders them grouped by entity client-side.
  Future<List<HiringEntityBankAccount>> listAll() async {
    final rows = await _client
        .from('hiring_entity_bank_accounts')
        .select()
        .isFilter('deleted_at', null)
        .order('hiring_entity_id')
        .order('is_primary', ascending: false)
        .order('bank_code');
    return rows
        .cast<Map<String, dynamic>>()
        .map(HiringEntityBankAccount.fromRow)
        .toList();
  }

  Future<List<HiringEntityBankAccount>> listByEntity(
      String hiringEntityId) async {
    final rows = await _client
        .from('hiring_entity_bank_accounts')
        .select()
        .eq('hiring_entity_id', hiringEntityId)
        .isFilter('deleted_at', null)
        .order('is_primary', ascending: false)
        .order('bank_code');
    return rows
        .cast<Map<String, dynamic>>()
        .map(HiringEntityBankAccount.fromRow)
        .toList();
  }

  Future<HiringEntityBankAccount> upsert({
    String? id,
    required String hiringEntityId,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountName,
    String? accountType,
    bool isPrimary = false,
    bool isActive = true,
  }) async {
    final payload = <String, dynamic>{
      if (id != null) 'id': id,
      'hiring_entity_id': hiringEntityId,
      'bank_code': bankCode,
      'bank_name': bankName,
      'account_number': accountNumber,
      'account_name': accountName,
      'account_type': accountType,
      'is_primary': isPrimary,
      'is_active': isActive,
    };
    Map<String, dynamic> row;
    if (id == null) {
      row = await _client
          .from('hiring_entity_bank_accounts')
          .insert(payload)
          .select()
          .single();
    } else {
      row = await _client
          .from('hiring_entity_bank_accounts')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
    }
    return HiringEntityBankAccount.fromRow(row);
  }

  /// Mark a single account primary for the entity; clear `is_primary` on
  /// its siblings. Two queries since PostgREST has no client transactions.
  Future<void> setPrimary({
    required String hiringEntityId,
    required String accountId,
  }) async {
    await _client
        .from('hiring_entity_bank_accounts')
        .update({'is_primary': false})
        .eq('hiring_entity_id', hiringEntityId)
        .neq('id', accountId);
    await _client
        .from('hiring_entity_bank_accounts')
        .update({'is_primary': true})
        .eq('id', accountId);
  }

  Future<void> delete(String id) async {
    await _client
        .from('hiring_entity_bank_accounts')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }
}

final hiringEntityBankAccountRepositoryProvider =
    Provider<HiringEntityBankAccountRepository>(
        (ref) => HiringEntityBankAccountRepository(Supabase.instance.client));

/// Company-wide (all hiring entities) bank accounts — Settings screen.
final companyBankAccountsProvider =
    FutureProvider<List<HiringEntityBankAccount>>((ref) {
  return ref.watch(hiringEntityBankAccountRepositoryProvider).listAll();
});

/// Bank accounts for a single hiring entity — employee form default-pay-source
/// dropdown, disbursement tab lookups, per-entity Settings sections.
final hiringEntityBankAccountsProvider =
    FutureProvider.family<List<HiringEntityBankAccount>, String>(
        (ref, hiringEntityId) {
  return ref
      .watch(hiringEntityBankAccountRepositoryProvider)
      .listByEntity(hiringEntityId);
});
