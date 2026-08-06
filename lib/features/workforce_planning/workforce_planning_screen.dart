import 'package:flutter/material.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import 'tabs/balance_tab.dart';
import 'tabs/drivers_scenario_tab.dart';
import 'tabs/role_view_tab.dart';
import 'tabs/structure_tab.dart';
import 'tabs/tasks_tab.dart';
import 'tabs/unassigned_tab.dart';

/// Workforce Planning hub. HR/Admin-only (route guard in app/router.dart also
/// redirects).
///
/// Five tabs, each answering a different question — no two overlap:
///   Balance   — plan and rebalance PEOPLE (drag work between them)
///   Roles     — cost and load per ROLE CARD (compare roles, whoever holds them)
///   Structure — reporting shape with load (the org)
///   Tasks     — the inventory and its costing (the data)
///   Unassigned — work that reaches nobody: archive, assign, or draft a role
///
/// Drivers & rates moved off the tab bar into a settings dialog: they are
/// configuration read by the other tabs, not a view of the workforce.
/// See docs/superpowers/specs/2026-07-19-workforce-capacity-planning-design.md.
class WorkforcePlanningScreen extends StatelessWidget {
  const WorkforcePlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mobile = isMobile(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        drawer: mobile ? const AppDrawer() : null,
        appBar: AppBar(
          title: const Text('Workforce Planning'),
          actions: [
            IconButton(
              tooltip: 'Drivers, rates & scenario',
              icon: const Icon(Icons.tune),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 1000,
                      maxHeight: 720,
                    ),
                    child: Column(
                      children: [
                        AppBar(
                          title: const Text('Drivers, rates & scenario'),
                          automaticallyImplyLeading: false,
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const Expanded(child: DriversScenarioTab()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Balance'),
              Tab(text: 'Roles'),
              Tab(text: 'Structure'),
              Tab(text: 'Tasks'),
              Tab(text: 'Unassigned'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            BalanceTab(),
            RoleViewTab(),
            StructureTab(),
            TasksTab(),
            UnassignedTab(),
          ],
        ),
      ),
    );
  }
}
