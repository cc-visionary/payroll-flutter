import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/payroll_repository.dart';
import '../features/auth/profile_provider.dart';
import '../features/compliance/providers.dart';
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

/// Whether the desktop sidebar is collapsed to icon-only mode.
class SidebarCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedNotifier, bool>(
  SidebarCollapsedNotifier.new,
);

const double _kSidebarExpandedWidth = 240;
const double _kSidebarCollapsedWidth = 64;
const Duration _kSidebarAnim = Duration(milliseconds: 180);

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final bool Function(UserProfile? p) visible;
  final bool comingSoon;
  /// When non-null, the tile invokes this with the surrounding `WidgetRef`
  /// to subscribe to a count source (typically `ref.watch(provider)` on an
  /// `AsyncNotifierProvider<_, int>` or `FutureProvider<int>`) and renders
  /// a numeric notification badge whenever the resolved value is `> 0`.
  /// Errors / loading collapse to zero so a transient backend hiccup never
  /// paints a stale or blank badge in the chrome. Use the same permission
  /// gate (`visible`) that hides the tile so users without access don't
  /// see counts they can't act on.
  ///
  /// Indirected through a closure (rather than a typed `ProviderListenable`)
  /// because `ProviderListenable` is not exported from
  /// `flutter_riverpod` 3.x's public surface, and the `Refreshable<...>`
  /// mixin returned by `AsyncNotifierProvider` and `FutureProvider` are
  /// not type-compatible without a cast.
  final AsyncValue<int> Function(WidgetRef ref)? badgeCountProvider;
  const _NavItem(
    this.label,
    this.icon,
    this.route,
    this.visible, {
    this.comingSoon = false,
    this.badgeCountProvider,
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
    _NavItem(
      'Payroll',
      Icons.payments_outlined,
      '/payroll',
      _always,
      badgeCountProvider: (ref) =>
          ref.watch(payrollRunsAwaitingReleaseCountProvider),
    ),
    _NavItem('Adjuncts', Icons.receipt_long_outlined, '/adjuncts', _always),
    _NavItem('Compensation', Icons.account_balance_wallet_outlined,
        '/compensation', _hrOrAdmin,
        comingSoon: true),
    _NavItem('Assets', Icons.devices_other_outlined, '/assets', _always,
        comingSoon: true),
  ]),
  _NavGroup('Admin', [
    _NavItem(
      'Compliance',
      Icons.verified_user_outlined,
      '/compliance',
      _hrOrAdmin,
      badgeCountProvider: (ref) =>
          ref.watch(pendingStatutoryPayablesCountProvider),
    ),
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
    final railCollapsed = ref.watch(sidebarCollapsedProvider);
    final p = LuxiumColors.of(context);

    void toggleGroup(String label) =>
        ref.read(collapsedNavGroupsProvider.notifier).toggle(label);

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: _kSidebarAnim,
            curve: Curves.easeOut,
            width:
                railCollapsed ? _kSidebarCollapsedWidth : _kSidebarExpandedWidth,
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(right: BorderSide(color: p.border, width: 1)),
            ),
            child: ClipRect(
              child: Column(
                children: [
                  _BrandHeader(
                    railCollapsed: railCollapsed,
                    onToggleRail: () => ref
                        .read(sidebarCollapsedProvider.notifier)
                        .toggle(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: railCollapsed
                            ? LuxiumSpacing.xs
                            : LuxiumSpacing.sm,
                        vertical: LuxiumSpacing.sm,
                      ),
                      children: [
                        for (final g in groups) ...[
                          if (!railCollapsed)
                            _GroupHeader(
                              label: g.label,
                              collapsed: collapsed.contains(g.label),
                              onTap: () => toggleGroup(g.label),
                            )
                          else
                            const SizedBox(height: LuxiumSpacing.sm),
                          if (railCollapsed ||
                              !collapsed.contains(g.label))
                            for (final item in g.items)
                              _NavTile(
                                item: item,
                                selected: _isItemSelected(item, location),
                                railCollapsed: railCollapsed,
                                onTap: () => context.go(item.route),
                              ),
                          const SizedBox(height: LuxiumSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                  _UserFooter(
                    profile: profile,
                    railCollapsed: railCollapsed,
                  ),
                ],
              ),
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
  final bool railCollapsed;
  final VoidCallback? onToggleRail;
  const _BrandHeader({
    this.drawer = false,
    this.railCollapsed = false,
    this.onToggleRail,
  });

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    final showToggle = onToggleRail != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
        railCollapsed ? LuxiumSpacing.sm : LuxiumSpacing.lg,
        drawer ? LuxiumSpacing.lg : LuxiumSpacing.xl,
        railCollapsed ? LuxiumSpacing.sm : LuxiumSpacing.lg,
        LuxiumSpacing.lg,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border, width: 1)),
      ),
      child: railCollapsed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 22, height: 22, child: _LuxiumMark()),
                if (showToggle) ...[
                  const SizedBox(height: 10),
                  _RailToggleButton(
                    collapsed: true,
                    onPressed: onToggleRail!,
                  ),
                ],
              ],
            )
          : Row(
              children: [
                const SizedBox(width: 22, height: 22, child: _LuxiumMark()),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Luxium People',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (showToggle)
                  _RailToggleButton(
                    collapsed: false,
                    onPressed: onToggleRail!,
                  ),
              ],
            ),
    );
  }
}

