import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/employee.dart';
import '../../data/models/workforce_planning.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/workforce_planning_repository.dart';
import 'balance_rows.dart';

final wpPersonLoadsProvider = FutureProvider<List<WpPersonLoad>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).personLoads());

final wpNodesProvider = FutureProvider<List<WpNode>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).nodes());

final wpDriversProvider = FutureProvider<List<WpDriver>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).drivers());

final wpRatesProvider = FutureProvider<List<WpRate>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).rates());

final wpConfigProvider = FutureProvider<WpConfig?>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).config());

final wpTasksProvider = FutureProvider<List<WpTask>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).tasks());

final wpActiveEmployeesProvider = FutureProvider<List<Employee>>((ref) =>
    ref.watch(employeeListProvider(const EmployeeListQuery()).future));

final wpKpiCountByEmployeeProvider = FutureProvider<Map<String, int>>((ref) async {
  final byKpi = await ref.watch(kpiAssignedEmployeesProvider.future);
  return kpiCountByEmployee(byKpi);
});

/// The stored growth multiplier (default 1.0 when no config row yet). Kept
/// separate so the Balance/Role-View tabs can watch just the number.
final wpGrowthMultiplierProvider = Provider<double>((ref) =>
    ref.watch(wpConfigProvider).asData?.value?.growthMultiplier ?? 1.0);
