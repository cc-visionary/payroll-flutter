import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workflow_instance.dart';
import '../models/workflow_step.dart';

/// Filter parameters for the workflows list. Mirrors ApplicantListQuery shape.
class WorkflowListQuery {
  final List<String>? statuses;   // null = all; default in UI = exclude CANCELLED
  final List<String>? types;       // null = all workflow_types
  final String? employeeId;
  const WorkflowListQuery({this.statuses, this.types, this.employeeId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkflowListQuery &&
          _eq(statuses, other.statuses) &&
          _eq(types, other.types) &&
          employeeId == other.employeeId;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(statuses ?? const []),
        Object.hashAll(types ?? const []),
        employeeId,
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

class WorkflowRepository {
  final SupabaseClient _client;
  WorkflowRepository(this._client);
}

final workflowRepositoryProvider =
    Provider<WorkflowRepository>((ref) => WorkflowRepository(Supabase.instance.client));
