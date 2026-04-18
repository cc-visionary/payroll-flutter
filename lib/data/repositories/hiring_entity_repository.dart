import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hiring_entity.dart';
import '../../features/auth/profile_provider.dart';

class HiringEntityRepository {
  final SupabaseClient _client;
  HiringEntityRepository(this._client);

  Future<List<HiringEntity>> list(String companyId) async {
    final rows = await _client
        .from('hiring_entities')
        .select()
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    return rows
        .cast<Map<String, dynamic>>()
        .map(HiringEntity.fromRow)
        .toList();
  }

  Future<Map<String, int>> employeeCounts(String companyId) async {
    final rows = await _client
        .from('employees')
        .select('hiring_entity_id')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null);
    final out = <String, int>{};
    for (final r in rows.cast<Map<String, dynamic>>()) {
      final id = r['hiring_entity_id'] as String?;
      if (id == null) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  Future<void> upsert({
    String? id,
    required String companyId,
    required String code,
    required String name,
    String? tradeName,
    String? tin,
    String? rdoCode,
    String? sssEmployerId,
    String? philhealthEmployerId,
    String? pagibigEmployerId,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? province,
    String? zipCode,
    String country = 'PH',
    String? phoneNumber,
    String? email,
    bool isActive = true,
  }) async {
    final payload = {
      'company_id': companyId,
      'code': code,
      'name': name,
      'trade_name': tradeName,
      'tin': tin,
      'rdo_code': rdoCode,
      'sss_employer_id': sssEmployerId,
      'philhealth_employer_id': philhealthEmployerId,
      'pagibig_employer_id': pagibigEmployerId,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'city': city,
      'province': province,
      'zip_code': zipCode,
      'country': country,
      'phone_number': phoneNumber,
      'email': email,
      'is_active': isActive,
    };
    if (id == null) {
      await _client.from('hiring_entities').insert(payload);
    } else {
      await _client.from('hiring_entities').update(payload).eq('id', id);
    }
  }

  Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('hiring_entities')
        .update({'is_active': isActive}).eq('id', id);
  }
}

final hiringEntityRepositoryProvider = Provider<HiringEntityRepository>(
    (ref) => HiringEntityRepository(Supabase.instance.client));

final hiringEntityListProvider =
    FutureProvider<List<HiringEntity>>((ref) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null) return const [];
  return ref.watch(hiringEntityRepositoryProvider).list(profile.companyId);
});

final hiringEntityEmployeeCountsProvider =
    FutureProvider<Map<String, int>>((ref) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null) return const {};
  return ref
      .watch(hiringEntityRepositoryProvider)
      .employeeCounts(profile.companyId);
});
