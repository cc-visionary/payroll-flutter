import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/employee_repository.dart';

/// Autocomplete field suggesting employee full-names. Suggests from the active
/// employee list as the user types; free-text is still accepted (for
/// external consultants or names not on the roster).
///
/// Uses `RawAutocomplete` with an externally-managed `TextEditingController`
/// so the field keeps focus while typing AND can be re-seeded by the
/// parent when autofill brings in a new value.
class EmployeeNameField extends ConsumerStatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final String? labelText;
  final List<String> exclude;
  const EmployeeNameField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.labelText,
    this.exclude = const [],
  });

  @override
  ConsumerState<EmployeeNameField> createState() => _EmployeeNameFieldState();
}

class _EmployeeNameFieldState extends ConsumerState<EmployeeNameField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  late final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(EmployeeNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only sync external value into the controller when the user isn't
    // actively editing this field. Avoids cursor jumps and focus loss
    // mid-typing. Triggered by parent autofill propagating a fresh value.
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(employeeListProvider(const EmployeeListQuery()));
    final excludeLc = widget.exclude
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final names = async.asData?.value
            .map((e) => e.fullName)
            .where((n) => n.isNotEmpty && !excludeLc.contains(n.toLowerCase()))
            .toList() ??
        const <String>[];

    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return names.take(8);
        return names.where((n) => n.toLowerCase().contains(q)).take(8);
      },
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText ?? 'Type or select an employee',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: widget.onChanged,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 480),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (sel) {
        widget.onChanged(sel);
      },
    );
  }
}
