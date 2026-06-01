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
