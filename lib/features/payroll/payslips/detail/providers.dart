import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/attendance_day.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../../data/repositories/payroll_repository.dart';

/// Raw joined payslip detail: payslip row + lines + employee + pay period +
/// payroll run. Exposed as a Map so the UI can render without a separate
/// typed model layer.
final payslipDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, payslipId) {
  return ref.watch(payrollRepositoryProvider).payslipDetailById(payslipId);
});

class AttendanceForPayslipKey {
  final String employeeId;
  final DateTime from;
  final DateTime to;
  const AttendanceForPayslipKey({
    required this.employeeId,
    required this.from,
    required this.to,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttendanceForPayslipKey &&
          other.employeeId == employeeId &&
          other.from == from &&
          other.to == to);

  @override
  int get hashCode => Object.hash(employeeId, from, to);
}

final attendanceForPayslipProvider =
    FutureProvider.family<List<AttendanceDay>, AttendanceForPayslipKey>(
        (ref, k) {
  return ref.watch(attendanceRepositoryProvider).listByRange(
        start: k.from,
        end: k.to,
        employeeId: k.employeeId,
      );
});

class ManualAdjustmentsKey {
  final String runId;
  final String employeeId;
  const ManualAdjustmentsKey({required this.runId, required this.employeeId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ManualAdjustmentsKey &&
          other.runId == runId &&
          other.employeeId == employeeId);

  @override
  int get hashCode => Object.hash(runId, employeeId);
}

final manualAdjustmentsProvider = FutureProvider.family<
    List<Map<String, dynamic>>, ManualAdjustmentsKey>((ref, k) {
  return ref
      .watch(payrollRepositoryProvider)
      .manualAdjustments(k.runId, k.employeeId);
});
