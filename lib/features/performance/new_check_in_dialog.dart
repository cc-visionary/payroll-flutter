import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/employee.dart';
import '../../data/quarter.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';

/// Result of [showNewCheckInDialog]: the check-in [id] to navigate to, and
/// whether it [existed] already (vs. newly created) so the caller can message
/// accordingly.
typedef NewCheckInResult = ({String id, bool existed});

/// Manual "New check-in" dialog. HR/Admin picks an employee and a quarter; the
/// matching company-wide period is ensured (any quarter, including past ones),
/// then a DRAFT check-in is created — or the existing one is opened if it was
/// already generated. Returns null if cancelled.
Future<NewCheckInResult?> showNewCheckInDialog({required BuildContext context}) {
  return showDialog<NewCheckInResult>(
    context: context,
    builder: (_) => const _NewCheckInDialog(),
  );
}

class _NewCheckInDialog extends ConsumerStatefulWidget {
  const _NewCheckInDialog();

  @override
  ConsumerState<_NewCheckInDialog> createState() => _NewCheckInDialogState();
}

class _NewCheckInDialogState extends ConsumerState<_NewCheckInDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _employeeId;
  late final List<Quarter> _quarters;
  late final Quarter _currentQuarter;
  late Quarter _quarter;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentQuarter = quarterOf(now);
    _quarters = quarterOptions(now);
    _quarter = _currentQuarter;
  }

  Future<void> _create(List<Employee> employees) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await ref.read(userProfileProvider.future);
      final companyId = profile?.companyId;
      if (companyId == null || companyId.isEmpty) {
        throw Exception('No company on your profile.');
      }
      final emp = employees.firstWhere((e) => e.id == _employeeId);
      final repo = ref.read(performanceRepositoryProvider);

      final periodId = await repo.ensureQuarterlyPeriod(
        companyId: companyId,
        year: _quarter.year,
        quarter: _quarter.quarter,
      );

      final existingId =
          await repo.findCheckInId(periodId: periodId, employeeId: emp.id);
      final NewCheckInResult result;
      if (existingId != null) {
        result = (id: existingId, existed: true);
      } else {
        final checkInId = await repo.ensureCheckInForEmployeeInPeriod(
          periodId: periodId,
          employeeId: emp.id,
          reviewerId: emp.reportsToId,
        );
        await repo.seedSkillRatingsForCheckIn(
          checkInId: checkInId,
          roleScorecardId: emp.roleScorecardId,
          employeeId: emp.id,
        );
        result = (id: checkInId, existed: false);
      }

      ref.invalidate(performanceCheckInListProvider);
      ref.invalidate(checkInPeriodNamesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync =
        ref.watch(employeeListProvider(const EmployeeListQuery()));

    return AlertDialog(
      title: const Text('New check-in'),
      content: SizedBox(
        width: 420,
        child: employeesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Failed to load employees: $e',
              style: const TextStyle(color: Colors.red)),
          data: (employees) {
            final sorted = [...employees]
              ..sort((a, b) => a.fullName
                  .toLowerCase()
                  .compareTo(b.fullName.toLowerCase()));
            return Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _employeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Employee',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final e in sorted)
                        DropdownMenuItem(
                          value: e.id,
                          child: Text(e.fullName, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    validator: (v) => v == null ? 'Pick an employee' : null,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _employeeId = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Quarter>(
                    initialValue: _quarter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Quarter',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final q in _quarters)
                        DropdownMenuItem(
                          value: q,
                          child: Text(q == _currentQuarter
                              ? '${q.periodName} (current)'
                              : q.periodName),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _quarter = v ?? _quarter),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || !employeesAsync.hasValue
              ? null
              : () => _create(employeesAsync.value!),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
