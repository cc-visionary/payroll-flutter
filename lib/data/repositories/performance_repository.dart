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
}

final performanceRepositoryProvider = Provider<PerformanceRepository>(
    (ref) => PerformanceRepository(Supabase.instance.client));
