import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/employee_repository.dart';
import 'tabs/attendance_tab.dart';
import 'tabs/documents_tab.dart';
import 'tabs/financials_tab.dart';
import 'tabs/payslips_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/role_tab.dart';
import 'tabs/timeline_tab.dart';
import 'widgets/profile_header.dart';

/// Read-first employee profile screen (view, not edit).
/// Matches the UI in the provided screenshots: back link, name header with
/// status chips + action buttons, four info cards, then seven tabs.
class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ProfileTabBarDelegate({required this.child});
  static const double _h = 49;
  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox(height: _h, child: child);
  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) =>
      oldDelegate.child != child;
}

class EmployeeProfileScreen extends ConsumerWidget {
  final String employeeId;
  const EmployeeProfileScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeeByIdProvider(employeeId));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
          ),
        ),
        data: (employee) {
          if (employee == null) {
            return const Center(child: Text('Employee not found.'));
          }
          return DefaultTabController(
            length: 7,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ProfileHeader(employee: employee),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ProfileTabBarDelegate(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            labelStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            unselectedLabelStyle:
                                const TextStyle(fontSize: 14),
                            indicatorSize: TabBarIndicatorSize.label,
                            tabs: const [
                              Tab(text: 'Profile'),
                              Tab(text: 'Attendance'),
                              Tab(text: 'Payslips'),
                              Tab(text: 'Role & Responsibilities'),
                              Tab(text: 'Financials'),
                              Tab(text: 'Timeline'),
                              Tab(text: 'Documents'),
                            ],
                          ),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TabBarView(
                  children: [
                    ProfileTab(employee: employee),
                    AttendanceTab(employee: employee),
                    PayslipsTab(employee: employee),
                    RoleTab(employee: employee),
                    FinancialsTab(employee: employee),
                    TimelineTab(employee: employee),
                    DocumentsTab(employee: employee),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
