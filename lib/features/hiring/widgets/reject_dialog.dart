import 'package:flutter/material.dart';

/// Returns the entered reason on Confirm; null on Cancel.
Future<String?> showRejectDialog(BuildContext context, String applicantName) async {
  final ctl = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject $applicantName?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Provide a reason. This is stored on the applicant and surfaces in the detail view.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Rejection reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              final r = ctl.text.trim();
              if (r.isEmpty) return; // require a reason
              Navigator.of(ctx).pop(r);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  } finally {
    ctl.dispose();
  }
}
