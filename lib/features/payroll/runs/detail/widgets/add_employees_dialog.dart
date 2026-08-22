import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/models/payroll_run.dart';
import '../run_roster_service.dart';

/// Picker for adding employees to an existing payroll run.
///
/// Lists the active employees eligible for the run's period that are not on
/// its roster yet, and pops with the ids the user ticked (or null on cancel).
/// The caller owns the write + recompute — this dialog only chooses.
class AddEmployeesDialog extends ConsumerStatefulWidget {
  final PayrollRun run;
  const AddEmployeesDialog({super.key, required this.run});

  @override
  ConsumerState<AddEmployeesDialog> createState() => _AddEmployeesDialogState();
}

class _AddEmployeesDialogState extends ConsumerState<AddEmployeesDialog> {
  List<Map<String, dynamic>>? _candidates;
  String? _error;
  String _search = '';
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref
          .read(payrollRosterServiceProvider)
          .employeesEligibleToAdd(widget.run);
      if (!mounted) return;
      setState(() => _candidates = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final rows = _candidates ?? const <Map<String, dynamic>>[];
    if (_search.isEmpty) return rows;
    final q = _search.toLowerCase();
    return [
      for (final r in rows)
        if (_fullName(r).toLowerCase().contains(q) ||
            (r['employee_number'] as String? ?? '').toLowerCase().contains(q))
          r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Add employees to this run'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Adding recomputes the run so their payslips are generated. '
              'Employees already on the run are not listed.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search employees...',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: _body(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<List<String>>(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop<List<String>>(context, _selected.toList()),
          child: Text(
            _selected.isEmpty
                ? 'Add'
                : 'Add ${_selected.length} employee'
                      '${_selected.length == 1 ? '' : 's'}',
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Failed to load employees: $_error',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      );
    }
    if (_candidates == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final rows = _filtered;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _candidates!.isEmpty
                ? 'Every eligible employee is already on this run.'
                : 'No employees match "$_search".',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        final id = r['id'] as String;
        return CheckboxListTile(
          dense: true,
          value: _selected.contains(id),
          onChanged: (v) => setState(() {
            if (v ?? false) {
              _selected.add(id);
            } else {
              _selected.remove(id);
            }
          }),
          title: Text(_fullName(r), style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            r['employee_number'] as String? ?? '—',
            style: const TextStyle(fontSize: 11),
          ),
        );
      },
    );
  }

  static String _fullName(Map<String, dynamic> e) => [
    e['first_name'],
    e['middle_name'],
    e['last_name'],
  ].where((s) => s != null && (s as String).isNotEmpty).join(' ');
}
