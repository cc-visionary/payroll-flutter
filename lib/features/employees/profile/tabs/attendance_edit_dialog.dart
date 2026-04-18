import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/attendance_day.dart';
import '../../../../data/models/shift_template.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../auth/profile_provider.dart';

/// Single-row attendance edit dialog. Opens for either an existing record or
/// a "No Data" day (in which case a new MANUAL record is inserted on save).
/// Returns true when changes were saved.
Future<bool?> showAttendanceEditDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String employeeId,
  required DateTime date,
  AttendanceDay? record,
  ShiftTemplate? currentShift,
  required List<ShiftTemplate> shifts,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _EditDialog(
      employeeId: employeeId,
      date: date,
      record: record,
      currentShift: currentShift,
      shifts: shifts,
    ),
  );
}

const _reasonCodes = <String, String>{
  'CORRECTION': 'Correction',
  'MISSED_PUNCH': 'Missed punch',
  'SCHEDULE_CHANGE': 'Schedule change',
  'APPROVE_OVERTIME': 'Approve overtime',
  'SYSTEM_ERROR': 'System error',
  'OTHER': 'Other',
};

class _EditDialog extends ConsumerStatefulWidget {
  final String employeeId;
  final DateTime date;
  final AttendanceDay? record;
  final ShiftTemplate? currentShift;
  final List<ShiftTemplate> shifts;
  const _EditDialog({
    required this.employeeId,
    required this.date,
    required this.record,
    required this.currentShift,
    required this.shifts,
  });

  @override
  ConsumerState<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends ConsumerState<_EditDialog> {
  TimeOfDay? _clockIn;
  TimeOfDay? _clockOut;
  String? _shiftId; // override selection; null = keep current
  bool _useBreakDefault = true;
  final _breakCtrl = TextEditingController();
  bool _earlyInApproved = false;
  bool _lateOutApproved = false;
  bool _rateOverrideOn = false;
  final _rateCtrl = TextEditingController();
  String? _reasonCode;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _clockIn = r?.actualTimeIn == null
        ? null
        : TimeOfDay.fromDateTime(r!.actualTimeIn!.toLocal());
    _clockOut = r?.actualTimeOut == null
        ? null
        : TimeOfDay.fromDateTime(r!.actualTimeOut!.toLocal());
    _earlyInApproved = r?.earlyInApproved ?? false;
    _lateOutApproved = r?.lateOutApproved ?? false;
    _rateOverrideOn = r?.dailyRateOverride != null;
    _rateCtrl.text = r?.dailyRateOverride?.toString() ?? '';
    if (r?.breakMinutesApplied != null) {
      _useBreakDefault = false;
      _breakCtrl.text = r!.breakMinutesApplied.toString();
    }
  }

