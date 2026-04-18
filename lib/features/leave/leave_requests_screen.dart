import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../auth/profile_provider.dart';
import 'leave_format.dart';

final _leaveRequestsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, employeeId) async {
  var q = Supabase.instance.client
      .from('leave_requests')
      .select('*, leave_types(name, code)');
  if (employeeId != null) q = q.eq('employee_id', employeeId);
  final rows = await q.order('start_date', ascending: false).limit(200) as List<dynamic>;
  return rows.cast<Map<String, dynamic>>();
});

class LeaveRequestsScreen extends ConsumerWidget {
  const LeaveRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final employeeId = (profile?.isHrOrAdmin ?? false) ? null : profile?.employeeId;
    final async = ref.watch(_leaveRequestsProvider(employeeId));

    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Leave Requests')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('No leave requests.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (c, i) {
                  final r = rows[i];
                  final type = (r['leave_types'] as Map?)?['name'] ?? (r['leave_types'] as Map?)?['code'] ?? '—';
                  final status = r['status'] as String;
                  final durationLabel = formatLeaveDurationUnit(
                    larkUnit: r['lark_leave_unit'],
                    larkDuration: r['lark_leave_duration'],
                    leaveDays: r['leave_days'],
                  );
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: _statusIcon(status),
                      title: Text('$type · $durationLabel'),
                      subtitle: Text(
                          '${r['start_date']} → ${r['end_date']}${r['reason'] == null ? '' : '\n${r['reason']}'}'),
                      trailing: Chip(
                          label: Text(status), visualDensity: VisualDensity.compact),
                      isThreeLine: r['reason'] != null,
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'APPROVED':
        return const Icon(Icons.check_circle_outline, color: Colors.green);
      case 'REJECTED':
        return const Icon(Icons.cancel_outlined, color: Colors.red);
      case 'CANCELLED':
        return const Icon(Icons.block, color: Colors.grey);
      default:
        return const Icon(Icons.hourglass_top, color: Colors.orange);
    }
  }
}
