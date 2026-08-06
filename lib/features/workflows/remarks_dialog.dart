import 'package:flutter/material.dart';

/// Prompt for the free-text remarks that accompany a workflow action —
/// cancellation reason, approval note, skip reason.
///
/// Returns the entered text, or null when dismissed. When [requireNonEmpty],
/// Confirm stays disabled until something is typed: it used to be enabled and
/// silently swallow the tap on an empty required reason, so "Cancel workflow"
/// looked broken rather than incomplete.
Future<String?> showRemarksDialog(
  BuildContext context,
  String title,
  String label, {
  bool requireNonEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _RemarksDialog(
      title: title,
      label: label,
      requireNonEmpty: requireNonEmpty,
    ),
  );
}

/// Stateful so the dialog owns its controller and disposes it on unmount.
/// Disposing right after `showDialog` resolves is too early — the route is
/// still animating out with the TextField and the Confirm button's listener
/// attached, which throws "A TextEditingController was used after being
/// disposed".
class _RemarksDialog extends StatefulWidget {
  final String title;
  final String label;
  final bool requireNonEmpty;
  const _RemarksDialog({
    required this.title,
    required this.label,
    required this.requireNonEmpty,
  });

  @override
  State<_RemarksDialog> createState() => _RemarksDialogState();
}

class _RemarksDialogState extends State<_RemarksDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _ctl,
          builder: (context, value, child) {
            final ok = !widget.requireNonEmpty || value.text.trim().isNotEmpty;
            return FilledButton(
              onPressed: ok ? () => Navigator.of(context).pop(_ctl.text) : null,
              child: const Text('Confirm'),
            );
          },
        ),
      ],
    );
  }
}
