import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pagination.dart';
import '../models/employee_review.dart';
import '../models/development_goal.dart';
import '../models/manager_review.dart';
import '../models/monthly_development_checkin.dart';
import '../models/review_cycle.dart';
import '../models/review_kpi_result.dart';
import '../models/review_skill_rating.dart';
import '../models/self_review_request.dart';
import '../models/self_review_submission.dart';

class ReviewCycleActivationResult {
  final int queued;
  final int sent;
  final int failed;
  final List<String> errors;

  const ReviewCycleActivationResult({
    required this.queued,
    required this.sent,
    required this.failed,
    required this.errors,
  });
}

class PerformanceDashboardSnapshot {
  final List<EmployeeReview> reviews;
  final List<ReviewCycle> cycles;
  final List<DevelopmentGoal> goals;
  final int employeesWithoutManager;
  final int employeesWithoutResponsibilityCard;

  const PerformanceDashboardSnapshot({
    required this.reviews,
    required this.cycles,
    required this.goals,
    required this.employeesWithoutManager,
    required this.employeesWithoutResponsibilityCard,
  });

  int reviewsWithStatus(String status) =>
      reviews.where((review) => review.status == status).length;
  int get awaitingSelfReview => reviewsWithStatus('AWAITING_SELF_REVIEW');
  int get pendingManagerReview => reviews
      .where(
        (review) => const {
          'SELF_REVIEW_SUBMITTED',
          'MANAGER_REVIEW_IN_PROGRESS',
          'OVERDUE',
        }.contains(review.status),
      )
      .length;
  int get readyForDiscussion => reviewsWithStatus('READY_FOR_DISCUSSION');

  /// Nothing ever writes the OVERDUE enum value — there is no cron, trigger or
  /// edge function that sets it — so counting rows with that status reported a
  /// permanent 0 and gave HR a false all-clear. Derive it from the cycle's due
  /// dates instead: a review is overdue once the deadline for its current stage
  /// has passed. The stored status is still honoured if anything ever sets it.
  int overdueReviewsAsOf(DateTime now) {
    final byId = {for (final cycle in cycles) cycle.id: cycle};
    return reviews.where((review) {
      if (review.status == 'OVERDUE') return true;
      final cycle = byId[review.reviewCycleId];
      if (cycle == null) return false;
      return switch (review.status) {
        'AWAITING_SELF_REVIEW' => now.isAfter(cycle.selfReviewDueDate),
        'SELF_REVIEW_SUBMITTED' ||
        'MANAGER_REVIEW_IN_PROGRESS' => now.isAfter(cycle.managerReviewDueDate),
        _ => false,
      };
    }).length;
  }

  int get overdueReviews => overdueReviewsAsOf(DateTime.now());
  int get activeGoals => goals
      .where(
        (goal) => !const {
          'COMPLETED',
          'CANCELLED',
          'CARRIED_FORWARD',
        }.contains(goal.status),
      )
      .length;
  int get goalsAtRisk => goals
      .where((goal) => const {'AT_RISK', 'OFF_TRACK'}.contains(goal.status))
      .length;
}

/// The testable core of [ReviewCycleRepository.allReviews]: walks [readPage]
/// via [fetchAllPages] and maps every raw row to an [EmployeeReview].
/// Extracted to a plain, non-private top-level function — rather than left
/// inline against `_client` — so a test can exercise real multi-page
/// concatenation and row-mapping with a fake [readPage] instead of a live
/// Supabase client, which this repository has no seam for otherwise.
Future<List<EmployeeReview>> pagedEmployeeReviews(
  Future<List<Map<String, dynamic>>> Function(int from, int to) readPage,
) async {
  final rows = await fetchAllPages<Map<String, dynamic>>(readPage);
  return rows.map(EmployeeReview.fromRow).toList();
}

class ReviewCycleRepository {
  final SupabaseClient _client;
  ReviewCycleRepository(this._client);

