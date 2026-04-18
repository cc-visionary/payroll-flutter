import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/models/employee.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});
  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  String _search = '';
  bool _includeArchived = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final query = EmployeeListQuery(
        search: _search.isEmpty ? null : _search,
        includeArchived: _includeArchived);
    final async = ref.watch(employeeListProvider(query));
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final roleTitleById = <String, String>{
      for (final c in cardsAsync.asData?.value ?? const []) c.id: c.jobTitle,
    };
    final canManage = profile?.canManageEmployees ?? false;

    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => context.push('/employees/new'),
                icon: const Icon(Icons.add),
                label: const Text('New employee'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name or employee #',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 16),
                FilterChip(
                  label: const Text('Include archived'),
                  selected: _includeArchived,
                  onSelected: (v) => setState(() => _includeArchived = v),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(employeeListProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: async.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
                    ),
                  ),
                  data: (rows) => rows.isEmpty
                      ? const Center(child: Text('No employees found.'))
                      : _EmployeesTable(
                          rows: rows,
                          canManage: canManage,
                          roleTitleById: roleTitleById,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeesTable extends ConsumerWidget {
  final List<Employee> rows;
  final bool canManage;
  final Map<String, String> roleTitleById;
  const _EmployeesTable({
    required this.rows,
    required this.canManage,
    required this.roleTitleById,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DataTable2(
      columnSpacing: 16,
      horizontalMargin: 16,
      minWidth: 1000,
      columns: const [
        DataColumn2(label: Text('Employee #'), size: ColumnSize.S),
        DataColumn2(label: Text('Name')),
        DataColumn2(label: Text('Job Title'), size: ColumnSize.L),
        DataColumn2(label: Text('Type'), size: ColumnSize.S),
        DataColumn2(label: Text('Status'), size: ColumnSize.S),
        DataColumn2(label: Text('Hire Date'), size: ColumnSize.S),
        DataColumn2(label: Text(''), size: ColumnSize.S),
      ],
      rows: rows.map((e) {
        final archived = e.deletedAt != null;
        return DataRow2(
          onTap: () {
            final router = GoRouter.of(context);
            router.push('/employees/${e.id}');
          },
          cells: [
            DataCell(Text(e.employeeNumber)),
            DataCell(Text(e.fullName,
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    decoration: archived ? TextDecoration.lineThrough : null))),
            DataCell(Text(
              (e.roleScorecardId != null ? roleTitleById[e.roleScorecardId] : null) ??
                  e.jobTitle ??
                  '—',
            )),
            DataCell(_StatusChip(e.employmentType)),
            DataCell(_StatusChip(e.employmentStatus)),
            DataCell(Text(e.hireDate.toIso8601String().substring(0, 10))),
            DataCell(canManage
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () =>
                            GoRouter.of(context).push('/employees/${e.id}/edit'),
                      ),
                      IconButton(
                        tooltip: archived ? 'Restore' : 'Archive',
                        icon: Icon(
                            archived ? Icons.restore : Icons.archive_outlined,
                            size: 18),
                        onPressed: () async {
                          final repo = ref.read(employeeRepositoryProvider);
                          if (archived) {
                            await repo.restore(e.id);
                          } else {
                            await repo.archive(e.id);
                          }
                          ref.invalidate(employeeListProvider);
                        },
                      ),
                    ],
                  )
                : const SizedBox.shrink()),
          ],
        );
      }).toList(),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String value;
  const _StatusChip(this.value);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(value, style: const TextStyle(fontSize: 11)),
    );
  }
}
