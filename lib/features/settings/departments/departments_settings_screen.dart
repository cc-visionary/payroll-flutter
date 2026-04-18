import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/department.dart';
import '../../../data/models/employee.dart';
import '../../../data/repositories/department_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../../auth/profile_provider.dart';

class DepartmentsSettingsScreen extends ConsumerWidget {
  const DepartmentsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deptsAsync = ref.watch(departmentListProvider);
    final countsAsync = ref.watch(departmentEmployeeCountsProvider);
    final employeesAsync =
        ref.watch(employeeListProvider(const EmployeeListQuery()));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Departments',
              style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _openForm(context, ref,
                employees: employeesAsync.asData?.value ?? const []),
            icon: const Icon(Icons.add),
            label: const Text('Add Department'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Organize employees and define approval routing. Departments with '
          'assigned employees cannot be deleted.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: deptsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: Colors.red))),
            data: (depts) => depts.isEmpty
                ? const Center(
                    child: Text(
                        'No departments yet. Click "Add Department" to create one.'))
                : SingleChildScrollView(
                    child: ResponsiveTable(
                      fullWidth: true,
                      child: DataTable(
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Code')),
                          DataColumn(label: Text('Manager')),
                          DataColumn(label: Text('Cost Center')),
                          DataColumn(label: Text('Employees')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: depts.map((d) {
                          final count =
                              countsAsync.asData?.value[d.id] ?? 0;
                          final manager = _managerName(
                              employeesAsync.asData?.value, d.managerId);
                          return DataRow(cells: [
                            DataCell(Text(d.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(Text(d.code,
                                style:
                                    const TextStyle(fontFamily: 'monospace'))),
                            DataCell(Text(manager ?? '—',
                                style: TextStyle(
                                    color: manager == null
                                        ? Colors.grey
                                        : null))),
                            DataCell(Text(d.costCenterCode ?? '—',
                                style: const TextStyle(
                                    fontFamily: 'monospace'))),
                            DataCell(Text('$count')),
                            DataCell(Row(children: [
                              TextButton(
                                onPressed: () => _openForm(context, ref,
                                    existing: d,
                                    employees: employeesAsync.asData?.value ??
                                        const []),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: count > 0
                                    ? null
                                    : () => _confirmDelete(context, ref, d),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                child: const Text('Delete'),
                              ),
                            ])),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }

  static String? _managerName(List<Employee>? employees, String? id) {
    if (id == null || employees == null) return null;
    for (final e in employees) {
      if (e.id == id) return '${e.firstName} ${e.lastName}'.trim();
    }
    return null;
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Department? existing,
    required List<Employee> employees,
  }) async {
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    await showDialog(
      context: context,
      builder: (_) => _DepartmentForm(
        companyId: profile.companyId,
        existing: existing,
        employees: employees,
        onSaved: () {
          ref.invalidate(departmentListProvider);
          ref.invalidate(departmentEmployeeCountsProvider);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Department d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete department?'),
        content: Text('Remove "${d.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(departmentRepositoryProvider).delete(d.id);
    ref.invalidate(departmentListProvider);
  }
}

class _DepartmentForm extends ConsumerStatefulWidget {
  final String companyId;
  final Department? existing;
  final List<Employee> employees;
  final VoidCallback onSaved;
  const _DepartmentForm({
    required this.companyId,
    required this.existing,
    required this.employees,
    required this.onSaved,
  });

  @override
  ConsumerState<_DepartmentForm> createState() => _FormState();
}

class _FormState extends ConsumerState<_DepartmentForm> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _costCenter = TextEditingController();
  String? _managerId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name.text = e?.name ?? '';
    _code.text = e?.code ?? '';
    _costCenter.text = e?.costCenterCode ?? '';
    _managerId = e?.managerId;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _costCenter.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final code = _code.text.trim().toUpperCase();
    if (name.isEmpty || code.isEmpty) {
      setState(() => _error = 'Name and code are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(departmentRepositoryProvider).upsert(
            id: widget.existing?.id,
            companyId: widget.companyId,
            code: code,
            name: name,
            costCenterCode:
                _costCenter.text.trim().isEmpty ? null : _costCenter.text.trim(),
            managerId: _managerId,
          );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final managers = [...widget.employees]
      ..sort((a, b) => a.employeeNumber.compareTo(b.employeeNumber));
    return AlertDialog(
      title: Text(
          widget.existing == null ? 'Add Department' : 'Edit Department'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Name', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            decoration: const InputDecoration(
                labelText: 'Code',
                hintText: 'e.g. HR, OPS, ENG',
                border: OutlineInputBorder()),
            style: const TextStyle(fontFamily: 'monospace'),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
              LengthLimitingTextInputFormatter(20),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _costCenter,
            decoration: const InputDecoration(
                labelText: 'Cost Center Code (optional)',
                border: OutlineInputBorder()),
            style: const TextStyle(fontFamily: 'monospace'),
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _managerId,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Manager (optional)',
                border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('— None —')),
              for (final e in managers)
                DropdownMenuItem<String?>(
                  value: e.id,
                  child: Text('${e.firstName} ${e.lastName}'.trim()),
                ),
            ],
            onChanged: (v) => setState(() => _managerId = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
