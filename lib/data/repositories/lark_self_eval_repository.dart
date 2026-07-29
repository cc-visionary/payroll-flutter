import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A single synced self-evaluation response (Lark form -> app). Written by the
/// `sync-lark-self-evals` edge function into `lark_self_eval_responses`.
class LarkSelfEvalResponse {
  final String id;
  final String reviewType;
  final String? sourceTable;
  final DateTime? submittedAt;

  /// Free-text answers keyed by question label.
  final Map<String, dynamic> answers;

  /// Numeric ratings keyed by question label.
  final Map<String, dynamic> ratings;

  const LarkSelfEvalResponse({
    required this.id,
    required this.reviewType,
    this.sourceTable,
    this.submittedAt,
    required this.answers,
    required this.ratings,
  });

  factory LarkSelfEvalResponse.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> asMap(Object? v) => v is Map
        ? v.map((k, value) => MapEntry('$k', value))
        : <String, dynamic>{};
    final submitted = row['submitted_at'] as String?;
    return LarkSelfEvalResponse(
      id: row['id'] as String,
      reviewType: row['review_type'] as String? ?? '',
      sourceTable: row['source_table'] as String?,
      submittedAt: submitted == null ? null : DateTime.tryParse(submitted),
      answers: asMap(row['answers']),
      ratings: asMap(row['ratings']),
    );
  }
}

/// Self-eval responses for one employee, newest first. RLS scopes reads to the
/// caller's company and HR/performance-admin role.
final selfEvalResponsesForEmployeeProvider =
    FutureProvider.family<List<LarkSelfEvalResponse>, String>(
        (ref, employeeId) async {
  final rows = await Supabase.instance.client
      .from('lark_self_eval_responses')
      .select('id, review_type, source_table, submitted_at, answers, ratings')
      .eq('employee_id', employeeId)
      .order('submitted_at', ascending: false);
  return rows
      .cast<Map<String, dynamic>>()
      .map(LarkSelfEvalResponse.fromRow)
      .toList();
});
