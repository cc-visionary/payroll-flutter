import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/calendar_event.dart';
import '../../../data/repositories/holiday_repository.dart';
import '../../auth/profile_provider.dart';
import '../../lark/lark_repository.dart';
import '../../../widgets/syncing_dialog.dart';
import '../../../widgets/responsive_table.dart';
import '../../../app/status_colors.dart';

class HolidaysSettingsScreen extends ConsumerStatefulWidget {
  const HolidaysSettingsScreen({super.key});
  @override
  ConsumerState<HolidaysSettingsScreen> createState() => _State();
}

class _State extends ConsumerState<HolidaysSettingsScreen> {
  bool _syncing = false;
  String? _msg;

  Future<void> _sync() async {
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    final year = ref.read(selectedHolidayYearProvider);
    setState(() { _syncing = true; _msg = null; });
    try {
      await ref.read(holidayRepositoryProvider).ensureForYear(profile.companyId, year);
      final res = await runWithSyncingDialog(
        context,
        'Holidays',
        () => ref.read(larkRepositoryProvider).syncCalendar(profile.companyId, year),
      );
      setState(() => _msg = 'Synced: ${res.created} created, ${res.updated} updated, ${res.skipped} skipped');
      ref.invalidate(holidayCalendarProvider);
      ref.invalidate(holidayEventsProvider);
      ref.invalidate(syncHistoryProvider);
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _addOrEdit({CalendarEvent? existing}) async {
    final cal = await ref.read(holidayCalendarProvider.future);
    if (cal == null) return;
    await showDialog(
      context: context,
      builder: (_) => _HolidayForm(
        calendarId: cal.id,
        existing: existing,
        onSaved: () {
          ref.invalidate(holidayEventsProvider);
        },
      ),
    );
  }

  Future<void> _delete(CalendarEvent ev) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete holiday?'),
        content: Text('Remove ${ev.name} on ${ev.date.toIso8601String().substring(0, 10)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(holidayRepositoryProvider).delete(ev.id);
    ref.invalidate(holidayEventsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final year = ref.watch(selectedHolidayYearProvider);
    final cal = ref.watch(holidayCalendarProvider).asData?.value;
    final eventsAsync = ref.watch(holidayEventsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Holiday Calendar', style: Theme.of(context).textTheme.headlineSmall),
        ]),
        const SizedBox(height: 4),
        const Text('Manage holidays for payroll day-type resolution. Sync from Lark to import holidays from the HR Calendar, or add them manually.',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Row(children: [
          IconButton(onPressed: () => ref.read(selectedHolidayYearProvider.notifier).state = year - 1, icon: const Icon(Icons.chevron_left)),
          Text('$year', style: Theme.of(context).textTheme.titleLarge),
          IconButton(onPressed: () => ref.read(selectedHolidayYearProvider.notifier).state = year + 1, icon: const Icon(Icons.chevron_right)),
          const Spacer(),
          if (cal?.lastSyncedAt != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('Last synced: ${DateFormat('MMM d, h:mm a').format(cal!.lastSyncedAt!.toLocal())}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          OutlinedButton.icon(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: const Text('Sync from Lark'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add),
            label: const Text('Add Holiday'),
          ),
        ]),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!)),
        const SizedBox(height: 16),
        Expanded(child: eventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (events) => events.isEmpty
              ? const Center(child: Text('No holidays for this year. Click "Sync from Lark" or "Add Holiday".'))
              : SingleChildScrollView(
                  child: ResponsiveTable(
                    fullWidth: true,
                    child: DataTable(
                      columnSpacing: 24,
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Day')),
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Type')),
                        DataColumn(label: Text('Source')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: events.map((ev) => DataRow(cells: [
                        DataCell(Text(ev.date.toIso8601String().substring(0, 10))),
                        DataCell(Text(DateFormat('E').format(ev.date))),
                        DataCell(Text(ev.name)),
                        DataCell(_typeChip(ev.dayType)),
                        DataCell(Text(ev.source, style: const TextStyle(fontSize: 12))),
                        DataCell(ev.source == 'MANUAL'
                            ? Row(children: [
                                TextButton(onPressed: () => _addOrEdit(existing: ev), child: const Text('Edit')),
                                TextButton(onPressed: () => _delete(ev), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
                              ])
                            : const Text('—', style: TextStyle(color: Colors.grey))),
                      ])).toList(),
                    ),
                  ),
                ),
        )),
      ]),
    );
  }

  Widget _typeChip(String dt) {
    switch (dt) {
      case 'REGULAR_HOLIDAY':
        return const StatusChip(label: 'Regular', tone: StatusTone.holidayRegular);
      case 'SPECIAL_HOLIDAY':
        return const StatusChip(label: 'Special', tone: StatusTone.holidaySpecial);
      case 'SPECIAL_WORKING':
        return const StatusChip(label: 'Extra', tone: StatusTone.holidayWorking);
      default:
        return Chip(label: Text(dt), visualDensity: VisualDensity.compact);
    }
  }
}

class _HolidayForm extends ConsumerStatefulWidget {
  final String calendarId;
  final CalendarEvent? existing;
  final VoidCallback onSaved;
  const _HolidayForm({required this.calendarId, this.existing, required this.onSaved});
  @override
  ConsumerState<_HolidayForm> createState() => _FormState();
}

class _FormState extends ConsumerState<_HolidayForm> {
  final _name = TextEditingController();
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late String _type = widget.existing?.dayType ?? 'REGULAR_HOLIDAY';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.existing?.name ?? '';
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(holidayRepositoryProvider).upsertManual(
            id: widget.existing?.id,
            calendarId: widget.calendarId,
            date: _date,
            name: _name.text.trim(),
            dayType: _type,
          );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Holiday' : 'Edit Holiday'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final p = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (p != null) setState(() => _date = p);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
              child: Text(_date.toIso8601String().substring(0, 10)),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'REGULAR_HOLIDAY', child: Text('Regular Holiday')),
              DropdownMenuItem(value: 'SPECIAL_HOLIDAY', child: Text('Special Holiday')),
              DropdownMenuItem(value: 'SPECIAL_WORKING', child: Text('Extra / Working')),
            ],
            onChanged: (v) => setState(() => _type = v!),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}
