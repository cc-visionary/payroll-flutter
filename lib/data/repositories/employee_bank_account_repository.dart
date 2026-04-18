import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_bank_account.dart';

class EmployeeBankAccountRepository {
  final SupabaseClient _client;
  EmployeeBankAccountRepository(this._client);

  Future<List<EmployeeBankAccount>> listByEmployee(String employeeId) async {
    final rows = await _client
        .from('employee_bank_accounts')
        .select()
        .eq('employee_id', employeeId)
        .isFilter('deleted_at', null)
        .order('is_primary', ascending: false)
        .order('bank_code');
    return rows
        .cast<Map<String, dynamic>>()
        .map(EmployeeBankAccount.fromRow)
        .toList();
  }

  Future<EmployeeBankAccount> upsert({
    String? id,
    required String employeeId,
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountName,
    String? accountType,
    bool isPrimary = false,
  }) async {
    final payload = <String, dynamic>{
      if (id != null) 'id': id,
      'employee_id': employeeId,
      'bank_code': bankCode,
      'bank_name': bankName,
      'account_number': accountNumber,
      'account_name': accountName,
      'account_type': accountType,
      'is_primary': isPrimary,
    };
    Map<String, dynamic> row;
    if (id == null) {
      row = await _client
          .from('employee_bank_accounts')
          .insert(payload)
          .select()
          .single();
    } else {
      row = await _client
          .from('employee_bank_accounts')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
    }
    return EmployeeBankAccount.fromRow(row);
  }

  /// Mark a single account as primary and clear `is_primary` on the rest.
  /// Done in two queries since PostgREST doesn't expose transactions to the
  /// client — the window of inconsistency is a few ms at worst.
  Future<void> setPrimary({
    required String employeeId,
    required String accountId,
  }) async {
    await _client
        .from('employee_bank_accounts')
        .update({'is_primary': false})
        .eq('employee_id', employeeId)
        .neq('id', accountId);
    await _client
        .from('employee_bank_accounts')
        .update({'is_primary': true})
        .eq('id', accountId);
  }

  Future<void> delete(String id) async {
    await _client
        .from('employee_bank_accounts')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }
}

final employeeBankAccountRepositoryProvider =
    Provider<EmployeeBankAccountRepository>(
        (ref) => EmployeeBankAccountRepository(Supabase.instance.client));

final employeeBankAccountsProvider =
    FutureProvider.family<List<EmployeeBankAccount>, String>((ref, employeeId) {
  return ref
      .watch(employeeBankAccountRepositoryProvider)
      .listByEmployee(employeeId);
});
