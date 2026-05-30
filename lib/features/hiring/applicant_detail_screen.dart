import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/profile_provider.dart';
import '../../data/models/applicant.dart';
import '../../data/repositories/applicant_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import 'applicant_status.dart';
import 'widgets/reject_dialog.dart';

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
    final scorecard = a.roleScorecardId == null
        ? null
        : scorecards.where((s) => s.id == a.roleScorecardId).firstOrNull;
    final jobTitle = scorecard?.jobTitle;
    final entity = a.hiringEntityId == null
        ? null
        : entities.where((e) => e.id == a.hiringEntityId).firstOrNull;
    final entityName = entity?.name;
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
            const SizedBox(height: 16),
            _StatusActionsBar(a: a),
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

class _StatusActionsBar extends ConsumerWidget {
  final Applicant a;
  const _StatusActionsBar({required this.a});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = (kApplicantTransitions[a.status] ?? const <String>{}).toList()..sort();
    if (allowed.isEmpty) {
      return Text('Terminal status — no further transitions.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return Row(children: [
      Text('Move to:',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(width: 12),
      for (final s in allowed)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: OutlinedButton(
            onPressed: () => _transitionTo(context, ref, s),
            child: Text(s),
          ),
        ),
    ]);
  }

  Future<void> _transitionTo(BuildContext context, WidgetRef ref, String target) async {
    final reasonField = requiresReason(target: target);
    String? reason;
    if (reasonField != null) {
      if (target == 'REJECTED') {
        reason = await showRejectDialog(context, a.fullName);
      } else {
        reason = await _basicReasonPrompt(context, reasonField);
      }
      if (reason == null) return;
    }
    final profile = ref.read(userProfileProvider).asData!.value!;
    final repo = ref.read(applicantRepositoryProvider);
    try {
      await repo.upsert(
        id: a.id,
        companyId: a.companyId,
        firstName: a.firstName,
        middleName: a.middleName,
        lastName: a.lastName,
        suffix: a.suffix,
        email: a.email,
        phoneNumber: a.phoneNumber,
        mobileNumber: a.mobileNumber,
        roleScorecardId: a.roleScorecardId!,
        departmentId: a.departmentId,
        hiringEntityId: a.hiringEntityId,
        source: a.source,
        referredById: a.referredById,
        linkedinUrl: a.linkedinUrl,
        portfolioUrl: a.portfolioUrl,
        expectedSalaryMin: a.expectedSalaryMin?.toString(),
        expectedSalaryMax: a.expectedSalaryMax?.toString(),
        expectedStartDate: a.expectedStartDate,
        status: target,
        notes: a.notes,
        rejectionReason: target == 'REJECTED' ? reason : a.rejectionReason,
        withdrawalReason: target == 'WITHDRAWN' ? reason : a.withdrawalReason,
        setByUserId: profile.userId,
      );
      if (!context.mounted) return;
      ref.invalidate(applicantByIdProvider(a.id));
      ref.invalidate(applicantListProvider);
      ref.invalidate(applicantsCountByStatusProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status change failed: $e')),
      );
    }
  }
}

Future<String?> _basicReasonPrompt(BuildContext context, String label) async {
  final ctl = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctl,
          decoration: InputDecoration(labelText: label),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  } finally {
    ctl.dispose();
  }
}
