import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/models/applicant.dart';
import '../../data/repositories/applicant_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import '../auth/profile_provider.dart';
import 'widgets/applicant_card.dart';

class HiringScreen extends ConsumerWidget {
  const HiringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.isHrOrAdmin ?? false;
    if (!canManage) {
      return Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(title: const Text('Hiring')),
        body: const Center(
          child: Text('You do not have permission to view applicants.'),
        ),
      );
    }
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Hiring'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => context.go('/hiring/new'),
              icon: const Icon(Icons.add),
              label: const Text('New applicant'),
            ),
          ),
        ],
      ),
      body: _KanbanBody(),
    );
  }
}

const _kPipelineColumns = <String>[
  'NEW',
  'SCREENING',
  'INTERVIEW',
  'ASSESSMENT',
  'OFFER',
  'OFFER_ACCEPTED',
  'HIRED',
];
const _kTerminalColumns = <String>['REJECTED', 'WITHDRAWN'];

class _KanbanBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(applicantListProvider(const ApplicantListQuery()));
    final asyncScorecards = ref.watch(roleScorecardListProvider);
    final asyncEntities = ref.watch(hiringEntityListProvider);
    return asyncList.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (applicants) {
        final jobById = <String, String>{
          for (final s in asyncScorecards.asData?.value ?? const [])
            s.id: s.jobTitle,
        };
        final entityById = <String, String>{
          for (final e in asyncEntities.asData?.value ?? const [])
            e.id: e.name,
        };
        final grouped = <String, List<Applicant>>{};
        for (final a in applicants) {
          grouped.putIfAbsent(a.status, () => []).add(a);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final col in [..._kPipelineColumns, ..._kTerminalColumns])
                _KanbanColumn(
                  status: col,
                  applicants: grouped[col] ?? const [],
                  jobById: jobById,
                  entityById: entityById,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final String status;
  final List<Applicant> applicants;
  final Map<String, String> jobById;
  final Map<String, String> entityById;
  const _KanbanColumn({
    required this.status,
    required this.applicants,
    required this.jobById,
    required this.entityById,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Text(status,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    )),
                const Spacer(),
                Text('${applicants.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final a in applicants)
            ApplicantCard(
              applicant: a,
              jobTitle: a.roleScorecardId == null ? null : jobById[a.roleScorecardId!],
              entityName: a.hiringEntityId == null ? null : entityById[a.hiringEntityId!],
            ),
        ],
      ),
    );
  }
}
