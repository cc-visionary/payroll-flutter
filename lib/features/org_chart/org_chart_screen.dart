import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../workforce_planning/org_tree_view.dart';
import '../workforce_planning/wp_providers.dart';

/// Live reporting structure across the company, from employees.reports_to_id.
/// Read-only (name + title); the Workforce Planning Structure tab adds load +
/// drag-to-restructure for HR/Admin.
class OrgChartScreen extends ConsumerWidget {
  const OrgChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Org Chart')),
      body: empsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (emps) {
          if (emps.isEmpty) return const Center(child: Text('No employees to show.'));
          final empById = {for (final e in emps) e.id: e};
          final people = [for (final e in emps) (id: e.id, parentId: e.reportsToId)];
          return OrgTreeView(people: people, empById: empById);
        },
      ),
    );
  }
}
