import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import 'tabs/balance_tab.dart';
import 'tabs/drivers_scenario_tab.dart';
import 'tabs/role_view_tab.dart';
import 'tabs/structure_tab.dart';
import 'tabs/tasks_tab.dart';

/// Workforce Planning hub. HR/Admin-only (route guard in app/router.dart also
/// redirects). Five tabs; Balance + Role View are live, the rest are filled by
/// later plans. See docs/superpowers/specs/2026-07-19-workforce-capacity-planning-design.md.
class WorkforcePlanningScreen extends ConsumerWidget {
  const WorkforcePlanningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mobile = isMobile(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        drawer: mobile ? const AppDrawer() : null,
        appBar: AppBar(
          title: const Text('Workforce Planning'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Balance'),
              Tab(text: 'Role View'),
              Tab(text: 'Structure'),
              Tab(text: 'Tasks'),
              Tab(text: 'Drivers & Scenario'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            BalanceTab(),
            RoleViewTab(),
            StructureTab(),
            TasksTab(),
            DriversScenarioTab(),
          ],
        ),
      ),
    );
  }
}
