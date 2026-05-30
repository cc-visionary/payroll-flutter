import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/profile_provider.dart';
import '../../data/models/applicant.dart';
import '../../data/repositories/applicant_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/hiring_entity_repository.dart';

class ApplicantDetailScreen extends ConsumerWidget {
  final String applicantId;
  const ApplicantDetailScreen({super.key, required this.applicantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (!(profile?.isHrOrAdmin ?? false)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Applicant')),
        body: const Center(child: Text('You do not have permission.')),
      );
    }
    final asyncApplicant = ref.watch(applicantByIdProvider(applicantId));
    return asyncApplicant.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Applicant')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Applicant')),
        body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      ),
      data: (a) {
        if (a == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Applicant')),
            body: const Center(child: Text('Applicant not found.')),
          );
        }
        return _Body(a: a);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final Applicant a;
  const _Body({required this.a});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scorecards = ref.watch(roleScorecardListProvider).asData?.value ?? const [];
    final entities = ref.watch(hiringEntityListProvider).asData?.value ?? const [];
    final jobTitle = a.roleScorecardId == null
        ? null
        : scorecards.firstWhere(
            (s) => s.id == a.roleScorecardId,
            orElse: () => scorecards.first,
          ).jobTitle;
    final entityName = a.hiringEntityId == null
        ? null
        : entities.firstWhere(
            (e) => e.id == a.hiringEntityId,
            orElse: () => entities.first,
          ).name;
    return Scaffold(
      appBar: AppBar(
        title: Text(a.fullName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/hiring'),
        ),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.go('/hiring/${a.id}/edit'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Chip(label: Text(a.status)),
              const SizedBox(width: 12),
              if (jobTitle != null) Text(jobTitle, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 12),
              if (entityName != null)
                Text('• $entityName',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 24),
            // Actions row — Status dropdown + Generate Offer + Convert all land in Tasks 17–19, 24, 26.
            _DetailField('Email', a.email),
            if (a.phoneNumber != null) _DetailField('Phone', a.phoneNumber!),
            if (a.mobileNumber != null) _DetailField('Mobile', a.mobileNumber!),
            if (a.source != null) _DetailField('Source', a.source!),
            if (a.expectedSalaryMin != null || a.expectedSalaryMax != null)
              _DetailField(
                'Expected salary',
                '${a.expectedSalaryMin ?? '?'} — ${a.expectedSalaryMax ?? '?'}',
              ),
            if (a.expectedStartDate != null)
              _DetailField('Expected start',
                  a.expectedStartDate!.toIso8601String().substring(0, 10)),
            _DetailField('Applied', a.appliedAt.toIso8601String().substring(0, 10)),
            _DetailField('Status changed',
                a.statusChangedAt.toIso8601String().substring(0, 16)),
            if (a.notes != null) ...[
              const SizedBox(height: 16),
              const Text('Notes',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(a.notes!),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  final String label;
  final String value;
  const _DetailField(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
