import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/payroll_repository.dart';
import '../../../auth/profile_provider.dart';
import '../compute/compute_service.dart';

/// "New Payroll Run" dialog. Always creates a fresh pay period under the
/// company's calendar for the chosen date range — reusing an existing
/// period is no longer supported (each run gets its own period). On confirm,
/// creates a DRAFT payroll_run scoped to the employees the user selected and
/// navigates to `/payroll/:id`.
Future<void> showNewPayrollRunDialog(BuildContext context, WidgetRef ref) async {
  final profile = ref.read(userProfileProvider).asData?.value;
  final companyId = profile?.companyId;
  if (companyId == null || companyId.isEmpty) return;
  await showDialog(
    context: context,
    builder: (_) => _NewRunDialog(
      companyId: companyId,
      createdById: profile?.userId,
    ),
  );
}

class _NewRunDialog extends ConsumerStatefulWidget {
  final String companyId;
  final String? createdById;
  const _NewRunDialog({required this.companyId, this.createdById});

  @override
  ConsumerState<_NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends ConsumerState<_NewRunDialog> {
  // New-period state
  String _frequency = 'SEMI_MONTHLY';
  late DateTime _startDate;
  late DateTime _endDate;
  late DateTime _payDate;

  // Employee-selection state (shared by both modes once dates are known)
  List<Map<String, dynamic>>? _employees;
  String? _employeesError;
  bool _loadingEmployees = false;
  final Set<String> _selectedEmployeeIds = <String>{};
  // Monotonically-incrementing token so a late-arriving employee fetch
  // doesn't overwrite a newer one when the user changes dates quickly.
  int _employeeLoadToken = 0;

  bool _busy = false;
  String? _busyLabel;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _startDate = DateTime(today.year, today.month, today.day);
    _endDate = _startDate.add(const Duration(days: 14));
    _payDate = _endDate.add(const Duration(days: 5));
    _reloadEmployees(); // initial fetch for the default create-mode range
  }

  ({DateTime from, DateTime to}) _currentRange() =>
      (from: _startDate, to: _endDate);

  Future<void> _reloadEmployees() async {
    final range = _currentRange();
    final token = ++_employeeLoadToken;
    setState(() {
      _loadingEmployees = true;
      _employeesError = null;
    });
    try {
      final rows = await ref
          .read(payrollRepositoryProvider)
          .employeesWithAttendance(
            companyId: widget.companyId,
            from: range.from,
            to: range.to,
          );
      if (!mounted || token != _employeeLoadToken) return;
      setState(() {
        _employees = rows;
        _loadingEmployees = false;
        _selectedEmployeeIds
          ..clear()
          ..addAll(rows.map((e) => e['id'] as String));
      });
    } catch (err) {
      if (!mounted || token != _employeeLoadToken) return;
      setState(() {
        _loadingEmployees = false;
        _employeesError = err.toString();
      });
    }
  }

  String get _derivedCode =>
      '${_isoDate(_startDate)} - ${_isoDate(_endDate)}';

  String? _validateCreateMode() {
    if (_endDate.isBefore(_startDate)) {
      return 'End date must be on or after start date.';
    }
    if (_payDate.isBefore(_endDate)) {
      return 'Pay date must be on or after end date.';
    }
    return null;
  }

