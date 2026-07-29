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

/// A self-eval response flattened with the employee context needed for the
/// HR Excel export (name, department, position, employment type).
class SelfEvalExportRow {
  final String reviewType;
  final DateTime? submittedAt;
  final String employeeNumber;
  final String firstName;
  final String lastName;
  final String? departmentName;
  final String? jobTitle;
  final String? employmentType;
  final Map<String, dynamic> answers;
  final Map<String, dynamic> ratings;

  const SelfEvalExportRow({
    required this.reviewType,
    this.submittedAt,
    required this.employeeNumber,
    required this.firstName,
    required this.lastName,
    this.departmentName,
    this.jobTitle,
    this.employmentType,
    required this.answers,
    required this.ratings,
  });

  String get fullName => [firstName, lastName]
      .where((s) => s.trim().isNotEmpty)
      .join(' ')
      .trim();
}

/// Fetch every self-eval response for [companyId] joined with employee context,
/// newest first. Two round-trips: responses, then employee meta (with the
/// department name embedded via the `employees.department_id -> departments` FK).
/// Mirrors the batch-fetch style of `buildBrandSheetsFromCurrentFilter`.
Future<List<SelfEvalExportRow>> fetchSelfEvalsForExport(String companyId) async {
  final client = Supabase.instance.client;
  final respRows = await client
      .from('lark_self_eval_responses')
      .select('employee_id, review_type, submitted_at, answers, ratings')
      .eq('company_id', companyId)
      .order('submitted_at', ascending: false);
  final responses = respRows.cast<Map<String, dynamic>>().toList();
  if (responses.isEmpty) return const [];

  final empIds = responses
      .map((r) => r['employee_id'] as String?)
      .whereType<String>()
      .toSet()
      .toList();
  final empRows = await client
      .from('employees')
      .select(
          'id, employee_number, first_name, last_name, job_title, employment_type, departments(name)')
      .inFilter('id', empIds);
  final empById = <String, Map<String, dynamic>>{
    for (final e in empRows.cast<Map<String, dynamic>>()) e['id'] as String: e,
  };

  Map<String, dynamic> asMap(Object? v) => v is Map
      ? v.map((k, value) => MapEntry('$k', value))
      : <String, dynamic>{};

  return responses.map((r) {
    final emp = empById[r['employee_id']] ?? const <String, dynamic>{};
    // To-one embed: a Map (or null), not a List.
    final dept = emp['departments'];
    final submitted = r['submitted_at'] as String?;
    return SelfEvalExportRow(
      reviewType: r['review_type'] as String? ?? '',
      submittedAt: submitted == null ? null : DateTime.tryParse(submitted),
      employeeNumber: emp['employee_number'] as String? ?? '',
      firstName: emp['first_name'] as String? ?? '',
      lastName: emp['last_name'] as String? ?? '',
      departmentName: dept is Map ? dept['name'] as String? : null,
      jobTitle: emp['job_title'] as String?,
      employmentType: emp['employment_type'] as String?,
      answers: asMap(r['answers']),
      ratings: asMap(r['ratings']),
    );
  }).toList();
}

/// A single self-eval response joined with the employee context needed for the
/// printable PDF header (name, employee number, department, position).
class SelfEvalDetail {
  final LarkSelfEvalResponse response;
  final String employeeNumber;
  final String firstName;
  final String lastName;
  final String? departmentName;
  final String? jobTitle;

  const SelfEvalDetail({
    required this.response,
    required this.employeeNumber,
    required this.firstName,
    required this.lastName,
    this.departmentName,
    this.jobTitle,
  });

  String get fullName => [firstName, lastName]
      .where((s) => s.trim().isNotEmpty)
      .join(' ')
      .trim();
}

/// Fetch one self-eval response by [responseId], joined with employee context
/// for the printable header. Two round-trips (response, then employee meta with
/// the department name embedded via the `employees.department_id -> departments`
/// FK), mirroring [fetchSelfEvalsForExport]. Returns null when the id is not
/// found or RLS hides it. Exposed as a family keyed by response id for the
/// self-eval PDF screen.
final selfEvalDetailByIdProvider =
    FutureProvider.family<SelfEvalDetail?, String>((ref, responseId) async {
  final client = Supabase.instance.client;
  final row = await client
      .from('lark_self_eval_responses')
      .select(
          'id, review_type, source_table, submitted_at, answers, ratings, employee_id')
      .eq('id', responseId)
      .maybeSingle();
  if (row == null) return null;

  final response = LarkSelfEvalResponse.fromRow(row);
  final employeeId = row['employee_id'] as String?;
  Map<String, dynamic> emp = const <String, dynamic>{};
  if (employeeId != null) {
    final empRow = await client
        .from('employees')
        .select(
            'employee_number, first_name, last_name, job_title, departments(name)')
        .eq('id', employeeId)
        .maybeSingle();
    if (empRow != null) emp = empRow;
  }
  // To-one embed: a Map (or null), not a List.
  final dept = emp['departments'];
  return SelfEvalDetail(
    response: response,
    employeeNumber: emp['employee_number'] as String? ?? '',
    firstName: emp['first_name'] as String? ?? '',
    lastName: emp['last_name'] as String? ?? '',
    departmentName: dept is Map ? dept['name'] as String? : null,
    jobTitle: emp['job_title'] as String?,
  );
});
