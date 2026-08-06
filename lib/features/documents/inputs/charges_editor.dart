import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../templates/nte_inputs.dart';
import 'quill_field.dart';

class ChargesEditor extends StatelessWidget {
  final List<NteCharge> charges;
  final ValueChanged<List<NteCharge>> onChanged;
  const ChargesEditor({
    super.key,
    required this.charges,
    required this.onChanged,
  });

  void _add() {
    onChanged([...charges, NteCharge(title: '', body: Delta()..insert('\n'))]);
  }

  void _remove(int idx) {
    final next = [...charges]..removeAt(idx);
    onChanged(next);
  }

  void _set(int idx, NteCharge c) {
    final next = [...charges];
    next[idx] = c;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < charges.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: charges[i].title,
                        decoration: InputDecoration(
                          labelText: 'Charge ${i + 1} title',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (s) =>
                            _set(i, NteCharge(title: s, body: charges[i].body)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => _remove(i),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                QuillField(
                  initial: charges[i].body,
                  onChanged: (d) =>
                      _set(i, NteCharge(title: charges[i].title, body: d)),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add charge'),
        ),
      ],
    );
  }
}
