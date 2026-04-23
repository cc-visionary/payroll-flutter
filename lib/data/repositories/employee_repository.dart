import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';

class EmployeeRepository {
  final SupabaseClient _client;
  EmployeeRepository(this._client);

  Future<List<Employee>> list({String? search, bool includeArchived = false}) async {
    var q = _client.from('employees').select();
    if (!includeArchived) {
      q = q.isFilter('deleted_at', null);
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q = q.or('first_name.ilike.$s,last_name.ilike.$s,employee_number.ilike.$s');
    }
    final rows = await q.order('employee_number');
    final out = <Employee>[];
    for (final r in rows) {
      try {
        out.add(Employee.fromRow(r as Map<String, dynamic>));
      } catch (e, st) {
        // ignore: avoid_print
        print('Employee.fromRow failed for ${r['id']}: $e\n$st\nrow=$r');
      }
    }
    return out;
  }

  Future<Employee?> byId(String id) async {
    final row = await _client
        .from('employees')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Employee.fromRow(row);
  }

  Future<void> archive(String id) async {
    await _client
        .from('employees')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  Future<void> restore(String id) async {
    await _client.from('employees').update({'deleted_at': null}).eq('id', id);
  }

  Future<Employee> upsert({
    String? id,
    required String companyId,
    required String employeeNumber,
    required String firstName,
    String? middleName,
    required String lastName,
    String? jobTitle,
    String? departmentId,
    String? roleScorecardId,
    String? workEmail,
    String? mobileNumber,
    required String employmentType,
    required String employmentStatus,
    required DateTime hireDate,
    DateTime? regularizationDate,
    bool isRankAndFile = true,
    bool isOtEligible = true,
    bool isNdEligible = true,
    bool isHolidayPayEligible = true,
    // Payroll overrides — only applied when the corresponding `write*` flag is true,
    // so callers without permission don't accidentally null the columns.
    bool writeTaxOnFullEarnings = false,
    bool? taxOnFullEarnings,
    bool writeDeclaredWage = false,
    String? declaredWageOverride, // stringified decimal, null to clear
    String? declaredWageType,
    DateTime? declaredWageEffectiveAt,
    String? declaredWageReason,
    String? declaredWageSetById,
    // Payment routing — which company source account disburses this employee.
    // Only writes when the corresponding `write*` flag is true so existing
    // rows aren't nulled by callers that don't manage these fields.
    bool writePaymentRouting = false,
    String? paymentMethod,
    String? paymentSourceAccount,
    // Statutory employer override — separate write flag because empty string
    // is meaningful here (clears the override / inherits brand allocation).
    bool writeStatutoryEntity = false,
    String? statutoryEntityId,
  }) async {
    final payload = <String, dynamic>{
      if (id != null) 'id': id,
      'company_id': companyId,
      'employee_number': employeeNumber,
      'first_name': firstName,
      'middle_name': middleName,
      'last_name': lastName,
      'job_title': jobTitle,
      'department_id': departmentId,
      'role_scorecard_id': roleScorecardId,
      'work_email': workEmail,
      'mobile_number': mobileNumber,
      'employment_type': employmentType,
      'employment_status': employmentStatus,
      'hire_date': hireDate.toIso8601String().substring(0, 10),
      'regularization_date': regularizationDate?.toIso8601String().substring(0, 10),
      'is_rank_and_file': isRankAndFile,
      'is_ot_eligible': isOtEligible,
      'is_nd_eligible': isNdEligible,
      'is_holiday_pay_eligible': isHolidayPayEligible,
    };
    if (writeTaxOnFullEarnings) {
      payload['tax_on_full_earnings'] = taxOnFullEarnings ?? false;
    }
    if (writeDeclaredWage) {
      payload['declared_wage_override'] = declaredWageOverride;
      payload['declared_wage_type'] = declaredWageType;
      payload['declared_wage_effective_at'] = declaredWageEffectiveAt?.toIso8601String();
      payload['declared_wage_reason'] = declaredWageReason;
      payload['declared_wage_set_by_id'] = declaredWageSetById;
      payload['declared_wage_set_at'] =
          declaredWageOverride == null ? null : DateTime.now().toIso8601String();
    }
    if (writePaymentRouting) {
      payload['payment_method'] = paymentMethod;
      payload['payment_source_account'] = paymentSourceAccount;
    }
    if (writeStatutoryEntity) {
      payload['statutory_entity_id'] = statutoryEntityId;
    }
    Map<String, dynamic> row;
    if (id == null) {
      row = await _client.from('employees').insert(payload).select().single();
    } else {
      row = await _client.from('employees').update(payload).eq('id', id).select().single();
    }
    return Employee.fromRow(row);
  }
}

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => EmployeeRepository(Supabase.instance.client),
);

class EmployeeListQuery {
  final String? search;
  final bool includeArchived;
  const EmployeeListQuery({this.search, this.includeArchived = false});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmployeeListQuery &&
          other.search == search &&
          other.includeArchived == includeArchived);

  @override
  int get hashCode => Object.hash(search, includeArchived);
}

final employeeListProvider =
    FutureProvider.family<List<Employee>, EmployeeListQuery>((ref, q) async {
  final repo = ref.watch(employeeRepositoryProvider);
  return repo.list(search: q.search, includeArchived: q.includeArchived);
});

/// Single-employee fetch used by the profile screen.
final employeeByIdProvider =
    FutureProvider.family<Employee?, String>((ref, id) async {
  final repo = ref.watch(employeeRepositoryProvider);
  return repo.byId(id);
});