  Future<List<ReviewCycle>> listCycles({String? status}) async {
    var query = _client.from('review_cycles').select();
    if (status != null) query = query.eq('status', status);
    final rows = await query.order('period_start', ascending: false);
    return (rows as List)
        .map((row) => ReviewCycle.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<ReviewCycle?> cycleById(String cycleId) async {
    final row = await _client
        .from('review_cycles')
        .select()
        .eq('id', cycleId)
        .maybeSingle();
    return row == null ? null : ReviewCycle.fromRow(row);
  }

  Future<ReviewCycle> createCycle({
    required String companyId,
    required String name,
    required String reviewType,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime selfReviewDueDate,
    required DateTime managerReviewDueDate,
    DateTime? finalizationDueDate,
    required String larkFormTemplateId,
    required String createdBy,
  }) async {
    String date(DateTime value) => value.toIso8601String().substring(0, 10);
    final row = await _client
        .from('review_cycles')
        .insert({
          'company_id': companyId,
          'name': name.trim(),
          'review_type': reviewType,
          'period_start': date(periodStart),
          'period_end': date(periodEnd),
          'self_review_due_date': date(selfReviewDueDate),
          'manager_review_due_date': date(managerReviewDueDate),
          'finalization_due_date': finalizationDueDate == null
              ? null
              : date(finalizationDueDate),
          'status': 'DRAFT',
          'lark_form_template_id': larkFormTemplateId.trim(),
          'created_by': createdBy,
        })
        .select()
        .single();
    return ReviewCycle.fromRow(row);
  }

  Future<void> updateCycleStatus(String cycleId, String status) async {
    await _client
        .from('review_cycles')
        .update({'status': status})
        .eq('id', cycleId);
  }

  Future<ReviewCycleActivationResult> activateCycle(String cycleId) async {
    final queuedRaw = await _client.rpc(
      'activate_review_cycle',
      params: {'p_review_cycle_id': cycleId},
    );
    final queued = (queuedRaw as num).toInt();
    return _dispatchSelfReviews(cycleId, queued: queued, retryFailed: false);
  }

  Future<ReviewCycleActivationResult> retryFailedSelfReviews(String cycleId) =>
      _dispatchSelfReviews(cycleId, queued: 0, retryFailed: true);

  Future<ReviewCycleActivationResult> _dispatchSelfReviews(
    String cycleId, {
    required int queued,
    required bool retryFailed,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'send-performance-self-reviews',
        body: {'review_cycle_id': cycleId, 'retry_failed': retryFailed},
      );
      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected Lark delivery response: $data');
      }
      return ReviewCycleActivationResult(
        queued: queued,
        sent: (data['sent'] as num?)?.toInt() ?? 0,
        failed: (data['failed'] as num?)?.toInt() ?? 0,
        errors: (data['errors'] as List? ?? const [])
            .map(
              (item) => item is Map
                  ? item['error']?.toString() ?? item.toString()
                  : item.toString(),
            )
            .toList(),
      );
    } on FunctionException catch (error) {
      return ReviewCycleActivationResult(
        queued: queued,
        sent: 0,
        failed: queued,
        errors: [
          'Lark delivery failed (status ${error.status}): '
              '${error.details ?? error.reasonPhrase}',
        ],
      );
    }
  }

