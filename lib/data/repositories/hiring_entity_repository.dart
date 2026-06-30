import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hiring_entity.dart';
import '../../features/auth/profile_provider.dart';

/// Decode a base64 logo string to bytes; returns null on null/empty/invalid input.
Uint8List? decodeLogoBytes(String? base64Str) {
  if (base64Str == null || base64Str.isEmpty) return null;
  try {
    return base64.decode(base64Str);
  } catch (_) {
    return null;
  }
}

class HiringEntityRepository {
  final SupabaseClient _client;
  HiringEntityRepository(this._client);

  Future<List<HiringEntity>> list(String companyId) async {
    final rows = await _client
        .from('hiring_entities')
        .select(
          'id, company_id, code, name, trade_name, tin, rdo_code, '
          'sss_employer_id, philhealth_employer_id, pagibig_employer_id, '
          'address_line1, address_line2, city, province, zip_code, country, '
          'phone_number, email, legal_signatory_name, legal_signatory_role, '
          'hr_manager_name, is_active',
        )
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .order('name');
    return rows
        .cast<Map<String, dynamic>>()
        .map(HiringEntity.fromRow)
        .toList();
  }

  /// Fetch ONLY the logo columns for one entity. Kept separate from [list] so the
  /// (potentially large) base64 never rides along on the constantly-loaded picker list.
  Future<({String base64, String mime})?> logoFor(String entityId) async {
    final row = await _client
        .from('hiring_entities')
        .select('logo_base64, logo_mime')
        .eq('id', entityId)
        .maybeSingle();
    final b64 = row?['logo_base64'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    return (base64: b64, mime: (row?['logo_mime'] as String?) ?? 'image/png');
  }

  /// Fetch one entity by id, INCLUDING the logo columns (unlike [list], which
  /// omits them to keep the picker light). Used by render paths that need the
  /// uploaded logo. Returns null when not found / soft-deleted.
  Future<HiringEntity?> byId(String id) async {
    final row = await _client
        .from('hiring_entities')
        .select()
        .eq('id', id)
        .isFilter('deleted_at', null)
        .maybeSingle();
    return row == null ? null : HiringEntity.fromRow(row);
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
    String? legalSignatoryName,
    String? legalSignatoryRole,
    String? hrManagerName,
    String? logoBase64,
    String? logoMime,
    bool updateLogo = false,
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
      'legal_signatory_name': legalSignatoryName,
      'legal_signatory_role': legalSignatoryRole,
      'hr_manager_name': hrManagerName,
      'is_active': isActive,
    };
    if (updateLogo) {
      payload['logo_base64'] = logoBase64;
      payload['logo_mime'] = logoMime;
    }
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
