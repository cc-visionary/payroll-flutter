import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/status_colors.dart';
import '../../../../data/models/development_goal.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/employee_review.dart';
import '../../../../data/models/monthly_development_checkin.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/performance_repository.dart';
import '../../../../data/repositories/review_cycle_repository.dart';

class PerformanceTab extends ConsumerWidget {
  final String employeeId;
  const PerformanceTab({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeByIdProvider(employeeId));
    final managerId = employee.value?.reportsToId;
    final manager = managerId == null
        ? const AsyncValue<Employee?>.data(null)
        : ref.watch(employeeByIdProvider(managerId));
    final reviews = ref.watch(employeeReviewsForEmployeeProvider(employeeId));
    final goals = ref.watch(developmentGoalsForEmployeeProvider(employeeId));
    final checkins = ref.watch(monthlyCheckinsForEmployeeProvider(employeeId));
    return DefaultTabController(
      length: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Reviews'),
              Tab(text: 'Goals'),
              Tab(text: 'Check-ins'),
              Tab(text: 'Development'),
              Tab(text: 'PIP'),
              Tab(text: 'Legacy'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                _Overview(
                  employee: employee,
                  manager: manager,
                  reviews: reviews,
                  goals: goals,
                  checkins: checkins,
                ),
                _Reviews(reviews: reviews),
                _Goals(goals: goals),
                _Checkins(checkins: checkins),
                _Development(goals: goals),
                const _EmptyView(
                  icon: Icons.policy_outlined,
                  title: 'No performance improvement plan',
                  description:
                      'Formal PIPs will appear here once the corrective performance workflow is enabled.',
                ),
                _Legacy(employeeId: employeeId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  final AsyncValue<Employee?> employee;
  final AsyncValue<Employee?> manager;
  final AsyncValue<List<EmployeeReview>> reviews;
  final AsyncValue<List<DevelopmentGoal>> goals;
  final AsyncValue<List<MonthlyDevelopmentCheckin>> checkins;
  const _Overview({
    required this.employee,
    required this.manager,
    required this.reviews,
    required this.goals,
    required this.checkins,
  });

  @override
  Widget build(BuildContext context) {
    if (employee.isLoading ||
        manager.isLoading ||
        reviews.isLoading ||
        goals.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error =
        employee.error ?? manager.error ?? reviews.error ?? goals.error;
    if (error != null) {
      return Center(child: Text('Could not load performance: $error'));
    }
    final person = employee.value;
    final managerName = manager.value?.fullName;
    final reviewRows = reviews.value ?? const [];
    final goalRows = goals.value ?? const [];
    final latest = reviewRows.firstOrNull;
    final activeGoals = goalRows
        .where((goal) => !_closedGoalStatuses.contains(goal.status))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 32,
          runSpacing: 20,
          children: [
            _Fact(
              label: 'Current status',
              value: latest == null ? 'No review' : _label(latest.status),
            ),
            _Fact(
              label: 'Responsibility Card',
              value: person?.roleScorecardId == null
                  ? 'Not assigned'
                  : 'Assigned',
            ),
            _Fact(
              label: 'Direct manager',
              value: person?.reportsToId == null
                  ? 'Not assigned'
                  : managerName ?? 'Assigned',
            ),
            _Fact(
              label: 'Latest rating',
              value: latest?.overallRating == null
                  ? 'Not rated'
                  : '${latest!.overallRating}/5',
            ),
            _Fact(
              label: 'Latest review',
              value: latest == null ? 'None' : _date(latest.reviewPeriodEnd),
            ),
            _Fact(label: 'Active goals', value: '${activeGoals.length}'),
          ],
        ),
        const Divider(height: 48),
        Text(
          'Current development',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (activeGoals.isEmpty)
          const Text('No active development goals.')
        else
          ...activeGoals.map((goal) => _GoalRow(goal: goal)),
        const Divider(height: 48),
        Text('Latest outcome', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (latest == null)
          const Text('No review history yet.')
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${_label(latest.reviewType)} review'),
            subtitle: Text(
              '${_date(latest.reviewPeriodStart)} to ${_date(latest.reviewPeriodEnd)}',
            ),
            trailing: StatusChip(
              label: _label(latest.status),
              tone: toneForStatusString(latest.status),
            ),
            onTap: () => context.push('/performance/reviews/${latest.id}'),
          ),
      ],
    );
  }
}

class _Reviews extends StatelessWidget {
  final AsyncValue<List<EmployeeReview>> reviews;
  const _Reviews({required this.reviews});
  @override
  Widget build(BuildContext context) => reviews.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => Center(child: Text('Could not load reviews: $error')),
    data: (rows) => rows.isEmpty
        ? const _EmptyView(
            icon: Icons.rate_review_outlined,
            title: 'No performance reviews',
            description: 'Generated review-cycle records will appear here.',
          )
        : ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final review = rows[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                title: Text('${_label(review.reviewType)} review'),
                subtitle: Text(
                  '${_date(review.reviewPeriodStart)} to ${_date(review.reviewPeriodEnd)}${review.overallRating == null ? '' : '  •  ${review.overallRating}/5'}',
                ),
                trailing: StatusChip(
                  label: _label(review.status),
                  tone: toneForStatusString(review.status),
                ),
                onTap: () => context.push('/performance/reviews/${review.id}'),
              );
            },
          ),
  );
}

