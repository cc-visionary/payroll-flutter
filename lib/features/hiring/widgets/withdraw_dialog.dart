import 'package:flutter/material.dart';

Future<String?> showWithdrawDialog(
  BuildContext context,
  String applicantName,
) async {
  final ctl = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Withdraw $applicantName?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Capture why the candidate withdrew — declined offer, accepted elsewhere, etc.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Withdrawal reason',
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
            onPressed: () {
              final r = ctl.text.trim();
              if (r.isEmpty) return;
              Navigator.of(ctx).pop(r);
            },
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
  } finally {
    ctl.dispose();
  }
}
