import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/employee_repository.dart';

/// Autocomplete field for HR Manager Name. Suggests from the active
/// employee list as the user types; free-text is still accepted (for
/// external consultants or names not on the roster).
class HrManagerField extends ConsumerWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hintText;
  const HrManagerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeeListProvider(const EmployeeListQuery()));
    final names = async.asData?.value
            .map((e) => e.fullName)
            .where((n) => n.isNotEmpty)
            .toList() ??
        const <String>[];

    return Autocomplete<String>(
      // Re-seed the field when the parent's `value` changes (e.g. after
      // re-autofill on employee change).
      key: ValueKey('hr-manager-$value'),
      initialValue: TextEditingValue(text: value),
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return names.take(8);
        return names
            .where((n) => n.toLowerCase().contains(q))
            .take(8);
      },
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: hintText ?? 'Type or select an employee',
          ),
          onChanged: onChanged,
        );
      },
      onSelected: onChanged,
    );
  }
}