class _Goals extends StatelessWidget {
  final AsyncValue<List<DevelopmentGoal>> goals;
  const _Goals({required this.goals});
  @override
  Widget build(BuildContext context) => goals.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => Center(child: Text('Could not load goals: $error')),
    data: (rows) => rows.isEmpty
        ? const _EmptyView(
            icon: Icons.flag_outlined,
            title: 'No development goals',
            description:
                'Goals created during review finalization will appear here.',
          )
        : ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) => _GoalRow(goal: rows[index]),
          ),
  );
}

class _GoalRow extends StatelessWidget {
  final DevelopmentGoal goal;
  const _GoalRow({required this.goal});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(goal.title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_label(goal.goalType)}  •  Due ${_date(goal.dueDate)}'),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: goal.progress / 100),
      ],
    ),
    trailing: SizedBox(
      width: 110,
      child: Text(
        '${goal.progress}%\n${_label(goal.status)}',
        textAlign: TextAlign.end,
      ),
    ),
  );
}

class _Checkins extends StatelessWidget {
  final AsyncValue<List<MonthlyDevelopmentCheckin>> checkins;
  const _Checkins({required this.checkins});
  @override
  Widget build(BuildContext context) => checkins.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) =>
        Center(child: Text('Could not load check-ins: $error')),
    data: (rows) => rows.isEmpty
        ? const _EmptyView(
            icon: Icons.event_note_outlined,
            title: 'No monthly check-ins',
            description: 'Goal-progress conversations will appear here.',
          )
        : ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final row = rows[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${_date(row.checkinDate)}  •  ${_label(row.generalStatus)}',
                ),
                subtitle: Text(
                  'Next action: ${row.agreedNextAction}\nDue ${_date(row.actionDueDate)}',
                ),
                trailing: Text(
                  '${row.goalUpdates.length} goal update${row.goalUpdates.length == 1 ? '' : 's'}',
                ),
              );
            },
          ),
  );
}

class _Development extends StatelessWidget {
  final AsyncValue<List<DevelopmentGoal>> goals;
  const _Development({required this.goals});
  @override
  Widget build(BuildContext context) => goals.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) =>
        Center(child: Text('Could not load development: $error')),
    data: (rows) {
      final crossTraining = rows
          .where((goal) => goal.goalType == 'CROSS_TRAINING')
          .toList();
      if (crossTraining.isEmpty) {
        return const _EmptyView(
          icon: Icons.swap_horiz,
          title: 'No cross-training pathway',
          description:
              'Cross-training goals and future development tracks will appear here.',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: crossTraining.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (_, index) => _GoalRow(goal: crossTraining[index]),
      );
    },
  );
}

class _Legacy extends ConsumerWidget {
  final String employeeId;
  const _Legacy({required this.employeeId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      performanceCheckInListProvider(
        PerformanceListQuery(employeeId: employeeId),
      ),
    );
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Could not load legacy records: $error')),
      data: (rows) => rows.isEmpty
          ? const _EmptyView(
              icon: Icons.history,
              title: 'No legacy check-ins',
              description: 'Older check-in records remain available here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_label(row.status)),
                  subtitle: Text(
                    'Created ${_date(row.createdAt)}${row.overallRating == null ? '' : '  •  ${row.overallRating}/5'}',
                  ),
                  // push, not go — go replaces the stack and strands the user
                  // with no way back to the employee profile. Matches the new
                  // review rows above.
                  onTap: () => context.push('/performance/${row.id}'),
                );
              },
            ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _EmptyView({
    required this.icon,
    required this.title,
    required this.description,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 36,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

const _closedGoalStatuses = {'COMPLETED', 'CANCELLED', 'CARRIED_FORWARD'};
String _date(DateTime value) => value.toIso8601String().substring(0, 10);
String _label(String value) => value
    .toLowerCase()
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
