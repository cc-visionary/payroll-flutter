import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/employee.dart';
import '../../data/models/workforce_planning.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/workforce_planning_repository.dart';

final wpPersonLoadsProvider = FutureProvider<List<WpPersonLoad>>(
  (ref) => ref.watch(workforcePlanningRepositoryProvider).personLoads(),
);

final wpNodesProvider = FutureProvider<List<WpNode>>(
  (ref) => ref.watch(workforcePlanningRepositoryProvider).nodes(),
);

final wpDriversProvider = FutureProvider<List<WpDriver>>(
  (ref) => ref.watch(workforcePlanningRepositoryProvider).drivers(),
);

final wpRatesProvider = FutureProvider<List<WpRate>>(
  (ref) => ref.watch(workforcePlanningRepositoryProvider).rates(),
);

final wpConfigProvider = FutureProvider<WpConfig?>(
  (ref) => ref.watch(workforcePlanningRepositoryProvider).config(),
);

/// All computed task rows (hours per task) — the hours the Roles board, the
/// needs-attention strip and All tasks read for every task.
final wpAllTaskComputedProvider = FutureProvider<List<WpTaskComputed>>(
  (ref) => ref.watch(workforcePlanningRepositoryProvider).allTaskComputed(),
);

final wpTasksProvider = FutureProvider<List<WpTask>>(
  (ref) => ref.watch(workforcePlanningRepositoryProvider).tasks(),
);

final wpTaskAssignmentsProvider = FutureProvider<List<WpTaskAssignment>>(
  (ref) => ref.watch(workforcePlanningRepositoryProvider).taskAssignments(),
);

/// Assignment rows grouped by task. No longer read for load (the role is the
/// only "who"); kept for the workbench's Archive-vs-Delete gate — a task with
/// assignment history is archived, never hard-deleted (ruling R7).
final wpAssignmentsByTaskProvider =
    FutureProvider<Map<String, List<WpTaskAssignment>>>((ref) async {
      final all = await ref.watch(wpTaskAssignmentsProvider.future);
      final byTask = <String, List<WpTaskAssignment>>{};
      for (final a in all) {
        (byTask[a.taskId] ??= []).add(a);
      }
      return byTask;
    });

final wpActiveEmployeesProvider = FutureProvider<List<Employee>>(
  (ref) => ref.watch(employeeListProvider(const EmployeeListQuery()).future),
);

/// The stored growth multiplier (default 1.0 when no config row yet). Kept
/// separate so the Roles board and needs-attention strip can watch just the
/// number.
final wpGrowthMultiplierProvider = Provider<double>(
  (ref) => ref.watch(wpConfigProvider).asData?.value?.growthMultiplier ?? 1.0,
);
