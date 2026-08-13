import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/leave_type.dart';
import '../../features/auth/profile_provider.dart';

class LeaveTypeRepository {
  final SupabaseClient _client;
  LeaveTypeRepository(this._client);

  Future<List<LeaveType>> list(String companyId) async {
    final rows = await _client
        .from('leave_types')
        .select(
          'id, company_id, code, name, description, is_paid, is_active, '
          'lark_leave_type_id',
        )
        .eq('company_id', companyId)
        .order('name');
    return rows.cast<Map<String, dynamic>>().map(LeaveType.fromRow).toList();
  }

  /// Single-column write, deliberately.
  ///
  /// Routing this through a whole-row upsert would mean reconstructing the
  /// model from a screen that only edits two switches, and any field the screen
  /// does not know about would be written back as its constructor default. That
  /// exact shape has cost this repo real data twice. Touch the one column the
  /// caller actually changed.
  Future<void> setPaid(String id, bool isPaid) async {
    await _client.from('leave_types').update({'is_paid': isPaid}).eq('id', id);
  }

  Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('leave_types')
        .update({'is_active': isActive})
        .eq('id', id);
  }
}

final leaveTypeRepositoryProvider = Provider<LeaveTypeRepository>(
  (ref) => LeaveTypeRepository(Supabase.instance.client),
);

final leaveTypeListProvider = FutureProvider<List<LeaveType>>((ref) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null) return const [];
  return ref.watch(leaveTypeRepositoryProvider).list(profile.companyId);
});
