import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/shift_template.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../auth/profile_provider.dart';

/// Applies a common patch to multiple attendance rows. Each section has an
/// "Apply this change" checkbox that gates whether it gets written. Clock
/// in/out are intentionally excluded — those are per-day values.
/// Returns true when at least one row was successfully updated.
Future<bool?> showAttendanceBatchEditDialog({
  required BuildContext context,
  required WidgetRef ref,
  required List<String> recordIds,
  required Map<String, DateTime> datesByRecordId,
  required List<ShiftTemplate> shifts,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) =>
        _BatchDialog(recordIds: recordIds, datesByRecordId: datesByRecordId, shifts: shifts),
  );
}

String _fmtTod(TimeOfDay t) {
  final h = t.hour;
  final m = t.minute.toString().padLeft(2, '0');
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return '${h12.toString().padLeft(2, '0')}:$m $period';
}

const _reasonCodes = <String, String>{
  'CORRECTION': 'Correction',
  'MISSED_PUNCH': 'Missed punch',
  'SCHEDULE_CHANGE': 'Schedule change',
  'APPROVE_OVERTIME': 'Approve overtime',
  'SYSTEM_ERROR': 'System error',
  'OTHER': 'Other',
};

class _BatchDialog extends ConsumerStatefulWidget {
  final List<String> recordIds;
  final Map<String, DateTime> datesByRecordId;
  final List<ShiftTemplate> shifts;
  const _BatchDialog({
    required this.recordIds,
    required this.datesByRecordId,
    required this.shifts,
  });

