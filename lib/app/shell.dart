import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.label, this.icon, this.route);
}

const _items = [
  _NavItem('Employees', Icons.people_outline, '/employees'),
  _NavItem('Responsibility Cards', Icons.badge_outlined, '/responsibility-cards'),
  _NavItem('Attendance', Icons.schedule_outlined, '/attendance'),
  _NavItem('Payroll', Icons.payments_outlined, '/payroll'),
  _NavItem('Settings', Icons.settings_outlined, '/settings'),
];

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final selected = _items.indexWhere((i) => location.startsWith(i.route));

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 220,
            selectedIndex: selected < 0 ? 0 : selected,
            onDestinationSelected: (i) => context.go(_items[i].route),
            leading: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.payments, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Payroll', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ],
              ),
            ),
            destinations: [
              for (final i in _items)
                NavigationRailDestination(icon: Icon(i.icon), label: Text(i.label)),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton(
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout),
                    onPressed: () => Supabase.instance.client.auth.signOut(),
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
