import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/role_scorecard_repository.dart';

/// Autocomplete field suggesting role/job titles. Suggests from the active
/// `role_scorecards.job_title` list as the user types; free-text is still
/// accepted (for ad-hoc positions or external hires whose role isn't on
/// the scorecard list yet).
///
/// Same controller-managed pattern as `EmployeeNameField`: external value
/// only re-seeds the controller when the user isn't actively editing.
class RoleTitleField extends ConsumerStatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final String? labelText;
  const RoleTitleField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.labelText,
  });

  @override
  ConsumerState<RoleTitleField> createState() => _RoleTitleFieldState();
}

class _RoleTitleFieldState extends ConsumerState<RoleTitleField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  late final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(RoleTitleField oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final async = ref.watch(roleScorecardListProvider);
    final titles = async.asData?.value
            .map((c) => c.jobTitle)
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList() ??
        const <String>[];

    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return titles.take(8);
        return titles.where((t) => t.toLowerCase().contains(q)).take(8);
      },
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText:
                widget.hintText ?? 'Type or select from responsibility cards',
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
      onSelected: widget.onChanged,
    );
  }
}
