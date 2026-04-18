class HolidayCalendar {
  final String id;
  final String companyId;
  final int year;
  final String name;
  final bool isActive;
  final DateTime? lastSyncedAt;
  const HolidayCalendar({
    required this.id,
    required this.companyId,
    required this.year,
    required this.name,
    required this.isActive,
    this.lastSyncedAt,
  });
  factory HolidayCalendar.fromRow(Map<String, dynamic> r) => HolidayCalendar(
        id: r['id'] as String,
        companyId: r['company_id'] as String,
        year: r['year'] as int,
        name: r['name'] as String,
        isActive: r['is_active'] as bool? ?? true,
        lastSyncedAt: r['last_synced_at'] == null
            ? null
            : DateTime.parse(r['last_synced_at'] as String),
      );
}

class CalendarEvent {
  final String id;
  final String calendarId;
  final DateTime date;
  final String name;
  final String dayType; // REGULAR_HOLIDAY | SPECIAL_HOLIDAY | SPECIAL_WORKING | COMPANY_EVENT
  final String source; // LARK | MANUAL
  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.date,
    required this.name,
    required this.dayType,
    required this.source,
  });
  factory CalendarEvent.fromRow(Map<String, dynamic> r) => CalendarEvent(
        id: r['id'] as String,
        calendarId: r['calendar_id'] as String,
        date: DateTime.parse(r['date'] as String),
        name: r['name'] as String,
        dayType: r['day_type'] as String,
        source: r['source'] as String? ?? 'MANUAL',
      );
}