  @override
  ConsumerState<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends ConsumerState<_BatchDialog> {
  bool _applyShift = false;
  String? _shiftId;
  bool _applyBreak = false;
  final _breakCtrl = TextEditingController();
  bool _applyEarlyIn = false;
  bool _earlyInApproved = false;
  bool _applyLateOut = false;
  bool _lateOutApproved = false;
  bool _applyRate = false;
  final _rateCtrl = TextEditingController();
  // Clock-time overwrite — when enabled, clock_in / clock_out get written to
  // every selected row. When left off, each row keeps its own clock times.
  bool _applyClockTimes = false;
  TimeOfDay? _clockIn;
  TimeOfDay? _clockOut;
  String? _reasonCode;
  bool _saving = false;
  String? _error;
  int _successCount = 0;

  bool get _hasAnyChange =>
      _applyShift ||
      _applyBreak ||
      _applyEarlyIn ||
      _applyLateOut ||
      _applyRate ||
      _applyClockTimes;

  @override
  void dispose() {
    _breakCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  /// Shift whose start/end times seed the time-picker defaults. Prefers the
  /// shift the user just picked in the "Apply this shift" section (if any),
  /// otherwise falls back to the first shift in the list. Returning null
  /// just means the picker will use the 9 AM / 6 PM literals.
  ShiftTemplate? get _defaultShift {
    if (_applyShift && _shiftId != null) {
      for (final s in widget.shifts) {
        if (s.id == _shiftId) return s;
      }
    }
    return widget.shifts.isEmpty ? null : widget.shifts.first;
  }

  /// Parse a shift `HH:MM[:SS]` string to TimeOfDay with a fallback.
  TimeOfDay _shiftTod(String? hhmmss, {required TimeOfDay fallback}) {
    if (hhmmss == null || hhmmss.isEmpty) return fallback;
    final parts = hhmmss.split(':');
    final h = int.tryParse(parts[0]);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (h == null) return fallback;
    return TimeOfDay(hour: h, minute: m ?? 0);
  }

  Future<void> _save() async {
    if (_reasonCode == null || !_hasAnyChange) return;
    setState(() {
      _saving = true;
      _error = null;
      _successCount = 0;
    });
    final profile = ref.read(userProfileProvider).asData?.value;
    final repo = ref.read(attendanceRepositoryProvider);

    // Fields that are identical for every selected row
    final basePatch = <String, dynamic>{
      'override_reason_code': _reasonCode,
    };
    if (_applyShift) basePatch['shift_template_id'] = _shiftId;
    if (_applyBreak) {
      basePatch['break_minutes_applied'] = int.tryParse(_breakCtrl.text.trim());
    }
    if (_applyEarlyIn) basePatch['early_in_approved'] = _earlyInApproved;
    if (_applyLateOut) basePatch['late_out_approved'] = _lateOutApproved;
    if (_applyRate) {
      basePatch['daily_rate_override'] =
          _rateCtrl.text.trim().isEmpty ? null : _rateCtrl.text.trim();
    }

    String? _combineDateTime(DateTime date, TimeOfDay? tod) {
      if (tod == null) return null;
      // Build the local wall-clock DateTime, then convert to UTC before
      // serializing. Without `.toUtc()` the ISO string has no timezone
      // suffix and Postgres treats it as UTC — a PH-local 18:00 then
      // renders back as 02:00 AM next day.
      final dt = DateTime(date.year, date.month, date.day, tod.hour, tod.minute);
      return dt.toUtc().toIso8601String();
    }

    final failures = <String>[];
    for (final id in widget.recordIds) {
      try {
        // Clock times are per-row: combine each row's own date with the
        // picked time. Write each column independently — an empty picker
        // means "don't touch this column", so setting Clock Out alone
        // doesn't wipe an existing Clock In.
        final rowPatch = Map<String, dynamic>.from(basePatch);
        if (_applyClockTimes) {
          final date = widget.datesByRecordId[id];
          if (date != null) {
            if (_clockIn != null) {
              rowPatch['actual_time_in'] = _combineDateTime(date, _clockIn);
            }
            if (_clockOut != null) {
              rowPatch['actual_time_out'] = _combineDateTime(date, _clockOut);
            }
          }
        }
        await repo.updateRecord(
          id: id,
          patch: rowPatch,
          overrideById: profile?.userId,
        );
        _successCount++;
      } catch (e) {
        failures.add('$id: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = failures.isEmpty ? null : '${failures.length} failed';
    });
    if (failures.isEmpty) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.recordIds.length;
    return AlertDialog(
      title: Text('Batch Edit — $n record${n == 1 ? '' : 's'}'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pick the fields to apply. Unchecked fields are left alone.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              // Shift
              // Clock times — per-row (the same time applied to each selected
              // row's own date). Only written when "Overwrite" is checked.
              _ApplySection(
                title: 'Replace existing clock in/out times',
                subtitle:
                    'When on, every selected row is overwritten with the times below '
                    '(paired with each row\'s own date). Uncheck to leave existing '
                    'clock times untouched.',
                applied: _applyClockTimes,
                onApplyChanged: (v) => setState(() => _applyClockTimes = v),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.login, size: 16),
                        label: Text(_clockIn == null
                            ? 'Clock In: —'
                            : 'Clock In: ${_fmtTod(_clockIn!)}'),
                        onPressed: !_applyClockTimes
                            ? null
                            : () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: _clockIn ??
                                      _shiftTod(
                                        _defaultShift?.startTime,
                                        fallback: const TimeOfDay(
                                            hour: 9, minute: 0),
                                      ),
                                );
                                if (t != null) setState(() => _clockIn = t);
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout, size: 16),
                        label: Text(_clockOut == null
                            ? 'Clock Out: —'
                            : 'Clock Out: ${_fmtTod(_clockOut!)}'),
                        onPressed: !_applyClockTimes
                            ? null
                            : () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: _clockOut ??
                                      _shiftTod(
                                        _defaultShift?.endTime,
                                        fallback: const TimeOfDay(
                                            hour: 18, minute: 0),
                                      ),
                                );
                                if (t != null) setState(() => _clockOut = t);
                              },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                    'Applied to every selected row using that row\'s own date. '
                    'Leave either field empty (—) to clear that clock time.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ]),
              ),
              _ApplySection(
                title: 'Shift Schedule',
                applied: _applyShift,
                onApplyChanged: (v) => setState(() => _applyShift = v),
                child: DropdownButtonFormField<String?>(
                  initialValue: _shiftId,
                  decoration: const InputDecoration(
                    labelText: 'Shift',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— Clear shift —'),
                    ),
                    ...widget.shifts.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(
                            '${s.name} (${s.startTime.substring(0, 5)}–${s.endTime.substring(0, 5)})'),
                      ),
                    ),
                  ],
                  onChanged:
                      _applyShift ? (v) => setState(() => _shiftId = v) : null,
                ),
              ),
              _ApplySection(
                title: 'Break Override (mins)',
                applied: _applyBreak,
                onApplyChanged: (v) => setState(() => _applyBreak = v),
                child: TextFormField(
                  controller: _breakCtrl,
                  enabled: _applyBreak,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '60',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              _ApplySection(
                title: 'Approve Early In OT',
                applied: _applyEarlyIn,
                onApplyChanged: (v) => setState(() => _applyEarlyIn = v),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(_earlyInApproved ? 'Approved' : 'Not approved'),
                  value: _earlyInApproved,
                  onChanged: _applyEarlyIn
                      ? (v) => setState(() => _earlyInApproved = v)
                      : null,
                ),
              ),
              _ApplySection(
                title: 'Approve Late Out OT',
                applied: _applyLateOut,
                onApplyChanged: (v) => setState(() => _applyLateOut = v),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(_lateOutApproved ? 'Approved' : 'Not approved'),
                  value: _lateOutApproved,
                  onChanged: _applyLateOut
                      ? (v) => setState(() => _lateOutApproved = v)
                      : null,
                ),
              ),
              _ApplySection(
                title: 'Daily Rate Override',
                applied: _applyRate,
                onApplyChanged: (v) => setState(() => _applyRate = v),
                child: TextFormField(
                  controller: _rateCtrl,
                  enabled: _applyRate,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: 'PHP (leave blank to clear)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: _reasonCode == null ? 0.4 : 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _reasonCode == null
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).dividerColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Reason for change',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        Text(
                          '*',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Required for audit trail. Every batch edit is recorded '
                      'with this reason so payroll can trace why records changed.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text('$_error — $_successCount succeeded',
                    style: const TextStyle(color: Colors.red)),
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
          onPressed: (_saving || _reasonCode == null || !_hasAnyChange)
              ? null
              : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Apply to $n'),
        ),
      ],
    );
  }
}

class _ApplySection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool applied;
  final ValueChanged<bool> onApplyChanged;
  final Widget child;
  const _ApplySection({
    required this.title,
    this.subtitle,
    required this.applied,
    required this.onApplyChanged,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
        color: applied
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: applied,
                onChanged: (v) => onApplyChanged(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
