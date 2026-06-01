import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/performance_check_in.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';

class PerformanceCheckInScreen extends ConsumerWidget {
  final String checkInId;
  const PerformanceCheckInScreen({super.key, required this.checkInId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final async = ref.watch(performanceCheckInByIdProvider(checkInId));
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check-in')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Check-in')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Check-in')),
        body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      ),
      data: (c) {
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Check-in')),
            body: const Center(child: Text('Check-in not found.')),
          );
        }
        final isSelf = profile.employeeId == c.employeeId;
        if (!profile.isHrOrAdmin && !isSelf) {
          return Scaffold(
            appBar: AppBar(title: const Text('Check-in')),
            body: const Center(child: Text('You do not have permission to view this check-in.')),
          );
        }
        return _Body(c: c);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final PerformanceCheckIn c;
  const _Body({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeByIdProvider(c.employeeId)).asData?.value;
    final period = ref.watch(checkInPeriodByIdProvider(c.periodId)).asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(employee?.fullName ?? 'Check-in'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/performance'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (period != null) Chip(label: Text(period.periodType)),
              const SizedBox(width: 8),
              Chip(label: Text(c.status)),
              const SizedBox(width: 12),
              if (period != null)
                Text(period.name, style: const TextStyle(fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            Text(
              'Created ${c.createdAt.toIso8601String().substring(0, 10)}'
              '${c.submittedAt != null ? '  ·  Submitted ${c.submittedAt!.toIso8601String().substring(0, 10)}' : ''}'
              '${c.reviewedAt != null ? '  ·  Reviewed ${c.reviewedAt!.toIso8601String().substring(0, 10)}' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Sections land in Tasks 17–21.
            const Text('Self-review, Goals, Skill Ratings, Manager Review, and Status Actions land in Tasks 17–21.'),
          ],
        ),
      ),
    );
  }
}