  Future<List<SelfReviewRequest>> selfReviewRequestsForCycle(
    String cycleId,
  ) async {
    final rows = await _client
        .from('self_review_requests')
        .select()
        .eq('review_cycle_id', cycleId)
        .order('created_at');
    return (rows as List)
        .map((row) => SelfReviewRequest.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Calls the database transaction that validates assignments and snapshots
  /// the employee's current role. Idempotent for cycle+employee.
  Future<String> generateEmployeeReview({
    required String cycleId,
    required String employeeId,
  }) async {
    final result = await _client.rpc(
      'generate_employee_review',
      params: {'p_review_cycle_id': cycleId, 'p_employee_id': employeeId},
    );
    return result as String;
  }

  Future<List<EmployeeReview>> reviewsForCycle(String cycleId) async {
    final rows = await _client
        .from('employee_reviews')
        .select()
        .eq('review_cycle_id', cycleId)
        .order('employee_name_snapshot');
    return (rows as List)
        .map((row) => EmployeeReview.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<EmployeeReview>> reviewsForEmployee(String employeeId) async {
    final rows = await _client
        .from('employee_reviews')
        .select()
        .eq('employee_id', employeeId)
        .order('review_period_end', ascending: false);
    return (rows as List)
        .map((row) => EmployeeReview.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<EmployeeReview?> reviewById(String reviewId) async {
    final row = await _client
        .from('employee_reviews')
        .select()
        .eq('id', reviewId)
        .maybeSingle();
    return row == null ? null : EmployeeReview.fromRow(row);
  }

  /// Every `employee_reviews` row visible to the caller, unfiltered by cycle
  /// or employee — the bare list `ReviewsCompletedOnTimeSource`
  /// (`kpi_results/automatic_sources.dart`) needs, since it does its own
  /// period/employee filtering over `reviewPeriodEnd` and `finalizedAt`.
  ///
  /// [dashboard] already reads every row for the same reason (its own
  /// counters need the whole table), but bundles cycles, goals and
  /// setup-gap counts around it — work this caller has no use for. A narrow
  /// method matching the KPI source's own `EmployeeReviewsReader` typedef
  /// tears off cleanly for production wiring without pulling in the rest of
  /// that snapshot.
  ///
  /// Paginated via [fetchAllPages] for the same reason [dashboard] is:
  /// `employee_reviews` grows per employee per cycle and can outrun
  /// PostgREST's `max_rows` cap, and a naive `.select()` here would
  /// silently truncate — this KPI source undercounting "reviews due" is
  /// exactly the kind of quiet under-report this whole plan exists to rule
  /// out (see `_status`/attendance's own pagination history for the same
  /// trap in another table).
  /// Roles `employee_reviews_read`'s own RLS policy
  /// (`auth_is_performance_admin_for_cycle`,
  /// 20260717000009_performance_rls_and_cascade_fixes.sql) treats as seeing
  /// every review in the company, not just self/direct-report rows.
  static const _kFullReviewVisibilityRoles = {
    'ADMIN',
    'HR',
    'HR_ADMIN',
    'SUPER_ADMIN',
  };

  /// Whether the CURRENT caller's `app_role` grants full-company visibility
  /// on `employee_reviews`. A caller outside [_kFullReviewVisibilityRoles]
  /// does not get an error from [allReviews] -- RLS silently narrows the
  /// result to that caller's own self/direct-report rows instead of every
  /// row -- so this is the one place that can actually tell "the company has
  /// zero reviews due" apart from "I only saw a slice of what exists".
  /// `auth_app_role()` carries no explicit revoke, so it keeps Postgres'
  /// default PUBLIC execute grant and is callable via `.rpc(...)` with no
  /// migration.
  Future<bool> callerSeesAllReviews() async {
    final role = await _client.rpc('auth_app_role') as String?;
    return _kFullReviewVisibilityRoles.contains(role);
  }

  /// Every review row in the caller's company -- but ONLY once
  /// [callerSeesAllReviews] confirms the caller's role actually grants
  /// full-company visibility. A narrower caller gets `null`, not RLS's own
  /// silently truncated self/direct-report subset:
  /// `ReviewsCompletedOnTimeSource` (automatic_sources.dart) reads `null` as
  /// "cannot certify full visibility" and reports NO_DATA rather than a
  /// plausible-looking partial number. The check has to live here, at the
  /// source of the read against the live database role -- a caller three
  /// files away being reachable only from an HR-gated route is a client-side
  /// navigation guard, not a guarantee about what this query returns.
  Future<List<EmployeeReview>?> allReviews() async {
    if (!await callerSeesAllReviews()) return null;
    return pagedEmployeeReviews((from, to) async {
      final page = await _client
          .from('employee_reviews')
          .select()
          .order('review_period_end', ascending: false)
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
  }

  Future<List<ReviewKpiResult>> kpisForReview(String reviewId) async {
    final rows = await _client
        .from('review_kpi_results')
        .select()
        .eq('review_id', reviewId)
        .order('snapshot_order');
    return (rows as List)
        .map((row) => ReviewKpiResult.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReviewSkillRating>> skillsForReview(String reviewId) async {
    final rows = await _client
        .from('review_skill_ratings')
        .select()
        .eq('review_id', reviewId)
        .order('snapshot_order');
    return (rows as List)
        .map((row) => ReviewSkillRating.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<SelfReviewSubmission>> selfReviewSubmissionsForReview(
    String reviewId,
  ) async {
    final rows = await _client
        .from('self_review_submissions')
        .select()
        .eq('review_id', reviewId)
        .order('version_number', ascending: false);
    return (rows as List)
        .map((row) => SelfReviewSubmission.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<ManagerReview?> managerReviewForReview(String reviewId) async {
    final row = await _client
        .from('manager_reviews')
        .select()
        .eq('review_id', reviewId)
        .maybeSingle();
    return row == null ? null : ManagerReview.fromRow(row);
  }

  Future<void> saveManagerEvaluation({
    required String reviewId,
    required List<Map<String, dynamic>> kpis,
    required List<Map<String, dynamic>> skills,
    required String overallFeedback,
    required String performanceConcerns,
    required String supportManagerWillProvide,
    required String readinessForAdditionalDuties,
    required List<Map<String, dynamic>> strengths,
    required List<Map<String, dynamic>> developmentAreas,
    required double? overallRating,
    required String? recommendedOutcome,
    required bool submit,
  }) async {
    await _client.rpc(
      'save_manager_evaluation',
      params: {
        'p_review_id': reviewId,
        'p_kpis': kpis,
        'p_skills': skills,
        'p_overall_feedback': overallFeedback,
        'p_performance_concerns': performanceConcerns,
        'p_support_manager_will_provide': supportManagerWillProvide,
        'p_readiness_for_additional_duties': readinessForAdditionalDuties,
        'p_strengths': strengths,
        'p_development_areas': developmentAreas,
        'p_overall_rating': overallRating,
        'p_recommended_outcome': recommendedOutcome,
        'p_submit': submit,
      },
    );
  }

  Future<List<DevelopmentGoal>> goalsForReview(String reviewId) async {
    final rows = await _client
        .from('development_goals')
        .select()
        .eq('source_review_id', reviewId)
        .order('due_date');
    return (rows as List)
        .map((row) => DevelopmentGoal.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<DevelopmentGoal>> goalsForEmployee(String employeeId) async {
    final rows = await _client
        .from('development_goals')
        .select()
        .eq('employee_id', employeeId)
        .order('due_date', ascending: false);
    return (rows as List)
        .map((row) => DevelopmentGoal.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> completeDiscussion({
    required String reviewId,
    required DateTime discussionDate,
    required String notes,
  }) async {
    await _client.rpc(
      'complete_review_discussion',
      params: {
        'p_review_id': reviewId,
        'p_discussion_date': discussionDate.toIso8601String().substring(0, 10),
        'p_discussion_notes': notes,
      },
    );
  }

  Future<void> finalizeReview({
    required String reviewId,
    required List<Map<String, dynamic>> goals,
    String? overrideReason,
  }) async {
    await _client.rpc(
      'finalize_employee_review',
      params: {
        'p_review_id': reviewId,
        'p_goals': goals,
        'p_override_reason': overrideReason,
      },
    );
  }

  Future<void> reopenReview({
    required String reviewId,
    required String reason,
  }) async {
    await _client.rpc(
      'reopen_employee_review',
      params: {'p_review_id': reviewId, 'p_reason': reason},
    );
  }

  Future<List<MonthlyDevelopmentCheckin>> monthlyCheckinsForReview(
    String reviewId,
  ) async {
    final rows = await _client
        .from('monthly_development_checkins')
        .select('*, monthly_checkin_goal_updates(*)')
        .eq('source_review_id', reviewId)
        .order('checkin_date', ascending: false);
    return (rows as List)
        .map(
          (row) =>
              MonthlyDevelopmentCheckin.fromRow(row as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<MonthlyDevelopmentCheckin>> monthlyCheckinsForEmployee(
    String employeeId,
  ) async {
    final rows = await _client
        .from('monthly_development_checkins')
        .select('*, monthly_checkin_goal_updates(*)')
        .eq('employee_id', employeeId)
        .order('checkin_date', ascending: false);
    return (rows as List)
        .map(
          (row) =>
              MonthlyDevelopmentCheckin.fromRow(row as Map<String, dynamic>),
        )
        .toList();
  }

  Future<PerformanceDashboardSnapshot> dashboard({
    required bool includeSetupGaps,
  }) async {
    // Both tables grow per employee per cycle, so they outrun the 1000-row
    // Postgrest cap (config.toml max_rows). Truncation here is invisible —
    // the newest rows still arrive — so every dashboard counter would quietly
    // under-report instead of failing.
    final reviewRows = await fetchAllPages<Map<String, dynamic>>((
      from,
      to,
    ) async {
      final page = await _client
          .from('employee_reviews')
          .select()
          .order('review_period_end', ascending: false)
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    final goalRows = await fetchAllPages<Map<String, dynamic>>((
      from,
      to,
    ) async {
      final page = await _client
          .from('development_goals')
          .select()
          .order('due_date')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    // Carries self/manager review due dates so overdueReviewsAsOf can derive
    // what no cron or trigger ever writes.
    final cycleRows = await fetchAllPages<Map<String, dynamic>>((
      from,
      to,
    ) async {
      final page = await _client
          .from('review_cycles')
          .select()
          .order('period_end', ascending: false)
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    var missingManager = 0;
    var missingCard = 0;
    if (includeSetupGaps) {
      final employees = await _client
          .from('employees')
          .select('reports_to_id, role_scorecard_id')
          .isFilter('deleted_at', null);
      for (final row in employees as List) {
        final item = row as Map<String, dynamic>;
        if (item['reports_to_id'] == null) missingManager++;
        if (item['role_scorecard_id'] == null) missingCard++;
      }
    }
    return PerformanceDashboardSnapshot(
      reviews: reviewRows.map(EmployeeReview.fromRow).toList(),
      cycles: cycleRows.map(ReviewCycle.fromRow).toList(),
      goals: goalRows.map(DevelopmentGoal.fromRow).toList(),
      employeesWithoutManager: missingManager,
      employeesWithoutResponsibilityCard: missingCard,
    );
  }

  Future<String> recordMonthlyCheckin({
    required String reviewId,
    required DateTime checkinDate,
    required String whatWentWell,
    required String needsAttention,
    required String supportNeeded,
    required String agreedNextAction,
    required String actionOwnerId,
    required DateTime actionDueDate,
    required String generalStatus,
    required List<Map<String, dynamic>> goalUpdates,
  }) async {
    String date(DateTime value) => value.toIso8601String().substring(0, 10);
    final result = await _client.rpc(
      'record_monthly_development_checkin',
      params: {
        'p_review_id': reviewId,
        'p_checkin_date': date(checkinDate),
        'p_what_went_well': whatWentWell,
        'p_needs_attention': needsAttention,
        'p_support_needed': supportNeeded,
        'p_agreed_next_action': agreedNextAction,
        'p_action_owner_id': actionOwnerId,
        'p_action_due_date': date(actionDueDate),
        'p_general_status': generalStatus,
        'p_goal_updates': goalUpdates,
      },
    );
    return result as String;
  }
}

final reviewCycleRepositoryProvider = Provider<ReviewCycleRepository>(
  (ref) => ReviewCycleRepository(Supabase.instance.client),
);

final reviewCycleListProvider = FutureProvider<List<ReviewCycle>>(
  (ref) => ref.watch(reviewCycleRepositoryProvider).listCycles(),
);

final reviewCycleProvider = FutureProvider.family<ReviewCycle?, String>(
  (ref, cycleId) => ref.watch(reviewCycleRepositoryProvider).cycleById(cycleId),
);

final employeeReviewsForCycleProvider =
    FutureProvider.family<List<EmployeeReview>, String>(
      (ref, cycleId) =>
          ref.watch(reviewCycleRepositoryProvider).reviewsForCycle(cycleId),
    );

final employeeReviewsForEmployeeProvider =
    FutureProvider.family<List<EmployeeReview>, String>(
      (ref, employeeId) => ref
          .watch(reviewCycleRepositoryProvider)
          .reviewsForEmployee(employeeId),
    );

final employeeReviewProvider = FutureProvider.family<EmployeeReview?, String>(
  (ref, reviewId) =>
      ref.watch(reviewCycleRepositoryProvider).reviewById(reviewId),
);

final reviewKpisProvider = FutureProvider.family<List<ReviewKpiResult>, String>(
  (ref, reviewId) =>
      ref.watch(reviewCycleRepositoryProvider).kpisForReview(reviewId),
);

final reviewSkillsProvider =
    FutureProvider.family<List<ReviewSkillRating>, String>(
      (ref, reviewId) =>
          ref.watch(reviewCycleRepositoryProvider).skillsForReview(reviewId),
    );

final selfReviewSubmissionsProvider =
    FutureProvider.family<List<SelfReviewSubmission>, String>(
      (ref, reviewId) => ref
          .watch(reviewCycleRepositoryProvider)
          .selfReviewSubmissionsForReview(reviewId),
    );

final managerReviewProvider = FutureProvider.family<ManagerReview?, String>(
  (ref, reviewId) =>
      ref.watch(reviewCycleRepositoryProvider).managerReviewForReview(reviewId),
);

final developmentGoalsForReviewProvider =
    FutureProvider.family<List<DevelopmentGoal>, String>(
      (ref, reviewId) =>
          ref.watch(reviewCycleRepositoryProvider).goalsForReview(reviewId),
    );

final developmentGoalsForEmployeeProvider =
    FutureProvider.family<List<DevelopmentGoal>, String>(
      (ref, employeeId) =>
          ref.watch(reviewCycleRepositoryProvider).goalsForEmployee(employeeId),
    );

final monthlyDevelopmentCheckinsProvider =
    FutureProvider.family<List<MonthlyDevelopmentCheckin>, String>(
      (ref, reviewId) => ref
          .watch(reviewCycleRepositoryProvider)
          .monthlyCheckinsForReview(reviewId),
    );

final monthlyCheckinsForEmployeeProvider =
    FutureProvider.family<List<MonthlyDevelopmentCheckin>, String>(
      (ref, employeeId) => ref
          .watch(reviewCycleRepositoryProvider)
          .monthlyCheckinsForEmployee(employeeId),
    );

final performanceDashboardProvider =
    FutureProvider.family<PerformanceDashboardSnapshot, bool>(
      (ref, includeSetupGaps) => ref
          .watch(reviewCycleRepositoryProvider)
          .dashboard(includeSetupGaps: includeSetupGaps),
    );

final selfReviewRequestsForCycleProvider =
    FutureProvider.family<List<SelfReviewRequest>, String>(
      (ref, cycleId) => ref
          .watch(reviewCycleRepositoryProvider)
          .selfReviewRequestsForCycle(cycleId),
    );
