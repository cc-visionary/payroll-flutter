import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/status_colors.dart';
import '../../data/models/review_cycle.dart';
import '../../data/repositories/review_cycle_repository.dart';

class ReviewCyclesScreen extends ConsumerWidget {
  const ReviewCyclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cycles = ref.watch(reviewCycleListProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to performance',
          onPressed: () => context.go('/performance'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Review cycles'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => context.go('/performance/review-cycles/new'),
              icon: const Icon(Icons.add),
              label: const Text('New cycle'),
            ),
          ),
        ],
      ),
      body: cycles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(
          icon: Icons.error_outline,
          title: 'Review cycles could not be loaded',
          detail: error.toString(),
        ),
        data: (rows) => rows.isEmpty
            ? _Message(
                icon: Icons.event_note_outlined,
                title: 'No review cycles yet',
                detail:
                    'Create a quarterly, probationary, or PIP review cycle to begin.',
                action: FilledButton(
                  onPressed: () => context.go('/performance/review-cycles/new'),
                  child: const Text('Create first cycle'),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.refresh(reviewCycleListProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _CycleRow(cycle: rows[index]),
                ),
              ),
      ),
    );
  }
}

class _CycleRow extends StatelessWidget {
  final ReviewCycle cycle;
  const _CycleRow({required this.cycle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      title: Text(
        cycle.name,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          '${_label(cycle.reviewType)}  •  ${_date(cycle.periodStart)} to ${_date(cycle.periodEnd)}  •  Self-review due ${_date(cycle.selfReviewDueDate)}',
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(
            label: _label(cycle.status),
            tone: toneForStatusString(cycle.status),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => context.go('/performance/review-cycles/${cycle.id}'),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    ),
  );
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);
String _label(String value) => value
    .toLowerCase()
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
