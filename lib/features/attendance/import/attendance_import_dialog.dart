import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/repositories/attendance_repository.dart';
import '../../auth/profile_provider.dart';

/// CSV import dialog for attendance records.
///
/// Expected CSV layout (first row = header):
///
///     employee_number, date, time_in, time_out
///     EMP001,          2026-04-01, 09:10, 18:20
///
/// - `date`: YYYY-MM-DD
/// - `time_in` / `time_out`: HH:MM (24h). Leave empty for absent days.
/// - Device local time is treated as the punch timezone; the client converts
///   to UTC before writing.
Future<void> showAttendanceImportDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _AttendanceImportDialog(),
  );
}

enum _DedupMode { overwrite, skip }

class _AttendanceImportDialog extends ConsumerStatefulWidget {
  const _AttendanceImportDialog();

  @override
  ConsumerState<_AttendanceImportDialog> createState() => _State();
}

class _State extends ConsumerState<_AttendanceImportDialog> {
  String? _fileName;
  Uint8List? _fileBytes;
  List<_ParsedRow> _rows = const [];
  List<String> _unknownEmployeeNumbers = const [];
  List<String> _parseErrors = const [];
  _DedupMode _dedup = _DedupMode.skip;
  bool _busy = false;
  String? _statusMsg;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _statusMsg = 'Could not read file bytes.');
      return;
    }
    setState(() {
      _fileName = file.name;
      _fileBytes = bytes;
      _rows = const [];
      _unknownEmployeeNumbers = const [];
      _parseErrors = const [];
      _statusMsg = null;
    });
    await _parseAndValidate();
  }

  Future<void> _parseAndValidate() async {
    final bytes = _fileBytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final table = Csv().decode(text);
      if (table.isEmpty) {
        setState(() {
          _parseErrors = const ['File is empty.'];
          _rows = const [];
        });
        return;
      }
      final header = table.first
          .map((c) => c.toString().trim().toLowerCase())
          .toList();
      final colEmp = header.indexOf('employee_number');
      final colDate = header.indexOf('date');
      final colIn = header.indexOf('time_in');
      final colOut = header.indexOf('time_out');
      if (colEmp < 0 || colDate < 0 || colIn < 0 || colOut < 0) {
        setState(() {
          _parseErrors = [
            'Header must include: employee_number, date, time_in, time_out. '
                'Got: ${header.join(", ")}',
          ];
          _rows = const [];
        });
        return;
      }

      // Resolve employee_number → employee_id (scoped to the active company).
      final profile = ref.read(userProfileProvider).asData?.value;
      if (profile == null) return;
      final empRows = await Supabase.instance.client
          .from('employees')
          .select('id, employee_number')
          .eq('company_id', profile.companyId)
          .isFilter('deleted_at', null);
      final empLookup = <String, String>{
        for (final r in empRows.cast<Map<String, dynamic>>())
          (r['employee_number'] as String).trim(): r['id'] as String,
      };

      final parsed = <_ParsedRow>[];
      final errors = <String>[];
      final unknownEmps = <String>{};
      for (var i = 1; i < table.length; i++) {
        final row = table[i];
        if (row.every((c) => c.toString().trim().isEmpty)) continue;
        final empNum = row[colEmp].toString().trim();
        final dateStr = row[colDate].toString().trim();
        final inStr = row[colIn].toString().trim();
        final outStr = row[colOut].toString().trim();
        if (empNum.isEmpty || dateStr.isEmpty) {
          errors.add('Row ${i + 1}: employee_number and date are required.');
          continue;
        }
        final empId = empLookup[empNum];
        if (empId == null) {
          unknownEmps.add(empNum);
          continue;
        }
        DateTime date;
        try {
          date = DateTime.parse(dateStr);
        } catch (_) {
          errors.add('Row ${i + 1}: invalid date "$dateStr" (expected YYYY-MM-DD).');
          continue;
        }
        final tIn = _toTimestamp(date, inStr);
        final tOut = _toTimestamp(date, outStr);
        if (inStr.isNotEmpty && tIn == null) {
          errors.add('Row ${i + 1}: invalid time_in "$inStr" (expected HH:MM).');
          continue;
        }
        if (outStr.isNotEmpty && tOut == null) {
          errors.add('Row ${i + 1}: invalid time_out "$outStr" (expected HH:MM).');
          continue;
        }
        parsed.add(_ParsedRow(
          employeeId: empId,
          employeeNumber: empNum,
          date: DateTime(date.year, date.month, date.day),
          timeIn: tIn,
          timeOut: tOut,
        ));
      }

      setState(() {
        _rows = parsed;
        _unknownEmployeeNumbers = unknownEmps.toList()..sort();
        _parseErrors = errors;
      });
    } catch (e) {
      setState(() => _statusMsg = 'Parse failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static DateTime? _toTimestamp(DateTime date, String hhmm) {
    if (hhmm.isEmpty) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  Future<void> _submit() async {
    if (_rows.isEmpty) return;
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    setState(() {
      _busy = true;
      _statusMsg = null;
    });
    final client = Supabase.instance.client;
    try {
      // 1) Record the import batch so uploads are auditable.
      final importRow = await client.from('attendance_imports').insert({
        'company_id': profile.companyId,
        'file_name': _fileName ?? 'manual.csv',
        'file_path': 'manual://${DateTime.now().millisecondsSinceEpoch}',
        'file_size': _fileBytes?.length,
        'status': 'PROCESSING',
        'total_rows': _rows.length,
        'uploaded_by_id': profile.userId,
        'started_at': DateTime.now().toIso8601String(),
      }).select('id').single();
      final importId = importRow['id'] as String;

      // 2) Build payloads (no FKs beyond employee_id — shift + day_type default).
      final payloads = _rows
          .map((r) => {
                'employee_id': r.employeeId,
                'attendance_date':
                    r.date.toIso8601String().substring(0, 10),
                'actual_time_in': r.timeIn?.toUtc().toIso8601String(),
                'actual_time_out': r.timeOut?.toUtc().toIso8601String(),
                'attendance_status':
                    r.timeIn != null ? 'PRESENT' : 'ABSENT',
                'day_type': 'WORKDAY',
                'source_type': 'MANUAL',
                'source_batch_id': importId,
                'entered_by_id': profile.userId,
              })
          .toList();

      int inserted = 0;
      int updated = 0;
      int skipped = 0;

      if (_dedup == _DedupMode.overwrite) {
        // Upsert merges into existing rows; can't distinguish insert vs update
        // in one round-trip, so count them separately via a pre-fetch.
        final existingKeys = await _fetchExistingKeys(payloads);
        inserted =
            payloads.where((p) => !existingKeys.contains(_keyOf(p))).length;
        updated = payloads.length - inserted;
        await client.from('attendance_day_records').upsert(
              payloads,
              onConflict: 'employee_id,attendance_date',
            );
      } else {
        final existingKeys = await _fetchExistingKeys(payloads);
        final fresh = payloads
            .where((p) => !existingKeys.contains(_keyOf(p)))
            .toList();
        skipped = payloads.length - fresh.length;
        inserted = fresh.length;
        if (fresh.isNotEmpty) {
          await client.from('attendance_day_records').insert(fresh);
        }
      }

      await client.from('attendance_imports').update({
        'status': 'COMPLETED',
        'processed_rows': payloads.length,
        'valid_rows': inserted + updated,
        'duplicate_rows': skipped,
        'invalid_rows':
            _unknownEmployeeNumbers.length + _parseErrors.length,
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', importId);

      if (!mounted) return;
      ref.invalidate(attendanceListProvider);
      final summary = _dedup == _DedupMode.overwrite
          ? 'Imported — $inserted new, $updated overwritten.'
          : 'Imported — $inserted new, $skipped skipped (already on file).';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(summary)));
      Navigator.pop(context);
    } catch (e) {
      setState(() => _statusMsg = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _keyOf(Map<String, dynamic> p) =>
      '${p['employee_id']}|${p['attendance_date']}';

  Future<Set<String>> _fetchExistingKeys(
      List<Map<String, dynamic>> payloads) async {
    if (payloads.isEmpty) return const {};
    final empIds =
        payloads.map((p) => p['employee_id'] as String).toSet().toList();
    final dates = payloads.map((p) => p['attendance_date'] as String).toList()
      ..sort();
    final rows = await Supabase.instance.client
        .from('attendance_day_records')
        .select('employee_id, attendance_date')
        .inFilter('employee_id', empIds)
        .gte('attendance_date', dates.first)
        .lte('attendance_date', dates.last);
    return {
      for (final r in rows.cast<Map<String, dynamic>>())
        '${r['employee_id']}|${r['attendance_date']}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _rows.isNotEmpty && !_busy;
    return AlertDialog(
      title: const Text('Import Attendance (CSV)'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _helpBlock(context),
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(_fileName == null ? 'Choose CSV' : 'Replace file'),
                  ),
                  const SizedBox(width: 12),
                  if (_fileName != null)
                    Expanded(
                      child: Text(
                        '$_fileName  •  ${_rows.length} valid row${_rows.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ]),
                if (_rows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _previewTable(),
                ],
                if (_unknownEmployeeNumbers.isNotEmpty)
                  _warnBlock(
                    context,
                    'Unknown employee numbers — rows skipped:',
                    _unknownEmployeeNumbers,
                  ),
                if (_parseErrors.isNotEmpty)
                  _warnBlock(
                    context,
                    'Parse errors:',
                    _parseErrors,
                  ),
                const SizedBox(height: 16),
                const Text('Duplicate handling',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                RadioListTile<_DedupMode>(
                  contentPadding: EdgeInsets.zero,
                  value: _DedupMode.skip,
                  groupValue: _dedup,
                  onChanged: (v) => setState(() => _dedup = v!),
                  title: const Text('Skip existing records'),
                  subtitle: const Text(
                      'If a record exists for (employee, date), leave it alone.'),
                ),
                RadioListTile<_DedupMode>(
                  contentPadding: EdgeInsets.zero,
                  value: _DedupMode.overwrite,
                  groupValue: _dedup,
                  onChanged: (v) => setState(() => _dedup = v!),
                  title: const Text('Overwrite existing records'),
                  subtitle: const Text(
                      'Replace matching rows with the values from this file.'),
                ),
                if (_statusMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_statusMsg!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ),
              ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_rows.isEmpty
                  ? 'Import'
                  : 'Import ${_rows.length} row${_rows.length == 1 ? '' : 's'}'),
        ),
      ],
    );
  }

  Widget _helpBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Expected CSV format',
                style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text(
              'Header row: employee_number, date, time_in, time_out\n'
              'date = YYYY-MM-DD   •   time_in / time_out = HH:MM (24h)\n'
              'Leave time fields blank for absent days.',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ]),
    );
  }

  Widget _previewTable() {
    final preview = _rows.take(10).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            const Text('Preview',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('showing ${preview.length} of ${_rows.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ),
        const Divider(height: 1),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            headingRowHeight: 32,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 32,
            columns: const [
              DataColumn(label: Text('Employee #')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('In')),
              DataColumn(label: Text('Out')),
            ],
            rows: [
              for (final r in preview)
                DataRow(cells: [
                  DataCell(Text(r.employeeNumber,
                      style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(Text(
                      r.date.toIso8601String().substring(0, 10),
                      style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(Text(_hhmm(r.timeIn),
                      style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(Text(_hhmm(r.timeOut),
                      style: const TextStyle(fontFamily: 'monospace'))),
                ]),
            ],
          ),
        ),
      ]),
    );
  }

  static String _hhmm(DateTime? dt) {
    if (dt == null) return '—';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _warnBlock(BuildContext context, String label, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E))),
              const SizedBox(height: 4),
              for (final s in items.take(10))
                Text('• $s',
                    style: const TextStyle(
                        color: Color(0xFF92400E), fontSize: 12)),
              if (items.length > 10)
                Text('… and ${items.length - 10} more',
                    style: const TextStyle(
                        color: Color(0xFF92400E), fontSize: 12)),
            ]),
      ),
    );
  }
}

class _ParsedRow {
  final String employeeId;
  final String employeeNumber;
  final DateTime date;
  final DateTime? timeIn;
  final DateTime? timeOut;
  const _ParsedRow({
    required this.employeeId,
    required this.employeeNumber,
    required this.date,
    required this.timeIn,
    required this.timeOut,
  });
}