  @override
  void dispose() {
    _breakCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(
    TimeOfDay? current,
    ValueChanged<TimeOfDay> onSet, {
    required TimeOfDay fallback,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? fallback,
    );
    if (picked != null) setState(() => onSet(picked));
  }

  ShiftTemplate? get _effectiveShift {
    if (_shiftId == null) return widget.currentShift;
    return widget.shifts.firstWhere(
      (s) => s.id == _shiftId,
      orElse: () => widget.currentShift ?? widget.shifts.first,
    );
  }

  /// Parse a shift `HH:MM` / `HH:MM:SS` string to TimeOfDay. Falls back to
  /// 9 AM / 6 PM defaults when the shift is missing or unparseable.
  TimeOfDay _shiftTod(String? hhmmss, {required TimeOfDay fallback}) {
    if (hhmmss == null || hhmmss.isEmpty) return fallback;
    final parts = hhmmss.split(':');
    final h = int.tryParse(parts[0]);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (h == null) return fallback;
    return TimeOfDay(hour: h, minute: m ?? 0);
  }

  DateTime? _combine(TimeOfDay? t) {
    if (t == null) return null;
    final d = widget.date;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    if (_reasonCode == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = ref.read(userProfileProvider).asData?.value;
      final patch = <String, dynamic>{
        'actual_time_in': _combine(_clockIn)?.toUtc().toIso8601String(),
        'actual_time_out': _combine(_clockOut)?.toUtc().toIso8601String(),
        'early_in_approved': _earlyInApproved,
        'late_out_approved': _lateOutApproved,
        'override_reason_code': _reasonCode,
      };
      if (_shiftId != null) patch['shift_template_id'] = _shiftId;
      if (!_useBreakDefault) {
        patch['break_minutes_applied'] = int.tryParse(_breakCtrl.text.trim());
      }
      if (_rateOverrideOn) {
        patch['daily_rate_override'] = _rateCtrl.text.trim().isEmpty
            ? null
            : _rateCtrl.text.trim();
      } else {
        patch['daily_rate_override'] = null;
      }

      final repo = ref.read(attendanceRepositoryProvider);
      final r = widget.record;
      if (r == null) {
        // New record — must provide day_type + status.
        final wd = widget.date.weekday;
        final dayType = (wd == DateTime.saturday || wd == DateTime.sunday)
            ? 'REST_DAY'
            : 'WORKDAY';
        final status = _clockIn != null || _clockOut != null
            ? (_clockIn != null && _clockOut != null ? 'PRESENT' : 'HALF_DAY')
            : 'ABSENT';
        patch['day_type'] = dayType;
        patch['attendance_status'] = status;
        await repo.upsertByDate(
          employeeId: widget.employeeId,
          date: widget.date,
          patch: patch,
          overrideById: profile?.userId,
        );
      } else {
        // Recompute status if clock times changed.
        final hasIn = _clockIn != null;
        final hasOut = _clockOut != null;
        if (hasIn && hasOut) {
          patch['attendance_status'] = 'PRESENT';
        } else if (hasIn || hasOut) {
          patch['attendance_status'] = 'HALF_DAY';
        }
        await repo.updateRecord(
          id: r.id,
          patch: patch,
          overrideById: profile?.userId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final dateLabel =
        '${_monthNames[widget.date.month - 1].substring(0, 3)} ${widget.date.day}';
    final currentShift = widget.currentShift;
    return AlertDialog(
      title: Text('Edit Attendance — $dateLabel'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header meta
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        const TextSpan(
                            text: 'Status: ',
                            style: TextStyle(color: Colors.grey)),
                        TextSpan(
                            text: r?.attendanceStatus ?? 'NO DATA',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ])),
                    ),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        const TextSpan(
                            text: 'Day Type: ',
                            style: TextStyle(color: Colors.grey)),
                        TextSpan(
                            text: r?.dayType ?? _defaultDayType(widget.date),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ])),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _Section('Actual Time'),
              Row(children: [
                Expanded(
                  child: _TimeField(
                    label: 'Clock In',
                    value: _clockIn,
                    onPick: () => _pickTime(
                      _clockIn,
                      (t) => _clockIn = t,
                      fallback: _shiftTod(
                        _effectiveShift?.startTime,
                        fallback: const TimeOfDay(hour: 9, minute: 0),
                      ),
                    ),
                    onClear: () => setState(() => _clockIn = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeField(
                    label: 'Clock Out',
                    value: _clockOut,
                    onPick: () => _pickTime(
                      _clockOut,
                      (t) => _clockOut = t,
                      fallback: _shiftTod(
                        _effectiveShift?.endTime,
                        fallback: const TimeOfDay(hour: 18, minute: 0),
                      ),
                    ),
                    onClear: () => setState(() => _clockOut = null),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              _Section('Shift Schedule Override',
                  hint: '(Overwrite imported schedule if incorrect)'),
              if (currentShift != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Current: ${currentShift.startTime.substring(0, 5)} - ${currentShift.endTime.substring(0, 5)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _shiftId,
                    decoration: const InputDecoration(
                      labelText: 'Select Shift',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— Keep current shift —'),
                      ),
                      ...widget.shifts.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(
                              '${s.name} (${s.startTime.substring(0, 5)}–${s.endTime.substring(0, 5)})'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _shiftId = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Break Override (mins)',
                          style: TextStyle(fontSize: 12)),
                      Row(children: [
                        Checkbox(
                          value: _useBreakDefault,
                          onChanged: (v) =>
                              setState(() => _useBreakDefault = v ?? true),
                        ),
                        Expanded(
                          child: Text(
                            'Use shift default (${_effectiveShift?.breakMinutes ?? 60} mins)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ]),
                      TextFormField(
                        controller: _breakCtrl,
                        enabled: !_useBreakDefault,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: '60',
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              const _Section('Overtime Approval'),
              Row(children: [
                Expanded(
                  child: _CheckTile(
                    title: 'Approve Early In OT',
                    subtitle: 'Clock in before shift start counts as OT',
                    value: _earlyInApproved,
                    onChanged: (v) => setState(() => _earlyInApproved = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CheckTile(
                    title: 'Approve Late Out OT',
                    subtitle: 'Clock out after shift end counts as OT',
                    value: _lateOutApproved,
                    onChanged: (v) => setState(() => _lateOutApproved = v),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              const _Section('Daily Rate Override',
                  hint: '(e.g., training rate for this day)'),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Override daily rate for this day'),
                value: _rateOverrideOn,
                onChanged: (v) =>
                    setState(() => _rateOverrideOn = v ?? false),
              ),
              if (_rateOverrideOn)
                TextFormField(
                  controller: _rateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rate (PHP)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              const SizedBox(height: 16),
              const _Section('Reason for Change *'),
              DropdownButtonFormField<String>(
                initialValue: _reasonCode,
                decoration: const InputDecoration(
                  hintText: 'Select a reason…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final e in _reasonCodes.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _reasonCode = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _reasonCode == null) ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save Changes'),
        ),
      ],
    );
  }
}

String _defaultDayType(DateTime d) {
  if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
    return 'REST_DAY';
  }
  return 'WORKDAY';
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class _Section extends StatelessWidget {
  final String text;
  final String? hint;
  const _Section(this.text, {this.hint});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(text,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hint!,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _TimeField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });
  @override
  Widget build(BuildContext context) {
    final fmt = value == null
        ? '—'
        : '${value!.hourOfPeriod.toString().padLeft(2, '0')}:${value!.minute.toString().padLeft(2, '0')} ${value!.period == DayPeriod.am ? 'AM' : 'PM'}';
    return InputDecorator(
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder(), isDense: true),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onPick,
              child: Text(fmt,
                  style: TextStyle(
                    color: value == null ? Theme.of(context).hintColor : null,
                  )),
            ),
          ),
          if (value != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.clear, size: 16),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CheckTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