  bool get _canSubmit {
    if (_busy) return false;
    if (_selectedEmployeeIds.isEmpty) return false;
    return _validateCreateMode() == null;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Creating run…';
      _validationError = null;
    });
    try {
      final repo = ref.read(payrollRepositoryProvider);
      final compute = ref.read(payrollComputeServiceProvider);

      // Block if any selected employee is already covered by a non-CANCELLED
      // run whose date range overlaps — they'd otherwise end up with
      // duplicate payslips for the same days.
      final covered = await repo.employeesCoveredByActiveRuns(
        companyId: widget.companyId,
        periodStart: _startDate,
        periodEnd: _endDate,
      );
      final conflictIds =
          _selectedEmployeeIds.where(covered.contains).toList();
      if (conflictIds.isNotEmpty) {
        final rows = await repo.employeesByIds(conflictIds);
        final names = rows
            .map((e) =>
                '${e['last_name'] ?? ''}, ${e['first_name'] ?? ''}'.trim())
            .where((s) => s.isNotEmpty && s != ',')
            .toList()
          ..sort();
        final preview = names.take(5).join('; ');
        final suffix = names.length > 5 ? ' (+${names.length - 5} more)' : '';
        throw Exception(
          '${names.length} selected employee${names.length == 1 ? " is" : "s are"} already in an active run overlapping this range: $preview$suffix. Cancel those runs first, or deselect these employees.',
        );
      }

      final newRunId = await repo.createRun(
        companyId: widget.companyId,
        periodStart: _startDate,
        periodEnd: _endDate,
        payDate: _payDate,
        payFrequency: _frequency,
        createdById: widget.createdById,
        includedEmployeeIds: _selectedEmployeeIds.toList(),
      );

      // Auto-compute so the user lands on a ready-to-review run rather than
      // a blank DRAFT that still needs a separate "Compute Payroll" click.
      // Failure here isn't fatal — the run still exists; the detail page has
      // a "Compute Payroll" button they can retry with.
      String? computeWarning;
      try {
        if (mounted) setState(() => _busyLabel = 'Computing payslips…');
        final outcome = await compute.computeRun(newRunId);
        if (outcome.errors.isNotEmpty) {
          computeWarning =
              'Run created. Compute had ${outcome.errors.length} error(s) — see details on the run page.';
        }
      } catch (err) {
        computeWarning =
            'Run created, but automatic compute failed: ${_friendlyError(err.toString())}. Open the run and click "Compute Payroll" to retry.';
      }

      ref.invalidate(payrollRunsProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      if (computeWarning != null) {
        messenger.showSnackBar(SnackBar(
          content: Text(computeWarning),
          duration: const Duration(seconds: 6),
        ));
      }
      context.go('/payroll/$newRunId');
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyLabel = null;
        _validationError = _friendlyError(err.toString());
      });
    }
  }

  String _friendlyError(String raw) {
    return raw.replaceAll('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New Payroll Run',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Select the pay period and employees to include',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _CreateBody(
                frequency: _frequency,
                startDate: _startDate,
                endDate: _endDate,
                payDate: _payDate,
                derivedCode: _derivedCode,
                enabled: !_busy,
                onFrequency: (v) => setState(() => _frequency = v),
                onPeriodRange: (start, end) {
                  setState(() {
                    _startDate = start;
                    _endDate = end;
                    if (_payDate.isBefore(end)) {
                      _payDate = end.add(const Duration(days: 5));
                    }
                  });
                  _reloadEmployees();
                },
                onPayDate: (d) => setState(() => _payDate = d),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _EmployeesSection(
                  loading: _loadingEmployees,
                  error: _employeesError,
                  employees: _employees,
                  selectedIds: _selectedEmployeeIds,
                  onToggle: (id) => setState(() {
                    if (_selectedEmployeeIds.contains(id)) {
                      _selectedEmployeeIds.remove(id);
                    } else {
                      _selectedEmployeeIds.add(id);
                    }
                  }),
                  onSelectAll: () => setState(() {
                    _selectedEmployeeIds
                      ..clear()
                      ..addAll(
                        (_employees ?? const []).map((e) => e['id'] as String),
                      );
                  }),
                  onDeselectAll: () =>
                      setState(_selectedEmployeeIds.clear),
                ),
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _validationError!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              if (_validateCreateMode() != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _validateCreateMode()!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _busy
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(_busyLabel ?? 'Working…'),
                            ],
                          )
                        : Text(_selectedEmployeeIds.isEmpty
                            ? 'Create Run'
                            : 'Create Run (${_selectedEmployeeIds.length} employee${_selectedEmployeeIds.length == 1 ? '' : 's'})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create body
// ---------------------------------------------------------------------------

class _CreateBody extends StatelessWidget {
  final String frequency;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime payDate;
  final String derivedCode;
  final bool enabled;
  final ValueChanged<String> onFrequency;
  final void Function(DateTime start, DateTime end) onPeriodRange;
  final ValueChanged<DateTime> onPayDate;
  const _CreateBody({
    required this.frequency,
    required this.startDate,
    required this.endDate,
    required this.payDate,
    required this.derivedCode,
    required this.enabled,
    required this.onFrequency,
    required this.onPeriodRange,
    required this.onPayDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: frequency,
          decoration: const InputDecoration(
            labelText: 'Pay frequency',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: enabled
              ? (v) => v == null ? null : onFrequency(v)
              : null,
          items: const [
            DropdownMenuItem(value: 'WEEKLY', child: Text('Weekly')),
            DropdownMenuItem(value: 'BI_WEEKLY', child: Text('Bi-weekly')),
            DropdownMenuItem(
                value: 'SEMI_MONTHLY', child: Text('Semi-monthly')),
            DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
          ],
        ),
        const SizedBox(height: 12),
        _PeriodRangeField(
          start: startDate,
          end: endDate,
          enabled: enabled,
          onChanged: onPeriodRange,
        ),
        const SizedBox(height: 12),
        _DateField(
          label: 'Pay date',
          value: payDate,
          enabled: enabled,
          onChanged: onPayDate,
        ),
        const SizedBox(height: 10),
        Text(
          'Pay period code: $derivedCode',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Single-field pay-period picker. Opens Flutter's built-in
/// [showDateRangePicker] (calendar on desktop, full-screen on mobile) so the
/// admin sees start + end highlighted together.
class _PeriodRangeField extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final bool enabled;
  final void Function(DateTime start, DateTime end) onChanged;
  const _PeriodRangeField({
    required this.start,
    required this.end,
    required this.enabled,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: 'Pay period',
      saveText: 'Use period',
      fieldStartLabelText: 'Start',
      fieldEndLabelText: 'End',
    );
    if (picked != null) {
      onChanged(picked.start, picked.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Pay period',
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(Icons.date_range, size: 16),
        ),
        child: Text(
          '${_isoDate(start)}  →  ${_isoDate(end)}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        child: Text(
          _isoDate(value),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(picked);
  }
}

// ---------------------------------------------------------------------------
// Employees section (auto-fetched by date range)
// ---------------------------------------------------------------------------

class _EmployeesSection extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>>? employees;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;

  const _EmployeesSection({
    required this.loading,
    required this.error,
    required this.employees,
    required this.selectedIds,
    required this.onToggle,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = employees?.length ?? 0;
    final selected = selectedIds.length;
    final allSelected = total > 0 && selected == total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'Employees${employees == null ? '' : ' ($total found)'}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            if (total > 0)
              TextButton(
                onPressed: allSelected ? onDeselectAll : onSelectAll,
                child: Text(allSelected ? 'Deselect All' : 'Select All'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _body(context),
        ),
        const SizedBox(height: 6),
        Text(
          total == 0
              ? ''
              : '$selected of $total employees selected',
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Failed to load employees: $error',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      );
    }
    final rows = employees;
    if (rows == null || rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No employees have attendance in this range. Sync attendance from Lark or adjust the dates.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: Scrollbar(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: rows.length + 1, // +1 for header row
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) return _headerRow(context);
            final r = rows[i - 1];
            return _employeeRow(context, r);
          },
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Spacer to align with checkbox column below (24 + 12 leading padding)
          const SizedBox(width: 36),
          Expanded(
            child: Text(
              'EMPLOYEE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            'ATTENDANCE DAYS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _employeeRow(BuildContext context, Map<String, dynamic> r) {
    final id = r['id'] as String;
    final isSelected = selectedIds.contains(id);
    final first = r['first_name'] as String? ?? '';
    final last = r['last_name'] as String? ?? '';
    final number = r['employee_number'] as String? ?? '';
    final days = r['attendance_days'] as int? ?? 0;
    return InkWell(
      onTap: () => onToggle(id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggle(id),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    last.isEmpty ? first : '$last, $first',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  if (number.isNotEmpty)
                    Text(
                      number,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '$days',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
