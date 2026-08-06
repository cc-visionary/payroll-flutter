import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/attendance_repository.dart';
import '../../widgets/syncing_dialog.dart';
import 'lark_repository.dart';

/// Pulls the standard Lark approval bundle — attendance + leaves +
/// reimbursements — for [from] → [to] behind a blocking [SyncingDialog], then
/// shows the usual "+created ~updated skipped" summary snackbar and refreshes
/// the attendance list. They all flow from Lark approvals and HR expects one
/// button to pull the whole bundle.
///
/// [to] is capped at today: Lark has no records for future dates. When the
/// whole range is in the future the sync is skipped with a snackbar.
///
/// Returns true when the sync ran (even if individual rows errored), false
/// when it failed outright or was skipped — callers chaining a reload or
/// recompute should stop on false.
Future<bool> runLarkBundleSync(
  BuildContext context,
  WidgetRef ref, {
  required String companyId,
  required DateTime from,
  required DateTime to,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final cappedTo = to.isAfter(today) ? today : to;
  if (from.isAfter(cappedTo)) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Pay period starts in the future — nothing to sync yet.'),
      ),
    );
    return false;
  }
  final lark = ref.read(larkRepositoryProvider);
  final fromIso = _isoDate(from);
  final toIso = _isoDate(cappedTo);
  try {
    final results = await runWithSyncingDialog(
      context,
      'Lark sync ($fromIso → $toIso)',
      () async {
        final attRes = await Supabase.instance.client.functions.invoke(
          'sync-lark-attendance',
          body: {'company_id': companyId, 'from': fromIso, 'to': toIso},
        );
        final leavesAndReimbs = await Future.wait([
          lark.syncLeaves(companyId, from: from, to: cappedTo),
          lark.syncReimbursements(companyId, from: from, to: cappedTo),
        ]);
        return (
          attendance: attRes,
          leaves: leavesAndReimbs[0],
          reimbursements: leavesAndReimbs[1],
        );
      },
    );
    final att = (results.attendance.data as Map?) ?? const {};
    final attLine = att['ok'] == true
        ? 'Attendance: +${att['created']} ~${att['updated']} skipped ${att['skipped']}'
        : 'Attendance error: ${att['error'] ?? 'unknown'}';
    String summaryLine(String label, LarkSyncResult r) =>
        '$label: +${r.created} ~${r.updated} skipped ${r.skipped}'
        '${r.errors.isNotEmpty ? ' (${r.errors.length} errors)' : ''}';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          [
            attLine,
            summaryLine('Leaves', results.leaves),
            summaryLine('Reimbursements', results.reimbursements),
          ].join('  •  '),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
    if (context.mounted) ref.invalidate(attendanceListProvider);
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    return false;
  }
}

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
