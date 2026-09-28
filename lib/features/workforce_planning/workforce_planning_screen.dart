import 'package:flutter/material.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import 'tabs/all_tasks_tab.dart';
import 'tabs/drivers_scenario_tab.dart';
import 'tabs/organization_tab.dart';
import 'tabs/roles_board_tab.dart';

/// Workforce Planning hub. HR/Admin-only (route guard in app/router.dart also
/// redirects).
///
/// Three tabs, each answering a different question — no two overlap:
///   Roles        — who does what: every role, its people and its work, with
///                  load; drag a task to another role to plan a move
///   Organization — the reporting shape with load (the org)
///   All tasks    — find any task: the searchable inventory and its costing
///
/// Every task belongs to exactly one role; a role's holders share its load.
/// Drivers & rates live off the tab bar in a settings dialog: they are
/// configuration read by the other tabs, not a view of the workforce.
class WorkforcePlanningScreen extends StatelessWidget {
  const WorkforcePlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mobile = isMobile(context);
    return DefaultTabController(
      length: 3,
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
              Tab(text: 'Roles'),
              Tab(text: 'Organization'),
              Tab(text: 'All tasks'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            RolesBoardTab(),
            OrganizationTab(),
            AllTasksTab(),
          ],
        ),
      ),
    );
  }
}
