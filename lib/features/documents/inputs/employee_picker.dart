import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/employee_repository.dart';

class EmployeePicker extends ConsumerWidget {
  final String? selectedId;
  final bool locked;
  final bool includeArchived;
  final ValueChanged<String?> onChanged;
  const EmployeePicker({
    super.key,
    required this.selectedId,
    required this.locked,
    this.includeArchived = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      employeeListProvider(EmployeeListQuery(includeArchived: includeArchived)),
    );
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error loading employees: $e'),
      data: (employees) {
        return DropdownButtonFormField<String>(
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final e in employees)
              DropdownMenuItem(value: e.id, child: Text(e.fullName)),
          ],
          onChanged: locked ? null : onChanged,
        );
      },
    );
  }
}
