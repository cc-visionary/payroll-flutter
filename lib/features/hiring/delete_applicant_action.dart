import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/applicant.dart';
import '../../data/repositories/applicant_repository.dart';

/// Confirms, then removes [a] from the hiring pipeline (soft delete).
/// Returns true when the applicant was removed.
///
/// Applicants already converted to an employee are refused: the employee
/// record links back to them, and removing a hire is an employee-side action.
Future<bool> confirmAndDeleteApplicant(
  BuildContext context,
  WidgetRef ref,
  Applicant a,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (a.convertedToEmployeeId != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${a.fullName} has already been hired and can no longer be removed '
          'from the pipeline.',
        ),
      ),
    );
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove applicant?'),
      content: Text(
        'Remove ${a.fullName} from the hiring pipeline? They will no longer '
        'appear in the Talent Pool or any listing.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref.read(applicantRepositoryProvider).softDelete(a.id);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Remove failed: $e')));
    return false;
  }
  ref.invalidate(applicantListProvider);
  ref.invalidate(applicantsCountByStatusProvider);
  ref.invalidate(applicantByIdProvider(a.id));
  messenger.showSnackBar(SnackBar(content: Text('Removed ${a.fullName}.')));
  return true;
}
