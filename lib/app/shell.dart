import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/profile_provider.dart';
import 'breakpoints.dart';
import 'tokens.dart';

/// Group labels the user has collapsed in the sidebar. Default is an empty
/// set — all groups start expanded. Lives in a Riverpod provider so the shell
/// sidebar and the mobile drawer share the same state within a session.
class CollapsedNavGroupsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String label) {
    final next = Set<String>.from(state);
    if (!next.remove(label)) next.add(label);
    state = next;
  }
}

final collapsedNavGroupsProvider =
    NotifierProvider<CollapsedNavGroupsNotifier, Set<String>>(
  CollapsedNavGroupsNotifier.new,
);

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final bool Function(UserProfile? p) visible;
  final bool comingSoon;
  const _NavItem(
    this.label,
    this.icon,
    this.route,
    this.visible, {
    this.comingSoon = false,
  });
}

class _NavGroup {
  final String label;
  final List<_NavItem> items;
  const _NavGroup(this.label, this.items);
}

bool _always(UserProfile? p) => true;
bool _hrOrAdmin(UserProfile? p) => p?.isHrOrAdmin ?? false;
bool _admin(UserProfile? p) => p?.isAdmin ?? false;

final _groups = <_NavGroup>[
  _NavGroup('Overview', [
    _NavItem('Dashboard', Icons.dashboard_outlined, '/dashboard', _always),
  ]),
  _NavGroup('People', [
    _NavItem('Employees', Icons.people_outline, '/employees', _always),
    _NavItem('Hiring', Icons.person_search_outlined, '/hiring', _always,
        comingSoon: true),
    _NavItem('Onboarding', Icons.rocket_launch_outlined, '/onboarding', _always,
        comingSoon: true),
    _NavItem('Offboarding', Icons.logout_outlined, '/offboarding', _always,
        comingSoon: true),
    _NavItem('Org Chart', Icons.account_tree_outlined, '/org-chart', _always,
        comingSoon: true),
  ]),
  _NavGroup('Work & Performance', [
    _NavItem('Responsibility Cards', Icons.badge_outlined,
        '/responsibility-cards', _hrOrAdmin),
    _NavItem('Workforce Planning', Icons.insights_outlined,
        '/workforce-planning', _hrOrAdmin,
        comingSoon: true),
    _NavItem('Performance', Icons.stacked_line_chart_outlined, '/performance',
        _always,
        comingSoon: true),
  ]),
  _NavGroup('Time & Pay', [
    _NavItem('Attendance', Icons.schedule_outlined, '/attendance', _always),
    _NavItem('Leave', Icons.beach_access_outlined, '/leave', _always),
    _NavItem('Payroll', Icons.payments_outlined, '/payroll', _always),
    _NavItem('Adjuncts', Icons.receipt_long_outlined, '/adjuncts', _always),
    _NavItem('Compensation', Icons.account_balance_wallet_outlined,
        '/compensation', _hrOrAdmin,
        comingSoon: true),
    _NavItem('Assets', Icons.devices_other_outlined, '/assets', _always,
        comingSoon: true),
  ]),
  _NavGroup('Admin', [
    _NavItem('Compliance', Icons.verified_user_outlined, '/compliance',
        _hrOrAdmin,
        comingSoon: true),
    _NavItem('Workflows', Icons.alt_route_outlined, '/workflows', _always,
        comingSoon: true),
    _NavItem('Documents', Icons.description_outlined, '/documents', _always,
        comingSoon: true),
  ]),
  _NavGroup('System', [
    _NavItem('Audit', Icons.history_outlined, '/audit', _admin),
    _NavItem('Settings', Icons.settings_outlined, '/settings', _admin),
  ]),
];

List<_NavGroup> _visibleGroups(UserProfile? profile) {
  return [
    for (final g in _groups)
      if (g.items.any((i) => i.visible(profile)))
        _NavGroup(g.label, [
          for (final i in g.items)
            if (i.visible(profile)) i,
        ]),
  ];
}

