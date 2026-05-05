import 'package:flutter/material.dart';

class ViolationsEditor extends StatelessWidget {
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  const ViolationsEditor({
    super.key,
    required this.items,
    required this.onChanged,
  });

  void _add() => onChanged([...items, '']);
  void _remove(int i) {
    final next = [...items]..removeAt(i);
    onChanged(next);
  }

  void _set(int i, String s) {
    final next = [...items];
    next[i] = s;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: items[i],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'e.g., Code of Conduct §3.1',
                    ),
                    onChanged: (s) => _set(i, s),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _remove(i),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add violation'),
        ),
      ],
    );
  }
}
