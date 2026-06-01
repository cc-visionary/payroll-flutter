import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/performance/check_in_status.dart';
import '../models/check_in_period.dart';
import '../models/check_in_goal.dart';
import '../models/performance_check_in.dart';
import '../models/skill_rating.dart';

/// Filter parameters for the performance list. Mirrors WorkflowListQuery shape.
class PerformanceListQuery {
  final String? periodId;
  final String? employeeId;
  final List<String>? statuses;
  const PerformanceListQuery({this.periodId, this.employeeId, this.statuses});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerformanceListQuery &&
          periodId == other.periodId &&
          employeeId == other.employeeId &&
          _eq(statuses, other.statuses);

  @override
  int get hashCode => Object.hash(
        periodId,
        employeeId,
        Object.hashAll(statuses ?? const []),
      );

  static bool _eq(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class PerformanceRepository {
  final SupabaseClient _client;
  PerformanceRepository(this._client);

  Future<List<PerformanceCheckIn>> list(PerformanceListQuery q) async {
    var builder = _client.from('performance_check_ins').select('*');
    if (q.periodId != null) {
      builder = builder.eq('period_id', q.periodId!);
    }
    if (q.employeeId != null) {
      builder = builder.eq('employee_id', q.employeeId!);
    }
    if (q.statuses != null && q.statuses!.isNotEmpty) {
      builder = builder.inFilter('status', q.statuses!);
    }
    final rows = await builder.order('created_at', ascending: false);
    return (rows as List)
        .map((r) => PerformanceCheckInFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<PerformanceCheckIn?> byId(String id) async {
    final row = await _client
        .from('performance_check_ins')
        .select('*')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return PerformanceCheckInFromRow.fromRow(row);
  }

  Future<CheckInPeriod?> periodById(String periodId) async {
    final row = await _client
        .from('check_in_periods')
        .select('*')
        .eq('id', periodId)
        .maybeSingle();
    if (row == null) return null;
    return CheckInPeriodFromRow.fromRow(row);
  }

  Future<List<CheckInGoal>> goalsFor(String checkInId) async {
    final rows = await _client
        .from('check_in_goals')
        .select('*')
        .eq('check_in_id', checkInId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => CheckInGoalFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<SkillRating>> skillRatingsFor(String checkInId) async {
    final rows = await _client
        .from('skill_ratings')
        .select('*')
        .eq('check_in_id', checkInId)
        .order('skill_category', ascending: true);
    return (rows as List)
        .map((r) => SkillRatingFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Idempotent. Returns the period id for the current calendar quarter.
  /// If a row with the same (company_id, name, target_employee_id=null)
  /// already exists, returns its id without creating a duplicate.
  Future<String> ensureQuarterlyPeriodForCurrentQuarter({
    required String companyId,
    required DateTime now,
  }) async {
    final quarter = ((now.month - 1) ~/ 3) + 1;
    final startMonth = (quarter - 1) * 3 + 1;
    final start = DateTime.utc(now.year, startMonth, 1);
    final endMonthStart = DateTime.utc(now.year, startMonth + 3, 1);
    final end = endMonthStart.subtract(const Duration(days: 1));
    final due = end.add(const Duration(days: 15));
    final name = '${now.year} Q$quarter';

    final existing = await _client
        .from('check_in_periods')
        .select('id')
        .eq('company_id', companyId)
        .eq('name', name)
        .isFilter('target_employee_id', null)
        .maybeSingle();
    if (existing != null) {
      return existing['id'] as String;
    }

    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    final inserted = await _client
        .from('check_in_periods')
        .insert({
          'company_id': companyId,
          'name': name,
          'period_type': 'QUARTERLY',
          'start_date': iso(start),
          'end_date': iso(end),
          'due_date': iso(due),
          'is_active': true,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// For each probationary milestone (1M / 3M / 5M from hire_date) that has
  /// passed (milestone date ≤ now), ensure a per-employee period exists.
  /// Returns the list of period ids (one per applicable milestone).
  ///
  /// Idempotent — uses the (company_id, name, target_employee_id) unique
  /// constraint to avoid duplicates.
  Future<List<String>> ensureProbationaryPeriodsForEmployee({
    required String companyId,
    required String employeeId,
    required String employeeFullName,
    required DateTime hireDate,
    required DateTime now,
  }) async {
    final ids = <String>[];
    const milestones = <(int months, String type, String label)>[
      (1, 'PROBATION_1M', '1M'),
      (3, 'PROBATION_3M', '3M'),
      (5, 'PROBATION_5M', '5M'),
    ];

    String iso(DateTime d) => d.toIso8601String().substring(0, 10);

    for (final (months, type, label) in milestones) {
      final milestoneDate = _addMonths(hireDate, months);
      if (milestoneDate.isAfter(now)) continue; // milestone not yet reached

      final name = 'Probation $label — $employeeFullName';

      final existing = await _client
          .from('check_in_periods')
          .select('id')
          .eq('company_id', companyId)
          .eq('name', name)
          .eq('target_employee_id', employeeId)
          .maybeSingle();
      if (existing != null) {
        ids.add(existing['id'] as String);
        continue;
      }

      // Window: opens 14 days before milestone, ends at milestone,
      // due 7 days after.
      final start = milestoneDate.subtract(const Duration(days: 14));
      final end = milestoneDate;
      final due = milestoneDate.add(const Duration(days: 7));

      final inserted = await _client
          .from('check_in_periods')
          .insert({
            'company_id': companyId,
            'name': name,
            'period_type': type,
            'start_date': iso(start),
            'end_date': iso(end),
            'due_date': iso(due),
            'is_active': true,
            'target_employee_id': employeeId,
          })
          .select('id')
          .single();
      ids.add(inserted['id'] as String);
    }
    return ids;
  }

  /// Idempotent. Returns the check-in id for (period, employee). Inserts a
  /// new DRAFT row if none exists, defaulting `reviewer_id` to the employee's
  /// manager (if provided). Does NOT seed skill_ratings — call
  /// `seedSkillRatingsForCheckIn` separately.
  Future<String> ensureCheckInForEmployeeInPeriod({
    required String periodId,
    required String employeeId,
    String? reviewerId,
  }) async {
    final existing = await _client
        .from('performance_check_ins')
        .select('id')
        .eq('period_id', periodId)
        .eq('employee_id', employeeId)
        .maybeSingle();
    if (existing != null) {
      return existing['id'] as String;
    }
    final inserted = await _client
        .from('performance_check_ins')
        .insert({
          'period_id': periodId,
          'employee_id': employeeId,
          'reviewer_id': reviewerId,
          'status': 'DRAFT',
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Auto-seed skill_ratings from the employee's RoleScorecard KPIs. Reads
  /// the scorecard's `kpis` jsonb array; each KPI.metric becomes a skill_name
  /// row with skill_category='KPI'. Idempotent via the (check_in_id,
  /// skill_category, skill_name) unique constraint — already-seeded rows
  /// stay untouched.
  ///
  /// Snapshotted at this moment: subsequent KPI edits do NOT propagate to
  /// existing check-ins. This is intentional (historical record stability).
  Future<void> seedSkillRatingsForCheckIn({
    required String checkInId,
    required String? roleScorecardId,
  }) async {
    if (roleScorecardId == null) return;
    final scorecard = await _client
        .from('role_scorecards')
        .select('kpis')
        .eq('id', roleScorecardId)
        .maybeSingle();
    if (scorecard == null) return;
    final rawKpis = scorecard['kpis'];
    if (rawKpis is! List) return;

    // Read existing skill_names to avoid PK violations on the unique constraint.
    final existing = await _client
        .from('skill_ratings')
        .select('skill_name')
        .eq('check_in_id', checkInId)
        .eq('skill_category', 'KPI');
    final existingNames = <String>{
      for (final r in (existing as List))
        ((r as Map<String, dynamic>)['skill_name'] as String?) ?? '',
    };

    final toInsert = <Map<String, dynamic>>[];
    for (final k in rawKpis) {
      if (k is! Map) continue;
      final metric = k['metric'] as String?;
      if (metric == null || metric.isEmpty) continue;
      if (existingNames.contains(metric)) continue;
      toInsert.add({
        'check_in_id': checkInId,
        'skill_category': 'KPI',
        'skill_name': metric,
      });
    }
    if (toInsert.isNotEmpty) {
      await _client.from('skill_ratings').insert(toInsert);
    }
  }

  /// Partial update of check-in fields. When `status` is set and differs from
  /// the prior value, validates the transition and stamps submitted_at /
  /// reviewed_at as appropriate.
  Future<void> updateCheckIn({
    required String checkInId,
    String? status,
    String? accomplishments,
    String? challenges,
    String? learnings,
    String? supportNeeded,
    String? managerFeedback,
    String? strengths,
    String? areasForImprovement,
    int? overallRating,
    String? overallComments,
  }) async {
    final payload = <String, dynamic>{};
    if (accomplishments case final a?) payload['accomplishments'] = a;
    if (challenges case final c?) payload['challenges'] = c;
    if (learnings case final l?) payload['learnings'] = l;
    if (supportNeeded case final s?) payload['support_needed'] = s;
    if (managerFeedback case final m?) payload['manager_feedback'] = m;
    if (strengths case final s?) payload['strengths'] = s;
    if (areasForImprovement case final a?) payload['areas_for_improvement'] = a;
    if (overallRating case final r?) payload['overall_rating'] = r;
    if (overallComments case final c?) payload['overall_comments'] = c;

    if (status != null) {
      final prior = await _client
          .from('performance_check_ins')
          .select('status')
          .eq('id', checkInId)
          .maybeSingle();
      final priorStatus = prior?['status'] as String?;
      if (priorStatus != null && priorStatus != status) {
        validateCheckInTransition(from: priorStatus, to: status);
      }
      payload['status'] = status;
      final now = DateTime.now().toIso8601String();
      if (status == 'SUBMITTED') payload['submitted_at'] = now;
      if (status == 'COMPLETED') payload['reviewed_at'] = now;
    }

    if (payload.isEmpty) return;
    await _client.from('performance_check_ins').update(payload).eq('id', checkInId);
  }

  Future<String> addGoal({
    required String checkInId,
    required String goalType,
    required String title,
    String? description,
    DateTime? targetDate,
  }) async {
    final iso = targetDate?.toIso8601String().substring(0, 10);
    final row = await _client
        .from('check_in_goals')
        .insert({
          'check_in_id': checkInId,
          'goal_type': goalType,
          'title': title,
          'description': description,
          'target_date': iso,
          'progress': 0,
          'status': 'IN_PROGRESS',
          'carry_forward': false,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateGoal({
    required String goalId,
    String? title,
    String? description,
    DateTime? targetDate,
    int? progress,
    String? status,
    String? selfAssessment,
    String? managerAssessment,
    int? rating,
    bool? carryForward,
  }) async {
    final payload = <String, dynamic>{};
    if (title case final t?) payload['title'] = t;
    if (description case final d?) payload['description'] = d;
    if (targetDate case final t?) payload['target_date'] = t.toIso8601String().substring(0, 10);
    if (progress case final p?) payload['progress'] = p;
    if (status case final s?) payload['status'] = s;
    if (selfAssessment case final s?) payload['self_assessment'] = s;
    if (managerAssessment case final m?) payload['manager_assessment'] = m;
    if (rating case final r?) payload['rating'] = r;
    if (carryForward case final c?) payload['carry_forward'] = c;
    if (payload.isEmpty) return;
    await _client.from('check_in_goals').update(payload).eq('id', goalId);
  }

  Future<void> deleteGoal(String goalId) async {
    await _client.from('check_in_goals').delete().eq('id', goalId);
  }

  Future<String> addSkill({
    required String checkInId,
    required String skillCategory,
    required String skillName,
  }) async {
    final row = await _client
        .from('skill_ratings')
        .insert({
          'check_in_id': checkInId,
          'skill_category': skillCategory,
          'skill_name': skillName,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateSkill({
    required String skillId,
    int? selfRating,
    int? managerRating,
    String? comments,
    String? developmentPlan,
  }) async {
    final payload = <String, dynamic>{};
    if (selfRating case final s?) payload['self_rating'] = s;
    if (managerRating case final m?) payload['manager_rating'] = m;
    if (comments case final c?) payload['comments'] = c;
    if (developmentPlan case final d?) payload['development_plan'] = d;
    if (payload.isEmpty) return;
    await _client.from('skill_ratings').update(payload).eq('id', skillId);
  }

  Future<void> deleteSkill(String skillId) async {
    await _client.from('skill_ratings').delete().eq('id', skillId);
  }

  /// Private clone of the pure helper so this file doesn't depend on the
  /// features layer (model files are in lib/data/, repositories should not
  /// depend on lib/features/). Inlined intentionally.
  DateTime _addMonths(DateTime d, int months) {
    var year = d.year;
    var month = d.month + months;
    while (month > 12) {
      month -= 12;
      year += 1;
    }
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    final lastDayOfTarget =
        DateTime.utc(year, month + 1, 1).subtract(const Duration(days: 1)).day;
    final day = d.day > lastDayOfTarget ? lastDayOfTarget : d.day;
    return DateTime.utc(year, month, day);
  }
}

final performanceRepositoryProvider = Provider<PerformanceRepository>(
    (ref) => PerformanceRepository(Supabase.instance.client));

final performanceCheckInListProvider =
    FutureProvider.family<List<PerformanceCheckIn>, PerformanceListQuery>(
        (ref, q) => ref.read(performanceRepositoryProvider).list(q));

final performanceCheckInByIdProvider =
    FutureProvider.family<PerformanceCheckIn?, String>(
        (ref, id) => ref.read(performanceRepositoryProvider).byId(id));

final checkInPeriodByIdProvider =
    FutureProvider.family<CheckInPeriod?, String>(
        (ref, id) => ref.read(performanceRepositoryProvider).periodById(id));

final checkInGoalsProvider = FutureProvider.family<List<CheckInGoal>, String>(
    (ref, checkInId) => ref.read(performanceRepositoryProvider).goalsFor(checkInId));

final skillRatingsProvider = FutureProvider.family<List<SkillRating>, String>(
    (ref, checkInId) => ref.read(performanceRepositoryProvider).skillRatingsFor(checkInId));
