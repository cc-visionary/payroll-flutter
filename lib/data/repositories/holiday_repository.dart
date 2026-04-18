import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/calendar_event.dart';
import '../../features/auth/profile_provider.dart';

class HolidayRepository {
  final SupabaseClient _client;
  HolidayRepository(this._client);

  Future<HolidayCalendar?> byYear(String companyId, int year) async {
    final row = await _client
        .from('holiday_calendars')
        .select()
        .eq('company_id', companyId)
        .eq('year', year)
        .maybeSingle();
    if (row == null) return null;
    return HolidayCalendar.fromRow(row);
  }

  Future<HolidayCalendar> ensureForYear(String companyId, int year) async {
    final existing = await byYear(companyId, year);
    if (existing != null) return existing;
    final row = await _client
        .from('holiday_calendars')
        .insert({'company_id': companyId, 'year': year, 'name': '$year Holidays'})
        .select()
        .single();
    return HolidayCalendar.fromRow(row);
  }

  Future<List<CalendarEvent>> events(String calendarId) async {
    final rows = await _client
        .from('calendar_events')
        .select()
        .eq('calendar_id', calendarId)
        .order('date');
    return rows.cast<Map<String, dynamic>>().map(CalendarEvent.fromRow).toList();
  }

  Future<void> upsertManual({
    String? id,
    required String calendarId,
    required DateTime date,
    required String name,
    required String dayType,
  }) async {
    final payload = {
      'calendar_id': calendarId,
      'date': date.toIso8601String().substring(0, 10),
      'name': name,
      'day_type': dayType,
      'source': 'MANUAL',
    };
    if (id == null) {
      await _client.from('calendar_events').insert(payload);
    } else {
      await _client.from('calendar_events').update(payload).eq('id', id);
    }
  }

  Future<void> delete(String id) async {
    await _client.from('calendar_events').delete().eq('id', id);
  }
}

final holidayRepositoryProvider = Provider<HolidayRepository>(
    (ref) => HolidayRepository(Supabase.instance.client));

final selectedHolidayYearProvider = StateProvider<int>((ref) => DateTime.now().year);

final holidayCalendarProvider = FutureProvider<HolidayCalendar?>((ref) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null) return null;
  final year = ref.watch(selectedHolidayYearProvider);
  return ref.watch(holidayRepositoryProvider).byYear(profile.companyId, year);
});

final holidayEventsProvider = FutureProvider<List<CalendarEvent>>((ref) async {
  final cal = await ref.watch(holidayCalendarProvider.future);
  if (cal == null) return const [];
  return ref.watch(holidayRepositoryProvider).events(cal.id);
});