class _RailToggleButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onPressed;
  const _RailToggleButton({required this.collapsed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
        icon: Icon(
          collapsed
              ? Icons.keyboard_double_arrow_right_rounded
              : Icons.keyboard_double_arrow_left_rounded,
          color: p.soft,
        ),
        onPressed: onPressed,
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

class _NavTile extends ConsumerWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool railCollapsed;
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.railCollapsed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LuxiumColors.of(context);
    final fg = selected ? p.cta : p.foreground;
    final bg = selected ? p.ctaTint : Colors.transparent;

    // Resolve the optional notification count. Errors / loading collapse to
    // zero so a transient backend hiccup never paints a stale or blank
    // badge in the chrome.
    final int badgeCount = item.badgeCountProvider == null
        ? 0
        : (item.badgeCountProvider!(ref).asData?.value ?? 0);
    // Notification badge wins over "Soon" — they're mutually exclusive in
    // practice, but be defensive in case both ever apply to the same item.
    final showBadge = badgeCount > 0;
    final showSoon = item.comingSoon && !showBadge;

    final iconWidget = showBadge && railCollapsed
        ? _NavBadge.collapsed(icon: item.icon, fg: fg, count: badgeCount)
        : Icon(item.icon, size: 18, color: fg);

    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(LuxiumRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: railCollapsed ? 0 : LuxiumSpacing.md,
              vertical: 9,
            ),
            child: railCollapsed
                ? Center(child: iconWidget)
                : Row(
                    children: [
                      iconWidget,
                      const SizedBox(width: LuxiumSpacing.md),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: fg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showBadge) _NavBadge.expanded(count: badgeCount),
                      if (showSoon) const _SoonBadge(),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (!railCollapsed) return tile;
    final tooltip = showBadge
        ? '${item.label} ($badgeCount)'
        : (item.comingSoon ? '${item.label} (Soon)' : item.label);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: tile,
    );
  }
}

/// Numeric notification badge for sidebar nav tiles. Two render modes:
///
///   - `_NavBadge.expanded`  — right-aligned pill in the tile row, replaces
///     the "Soon" badge slot. Tinted bg + darker text per `.impeccable.md`.
///   - `_NavBadge.collapsed` — overlay dot at the top-right of the tile's
///     icon, with the number inside when it fits (single digit) or just a
///     filled dot otherwise.
///
/// Counts cap at `99+` to avoid runaway growth in the chrome.
class _NavBadge extends StatelessWidget {
  final int count;
  final bool _collapsed;
  final IconData? _icon;
  final Color? _iconFg;

  const _NavBadge.expanded({required this.count})
      : _collapsed = false,
        _icon = null,
        _iconFg = null;

  const _NavBadge.collapsed({
    required IconData icon,
    required Color fg,
    required this.count,
  })  : _collapsed = true,
        _icon = icon,
        _iconFg = fg;

  String get _label => count > 99 ? '99+' : '$count';

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    if (_collapsed) {
      // Stack the icon with a small overlay dot/badge at the top-right.
      // Single-digit counts fit inside the dot; anything wider degrades to
      // a filled dot (the tooltip on the tile carries the exact number).
      final showNumber = count < 10;
      return SizedBox(
        width: 22,
        height: 22,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(_icon, size: 18, color: _iconFg),
            Positioned(
              top: -2,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 12,
                  minHeight: 12,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: showNumber ? 3 : 0,
                  vertical: 0,
                ),
                decoration: BoxDecoration(
                  color: p.cta,
                  borderRadius: BorderRadius.circular(LuxiumRadius.pill),
                ),
                child: showNumber
                    ? Text(
                        _label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      );
    }
    // Expanded: tinted bg + darker text, no border.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.ctaTint,
        borderRadius: BorderRadius.circular(LuxiumRadius.pill),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: p.cta,
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
  final bool railCollapsed;
  const _UserFooter({
    required this.profile,
    this.drawer = false,
    this.railCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: railCollapsed ? LuxiumSpacing.sm : LuxiumSpacing.lg,
        vertical: LuxiumSpacing.lg,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border, width: 1)),
      ),
      child: railCollapsed
          ? Tooltip(
              message: profile?.email ?? 'Sign out',
              child: IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout, size: 18),
                onPressed: () => Supabase.instance.client.auth.signOut(),
              ),
            )
          : Row(
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
