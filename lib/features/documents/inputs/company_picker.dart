import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/hiring_entity_repository.dart';

class CompanyPicker extends ConsumerWidget {
  final String? selectedId;
  final bool locked;
  final ValueChanged<String?> onChanged;
  const CompanyPicker({
    super.key,
    required this.selectedId,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hiringEntityListProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
      data: (entities) => DropdownButtonFormField<String>(
        initialValue: selectedId,
        isExpanded: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final e in entities.where((x) => x.isActive))
            DropdownMenuItem(value: e.id, child: Text(e.name)),
        ],
        onChanged: locked ? null : onChanged,
      ),
    );
  }
}
