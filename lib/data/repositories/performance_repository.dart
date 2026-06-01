import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
