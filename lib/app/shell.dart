import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/profile_provider.dart';
import 'breakpoints.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final bool Function(UserProfile? p) visible;
  const _NavItem(this.label, this.icon, this.route, this.visible);
}

final _items = <_NavItem>[
  _NavItem('Dashboard', Icons.dashboard_outlined, '/dashboard', (p) => true),
  _NavItem('Employees', Icons.people_outline, '/employees', (p) => true),
  _NavItem('Responsibility Cards', Icons.badge_outlined,
      '/responsibility-cards', (p) => p?.isHrOrAdmin ?? false),
  _NavItem('Attendance', Icons.schedule_outlined, '/attendance', (p) => true),
  _NavItem('Leave', Icons.beach_access_outlined, '/leave', (p) => true),
  _NavItem('Payroll', Icons.payments_outlined, '/payroll', (p) => true),
  _NavItem('Adjuncts', Icons.receipt_long_outlined, '/adjuncts', (p) => true),
  _NavItem('Audit', Icons.history_outlined, '/audit',
      (p) => p?.isAdmin ?? false),
  _NavItem('Settings', Icons.settings_outlined, '/settings',
      (p) => p?.isAdmin ?? false),
];

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isMobile(context)) {
      return child;
    }

    final location = GoRouterState.of(context).matchedLocation;
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.asData?.value;

    final visibleItems = _items.where((i) => i.visible(profile)).toList();
    final selectedIndex =
        visibleItems.indexWhere((i) => location.startsWith(i.route));
    final safeSelected = selectedIndex < 0 ? 0 : selectedIndex;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 220,
            selectedIndex: safeSelected,
            onDestinationSelected: (i) => context.go(visibleItems[i].route),
            leading: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: _LuxiumMark(),
                  ),
                  SizedBox(width: 10),
                  Text('Luxium Payroll',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.2)),
                ],
              ),
            ),
            destinations: [
              for (final i in visibleItems)
                NavigationRailDestination(
                    icon: Icon(i.icon), label: Text(i.label)),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (profile != null) ...[
                        Text(profile.email,
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(profile.appRole.name,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                      ],
                      IconButton(
                        tooltip: 'Sign out',
                        icon: const Icon(Icons.logout),
                        onPressed: () =>
                            Supabase.instance.client.auth.signOut(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Drawer for mobile navigation. Attach to a feature `Scaffold` via
/// `drawer: const AppDrawer()` — only visible on mobile (the shell hides the
/// `NavigationRail` there, so the drawer becomes the primary nav).
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final visibleItems = _items.where((i) => i.visible(profile)).toList();
    final selected =
        visibleItems.indexWhere((i) => location.startsWith(i.route));

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Row(
                    children: [
                      SizedBox(width: 24, height: 24, child: _LuxiumMark()),
                      SizedBox(width: 10),
                      Text('Luxium Payroll',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: -0.2)),
                    ],
                  ),
                  if (profile != null) ...[
                    const SizedBox(height: 12),
                    Text(profile.email, style: theme.textTheme.bodySmall),
                    Text(
                      profile.appRole.name,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (int i = 0; i < visibleItems.length; i++)
                    ListTile(
                      leading: Icon(visibleItems[i].icon),
                      title: Text(visibleItems[i].label),
                      selected: i == selected,
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go(visibleItems[i].route);
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.of(context).pop();
                Supabase.instance.client.auth.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Luxium brand mark — three-tone SVG (navy / cyan / green) at the chosen size.
/// Wrap with `SizedBox(width:..., height:...)` to control display size.
class _LuxiumMark extends StatelessWidget {
  const _LuxiumMark();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/luxium-icon.svg',
      semanticsLabel: 'Luxium',
      fit: BoxFit.contain,
    );
  }
}
