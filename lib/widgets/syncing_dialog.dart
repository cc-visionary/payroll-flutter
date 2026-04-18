import 'package:flutter/material.dart';

/// Simple modal dialog with a spinner + "Syncing <label>..." text.
/// Blocks until manually popped by the caller.
class SyncingDialog extends StatelessWidget {
  final String label;
  const SyncingDialog({super.key, required this.label});
  @override
  Widget build(BuildContext context) => AlertDialog(
        content: SizedBox(
          width: 300,
          child: Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Expanded(child: Text('Syncing $label...')),
          ]),
        ),
      );
}

/// Wraps any async action with a "Syncing..." modal. Dialog shows until the
/// future resolves (success or error). Returns the future's result or rethrows.
Future<T> runWithSyncingDialog<T>(
  BuildContext context,
  String label,
  Future<T> Function() action,
) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => SyncingDialog(label: label),
  );
  try {
    final result = await action();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return result;
  } catch (_) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    rethrow;
  }
}
