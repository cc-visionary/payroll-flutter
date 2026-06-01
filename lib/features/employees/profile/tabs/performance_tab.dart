import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/performance_repository.dart';

class PerformanceTab extends ConsumerWidget {
  final String employeeId;
  const PerformanceTab({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(performanceCheckInListProvider(
      PerformanceListQuery(employeeId: employeeId),
    ));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No performance check-ins yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final c = rows[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('Status: ${c.status}'),
                subtitle: Text(
                  'Created ${c.createdAt.toIso8601String().substring(0, 10)}'
                  '${c.overallRating != null ? '  ·  Overall: ${c.overallRating}/5' : ''}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                onTap: () => context.go('/performance/${c.id}'),
              ),
            );
          },
        );
      },
    );
  }
}
