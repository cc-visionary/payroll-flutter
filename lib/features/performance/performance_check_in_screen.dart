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
            _GoalsSection(c: c),
            const SizedBox(height: 24),
            _SkillsSection(c: c),
            const SizedBox(height: 24),
            const Text('Manager Review and Status Actions land in Tasks 20–21.'),
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

class _GoalsSection extends ConsumerWidget {
  final PerformanceCheckIn c;
  const _GoalsSection({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(checkInGoalsProvider(c.id));
    final profile = ref.watch(userProfileProvider).asData!.value!;
    final canEditAll = profile.isHrOrAdmin || profile.userId == c.reviewerId;
    final canEditSelf = profile.employeeId == c.employeeId && c.status == 'DRAFT';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Goals',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const Spacer(),
              if (canEditAll || canEditSelf)
                TextButton.icon(
                  onPressed: () => _addGoal(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add goal'),
                ),
            ]),
            const SizedBox(height: 12),
            goals.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Text('No goals set yet.');
                }
                return Column(
                  children: [
                    for (final g in rows)
                      _GoalRow(
                        goal: g,
                        canEditAll: canEditAll,
                        canEditSelf: canEditSelf,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addGoal(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add goal'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Goal title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (ctl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(ctl.text.trim());
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (title == null) return;
      await ref.read(performanceRepositoryProvider).addGoal(
            checkInId: c.id,
            goalType: 'PERFORMANCE',
            title: title,
          );
      ref.invalidate(checkInGoalsProvider(c.id));
    } finally {
      ctl.dispose();
    }
  }
}

class _GoalRow extends ConsumerStatefulWidget {
  final dynamic goal;
  final bool canEditAll;
  final bool canEditSelf;
  const _GoalRow({required this.goal, required this.canEditAll, required this.canEditSelf});
  @override
  ConsumerState<_GoalRow> createState() => _GoalRowState();
}

class _GoalRowState extends ConsumerState<_GoalRow> {
  @override
  Widget build(BuildContext context) {
    final g = widget.goal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(g.title as String,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                Chip(label: Text(g.goalType as String)),
                const SizedBox(width: 8),
                Chip(label: Text(g.status as String)),
                if (widget.canEditAll)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete goal',
                    onPressed: () => _delete(context),
                  ),
              ]),
              const SizedBox(height: 8),
              Text('Progress: ${g.progress}%',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (g.description != null && (g.description as String).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(g.description as String,
                    style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this goal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(performanceRepositoryProvider).deleteGoal(widget.goal.id as String);
    ref.invalidate(checkInGoalsProvider(widget.goal.checkInId as String));
  }
}

class _SkillsSection extends ConsumerWidget {
  final PerformanceCheckIn c;
  const _SkillsSection({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(skillRatingsProvider(c.id));
    final profile = ref.watch(userProfileProvider).asData!.value!;
    final isSelf = profile.employeeId == c.employeeId;
    final isReviewer = profile.userId == c.reviewerId;
    final canManage = profile.isHrOrAdmin || isReviewer;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Skill Ratings',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const Spacer(),
              if (canManage)
                TextButton.icon(
                  onPressed: () => _addSkill(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add skill'),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              'KPI skills auto-seeded from the role scorecard at check-in creation. '
              'HR can add ad-hoc competencies (behavioral, technical, etc.).',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            skills.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Text('No skills tracked yet.');
                }
                return Column(
                  children: [
                    for (final s in rows)
                      _SkillRow(
                        skill: s,
                        canEditSelf: isSelf && c.status == 'DRAFT',
                        canEditManager: canManage && c.status != 'COMPLETED' && c.status != 'SKIPPED',
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSkill(BuildContext context, WidgetRef ref) async {
    final nameCtl = TextEditingController();
    final categoryCtl = TextEditingController(text: 'BEHAVIORAL');
    try {
      final result = await showDialog<({String category, String name})>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add skill'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: categoryCtl,
                decoration: const InputDecoration(labelText: 'Category (e.g. BEHAVIORAL, TECHNICAL)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Skill name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtl.text.trim();
                final cat = categoryCtl.text.trim();
                if (name.isEmpty || cat.isEmpty) return;
                Navigator.of(ctx).pop((category: cat, name: name));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (result == null) return;
      await ref.read(performanceRepositoryProvider).addSkill(
            checkInId: c.id,
            skillCategory: result.category,
            skillName: result.name,
          );
      ref.invalidate(skillRatingsProvider(c.id));
    } finally {
      nameCtl.dispose();
      categoryCtl.dispose();
    }
  }
}

class _SkillRow extends ConsumerStatefulWidget {
  final dynamic skill;
  final bool canEditSelf;
  final bool canEditManager;
  const _SkillRow({
    required this.skill,
    required this.canEditSelf,
    required this.canEditManager,
  });
  @override
  ConsumerState<_SkillRow> createState() => _SkillRowState();
}

class _SkillRowState extends ConsumerState<_SkillRow> {
  @override
  Widget build(BuildContext context) {
    final s = widget.skill;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Chip(label: Text(s.skillCategory as String)),
                const SizedBox(width: 8),
                Expanded(child: Text(s.skillName as String,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                if (widget.canEditManager && (s.skillCategory as String) != 'KPI')
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Remove skill',
                    onPressed: () => _delete(context),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _RatingPicker(
                    label: 'Self',
                    value: s.selfRating as int?,
                    enabled: widget.canEditSelf,
                    onChanged: (v) => _update(selfRating: v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RatingPicker(
                    label: 'Manager',
                    value: s.managerRating as int?,
                    enabled: widget.canEditManager,
                    onChanged: (v) => _update(managerRating: v),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _update({int? selfRating, int? managerRating}) async {
    await ref.read(performanceRepositoryProvider).updateSkill(
          skillId: widget.skill.id as String,
          selfRating: selfRating,
          managerRating: managerRating,
        );
    ref.invalidate(skillRatingsProvider(widget.skill.checkInId as String));
  }

  Future<void> _delete(BuildContext context) async {
    await ref.read(performanceRepositoryProvider).deleteSkill(widget.skill.id as String);
    ref.invalidate(skillRatingsProvider(widget.skill.checkInId as String));
  }
}

class _RatingPicker extends StatelessWidget {
  final String label;
  final int? value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const _RatingPicker({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Row(children: [
          for (var i = 1; i <= 5; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text('$i'),
                selected: value == i,
                onSelected: enabled ? (_) => onChanged(i) : null,
              ),
            ),
        ]),
      ],
    );
  }
}
