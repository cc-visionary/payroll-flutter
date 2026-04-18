import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/profile_provider.dart';

/// Two independent feature flags that together describe how attendance and
/// Lark integrations are wired up for a given company.
///
///   - [manualCsvEnabled] controls whether the "Import CSV" button appears on
///     the Attendance screen. When on, admins can upload CSVs for any day.
///   - [larkEnabled] controls whether the Lark sync UI is visible (Connection
///     Status, Employee Lark User IDs, Sync History, per-entity sync cards).
///     When off, the Lark settings tab only shows the toggle.
///
/// Both can be on simultaneously — e.g. Lark is the primary source but admins
/// still want the CSV escape hatch for backfills and exception days.
class AttendanceSourceFlags {
  final bool manualCsvEnabled;
  final bool larkEnabled;
  const AttendanceSourceFlags({
    required this.manualCsvEnabled,
    required this.larkEnabled,
  });

  AttendanceSourceFlags copyWith({bool? manualCsvEnabled, bool? larkEnabled}) =>
      AttendanceSourceFlags(
        manualCsvEnabled: manualCsvEnabled ?? this.manualCsvEnabled,
        larkEnabled: larkEnabled ?? this.larkEnabled,
      );
}

class CompanySettingsRepository {
  final SupabaseClient _client;
  CompanySettingsRepository(this._client);

  Future<AttendanceSourceFlags> attendanceSourceFlags(String companyId) async {
    final row = await _client
        .from('company_settings')
        .select('lark_enabled, manual_csv_enabled')
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) {
      // Backfill defensively if no settings row exists yet.
      await _client
          .from('company_settings')
          .upsert({'company_id': companyId}, onConflict: 'company_id');
      return const AttendanceSourceFlags(
          manualCsvEnabled: true, larkEnabled: true);
    }
    return AttendanceSourceFlags(
      manualCsvEnabled: (row['manual_csv_enabled'] as bool?) ?? true,
      larkEnabled: (row['lark_enabled'] as bool?) ?? true,
    );
  }

  Future<void> setAttendanceSourceFlags(
      String companyId, AttendanceSourceFlags flags) async {
    await _client.from('company_settings').upsert(
      {
        'company_id': companyId,
        'manual_csv_enabled': flags.manualCsvEnabled,
        'lark_enabled': flags.larkEnabled,
      },
      onConflict: 'company_id',
    );
  }
}

final companySettingsRepositoryProvider =
    Provider<CompanySettingsRepository>((ref) {
  return CompanySettingsRepository(Supabase.instance.client);
});

final attendanceSourceFlagsProvider =
    FutureProvider<AttendanceSourceFlags>((ref) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null || profile.companyId.isEmpty) {
    return const AttendanceSourceFlags(
        manualCsvEnabled: true, larkEnabled: true);
  }
  return ref
      .watch(companySettingsRepositoryProvider)
      .attendanceSourceFlags(profile.companyId);
});
