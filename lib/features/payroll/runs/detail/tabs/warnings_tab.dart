import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../attendance/attendance_row_vm.dart' show isoDate;
import '../providers.dart';
import '../warnings.dart';

/// Read-only list of live attendance anomalies for a run. Ephemeral — recomputed
/// from attendance each load. Tapping a row deep-links to that day's attendance.
class PayrollWarningsTab extends ConsumerWidget {
  final String runId;
  const PayrollWarningsTab({super.key, required this.runId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(runWarningsProvider(runId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (warnings) {
        if (warnings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 40, color: Color(0xFF16A34A)),
                  const SizedBox(height: 12),
                  Text(
                    'No attendance warnings for this period.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Row(
              children: [
                Text(
                  '${warnings.length} warning${warnings.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => ref.invalidate(runWarningsProvider(runId)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < warnings.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                    _WarningRow(warning: warnings[i]),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WarningRow extends StatelessWidget {
  final RunWarning warning;
  const _WarningRow({required this.warning});

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = _style(warning.type);
    return InkWell(
      onTap: () => context
          .go('/attendance/${warning.employeeId}/${isoDate(warning.date)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    warning.employeeLabel,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtDate(warning.date)} · ${warning.message}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  static (IconData, Color, Color) _style(WarningType t) {
    switch (t) {
      case WarningType.invalidWorkedTime:
        return (
          Icons.error_outline,
          const Color(0xFFFEE2E2),
          const Color(0xFF991B1B)
        );
      case WarningType.missingClockOut:
      case WarningType.missingClockIn:
      case WarningType.unapprovedOvertime:
        return (
          Icons.warning_amber_rounded,
          const Color(0xFFFEF3C7),
          const Color(0xFF92400E)
        );
    }
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