bool _isItemSelected(_NavItem item, String location) {
  if (location == item.route) return true;
  return location.startsWith('${item.route}/');
}

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isMobile(context)) {
      return child;
    }

    final location = GoRouterState.of(context).matchedLocation;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final groups = _visibleGroups(profile);
    final collapsed = ref.watch(collapsedNavGroupsProvider);
    final p = LuxiumColors.of(context);

    void toggleGroup(String label) =>
        ref.read(collapsedNavGroupsProvider.notifier).toggle(label);

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(right: BorderSide(color: p.border, width: 1)),
            ),
            child: Column(
              children: [
                const _BrandHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuxiumSpacing.sm,
                      vertical: LuxiumSpacing.sm,
                    ),
                    children: [
                      for (final g in groups) ...[
                        _GroupHeader(
                          label: g.label,
                          collapsed: collapsed.contains(g.label),
                          onTap: () => toggleGroup(g.label),
                        ),
                        if (!collapsed.contains(g.label))
                          for (final item in g.items)
                            _NavTile(
                              item: item,
                              selected: _isItemSelected(item, location),
                              onTap: () => context.go(item.route),
                            ),
                        const SizedBox(height: LuxiumSpacing.sm),
                      ],
                    ],
                  ),
                ),
                _UserFooter(profile: profile),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Drawer for mobile navigation. Attach to a feature `Scaffold` via
/// `drawer: const AppDrawer()` — only visible on mobile (the shell hides the
/// sidebar there, so the drawer becomes the primary nav).
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final groups = _visibleGroups(profile);
    final collapsed = ref.watch(collapsedNavGroupsProvider);
    final p = LuxiumColors.of(context);

    void toggleGroup(String label) =>
        ref.read(collapsedNavGroupsProvider.notifier).toggle(label);

    return Drawer(
      backgroundColor: p.surface,
      child: SafeArea(
        child: Column(
          children: [
            const _BrandHeader(drawer: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: LuxiumSpacing.sm,
                  vertical: LuxiumSpacing.sm,
                ),
                children: [
                  for (final g in groups) ...[
                    _GroupHeader(
                      label: g.label,
                      collapsed: collapsed.contains(g.label),
                      onTap: () => toggleGroup(g.label),
                    ),
                    if (!collapsed.contains(g.label))
                      for (final item in g.items)
                        _NavTile(
                          item: item,
                          selected: _isItemSelected(item, location),
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go(item.route);
                          },
                        ),
                    const SizedBox(height: LuxiumSpacing.sm),
                  ],
                ],
              ),
            ),
            _UserFooter(profile: profile, drawer: true),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  final bool drawer;
  const _BrandHeader({this.drawer = false});

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        LuxiumSpacing.lg,
        drawer ? LuxiumSpacing.lg : LuxiumSpacing.xl,
        LuxiumSpacing.lg,
        LuxiumSpacing.lg,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border, width: 1)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 22, height: 22, child: _LuxiumMark()),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Luxium People',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final bool collapsed;
  final VoidCallback onTap;
  const _GroupHeader({
    required this.label,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(LuxiumRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LuxiumSpacing.md,
          LuxiumSpacing.md,
          LuxiumSpacing.sm,
          LuxiumSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: p.soft,
                ),
              ),
            ),
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: p.soft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    final fg = selected ? p.cta : p.foreground;
    final bg = selected ? p.ctaTint : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(LuxiumRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LuxiumSpacing.md,
              vertical: 9,
            ),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: fg),
                const SizedBox(width: LuxiumSpacing.md),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.comingSoon) const _SoonBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoonBadge extends StatelessWidget {
  const _SoonBadge();

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.muted,
        borderRadius: BorderRadius.circular(LuxiumRadius.pill),
      ),
      child: Text(
        'Soon',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: p.soft,
        ),
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  final UserProfile? profile;
  final bool drawer;
  const _UserFooter({required this.profile, this.drawer = false});

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(LuxiumSpacing.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (profile != null) ...[
                  Text(
                    profile!.email,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile!.appRole.name,
                    style: TextStyle(
                      color: p.cta,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 18),
            onPressed: () {
              if (drawer) Navigator.of(context).pop();
              Supabase.instance.client.auth.signOut();
            },
          ),
        ],
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
