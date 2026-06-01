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
            _SelfReviewSection(c: c),
            const SizedBox(height: 24),
            // Goals + Skill Ratings + Manager Review + Status Actions land in Tasks 18–21.
            const Text('Goals, Skill Ratings, Manager Review, and Status Actions land in Tasks 18–21.'),
          ],
        ),
      ),
    );
  }
}

class _SelfReviewSection extends ConsumerStatefulWidget {
  final PerformanceCheckIn c;
  const _SelfReviewSection({required this.c});
  @override
  ConsumerState<_SelfReviewSection> createState() => _SelfReviewSectionState();
}

class _SelfReviewSectionState extends ConsumerState<_SelfReviewSection> {
  late final TextEditingController _accomplishments;
  late final TextEditingController _challenges;
  late final TextEditingController _learnings;
  late final TextEditingController _supportNeeded;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accomplishments = TextEditingController(text: widget.c.accomplishments ?? '');
    _challenges = TextEditingController(text: widget.c.challenges ?? '');
    _learnings = TextEditingController(text: widget.c.learnings ?? '');
    _supportNeeded = TextEditingController(text: widget.c.supportNeeded ?? '');
  }

  @override
  void dispose() {
    _accomplishments.dispose();
    _challenges.dispose();
    _learnings.dispose();
    _supportNeeded.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(performanceRepositoryProvider).updateCheckIn(
            checkInId: widget.c.id,
            accomplishments: _accomplishments.text,
            challenges: _challenges.text,
            learnings: _learnings.text,
            supportNeeded: _supportNeeded.text,
          );
      ref.invalidate(performanceCheckInByIdProvider(widget.c.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Self-review saved.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.c.status != 'DRAFT';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Self-review',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 12),
            TextField(
              controller: _accomplishments,
              readOnly: readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Accomplishments',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _challenges,
              readOnly: readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Challenges',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _learnings,
              readOnly: readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Learnings',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supportNeeded,
              readOnly: readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Support needed',
                border: OutlineInputBorder(),
              ),
            ),
            if (!readOnly) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save self-review'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
