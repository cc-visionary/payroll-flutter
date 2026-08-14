import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PostgREST codes that mean "the schema this code expects is not there yet".
///
/// `PGRST205` is a missing table, `PGRST204` a missing column. Both are what a
/// screen gets when its migration has been committed but not yet applied —
/// this repo hands migrations to a human to run with `supabase db push`, so
/// there is always a window where the code is ahead of the database.
const _pendingMigrationCodes = {'PGRST205', 'PGRST204'};

/// True when [error] is PostgREST telling us the table or column is absent.
///
/// Deliberately narrow: a genuine permission error, a network failure or a
/// constraint violation must NOT be dressed up as "not set up yet", or a real
/// fault gets a reassuring message and nobody investigates.
bool isPendingMigrationError(Object error) {
  if (error is! PostgrestException) return false;
  return _pendingMigrationCodes.contains(error.code);
}

/// What a screen shows when its tables do not exist yet.
///
/// The raw `PostgrestException(message: Could not find the table
/// 'public.kpi_results' in the schema cache, code: PGRST205, ...)` is accurate
/// and useless: it reads as a crash, and its own hint ("perhaps you meant
/// public.review_kpi_results") points somewhere unrelated and misleading. The
/// actual situation is ordinary and expected — the feature shipped, its
/// migration has not been applied — so say that, name what to run, and keep
/// the raw text available underneath for whoever needs it.
class PendingMigrationNotice extends StatelessWidget {
  const PendingMigrationNotice({
    super.key,
    required this.error,
    required this.feature,
  });

  /// The original error, shown verbatim in the expandable detail.
  final Object error;

  /// What is unavailable, in the user's words — "KPI results", not a table
  /// name. Someone reading this screen did not choose the schema.
  final String feature;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!isPendingMigrationError(error)) {
      return Center(
        child: Text('Error: $error', style: TextStyle(color: cs.error)),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schema_outlined, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '$feature is not set up yet',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The database changes this feature needs have not been applied. '
              'An administrator needs to run the pending migrations '
              '(supabase db push), then reopen this page.',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Kept, not hidden: whoever runs the migration will want the exact
            // code, and burying it entirely would trade one unhelpful screen
            // for another.
            ExpansionTile(
              title: const Text('Technical details'),
              tilePadding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SelectableText(
                    '$error',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
