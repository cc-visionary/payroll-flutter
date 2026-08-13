import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/breakpoints.dart';
import '../../../data/models/leave_type.dart';
import '../../../data/repositories/leave_type_repository.dart';
import '../../../widgets/responsive_table.dart';

/// Settings ▸ Leave Types — where a leave type becomes paid, and the only
/// place it can.
///
/// This screen exists because it did not. `sync-lark-leaves` creates a row for
/// every leave type Lark reports, and `is_paid` used to default to true, so
/// every imported type silently paid a full day — Personal leave included —
/// with nothing in the app able to say otherwise. Imported types now arrive
/// unpaid; this is where someone decides which ones are not.
class LeaveTypesSettingsScreen extends ConsumerWidget {
  const LeaveTypesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(leaveTypeListProvider);
    final mobile = isMobile(context);

    return Padding(
      padding: EdgeInsets.all(mobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Leave Types',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Whether payroll pays a full day for each kind of leave. Types '
            'imported from Lark arrive unpaid — Lark reports a type\'s name, '
            'not whether the company pays for it, so that decision is made '
            'here.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: typesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Could not load leave types: $e',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              data: (types) => types.isEmpty
                  ? const Center(
                      child: Text(
                        'No leave types yet. They appear here once Lark leave '
                        'is synced.',
                      ),
                    )
                  : _table(context, ref, types),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, WidgetRef ref, List<LeaveType> types) {
    return SingleChildScrollView(
      child: ResponsiveTable(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Code')),
            DataColumn(label: Text('Source')),
            DataColumn(label: Text('Paid')),
            DataColumn(label: Text('Active')),
          ],
          rows: [
            for (final t in types)
              DataRow(
                key: ValueKey(t.id),
                cells: [
                  DataCell(Text(t.name)),
                  DataCell(Text(t.code)),
                  DataCell(Text(t.isFromLark ? 'Lark' : 'Manual')),
                  DataCell(
                    Switch(
                      value: t.isPaid,
                      onChanged: (v) => _setPaid(context, ref, t, v),
                    ),
                  ),
                  DataCell(
                    Switch(
                      value: t.isActive,
                      onChanged: (v) => _setActive(context, ref, t, v),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setPaid(
    BuildContext context,
    WidgetRef ref,
    LeaveType type,
    bool value,
  ) async {
    // Captured before the dialog await — reaching for the messenger afterwards
    // reads a BuildContext that may no longer be mounted.
    final messenger = ScaffoldMessenger.of(context);

    // Turning a type ON is the direction that costs money, so it asks. Turning
    // one off does not: unpaid is the safe state, and a confirmation there
    // would only train people to dismiss the dialog that matters.
    if (value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Pay for ${type.name}?'),
          content: Text(
            'Payroll will pay a full day for every approved "${type.name}" '
            'day from now on. Released payslips are not changed; open runs '
            'pick this up when they are recomputed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Mark as paid'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _apply(
      messenger,
      ref,
      () => ref.read(leaveTypeRepositoryProvider).setPaid(type.id, value),
    );
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    LeaveType type,
    bool value,
  ) async {
    await _apply(
      ScaffoldMessenger.of(context),
      ref,
      () => ref.read(leaveTypeRepositoryProvider).setActive(type.id, value),
    );
  }

  Future<void> _apply(
    ScaffoldMessengerState messenger,
    WidgetRef ref,
    Future<void> Function() write,
  ) async {
    try {
      await write();
      ref.invalidate(leaveTypeListProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save the change: $e')),
      );
    }
  }
}
