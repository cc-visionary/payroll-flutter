import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../auth/profile_provider.dart';
import 'shifts/shift_templates_screen.dart';
import 'holidays/holidays_settings_screen.dart';
import 'about/about_settings_screen.dart';
import 'bank_accounts/company_bank_accounts_screen.dart';
import 'departments/departments_settings_screen.dart';
import 'hiring_entities/hiring_entities_settings_screen.dart';
import 'roles/roles_settings_screen.dart';
import 'users/users_settings_screen.dart';
import '../lark/lark_settings_screen.dart';

enum _Tab {
  departments('departments', 'Departments', 'Manage company departments',
      Icons.apartment_outlined),
  hiringEntities('hiring-entities', 'Company Info',
      'Hiring entities & registrations', Icons.business_outlined),
  bankAccounts('bank-accounts', 'Bank Accounts', 'Company payment sources',
      Icons.account_balance_outlined),
  roles('roles', 'Roles', 'Manage roles and permissions',
      Icons.shield_outlined),
  users('users', 'Users', 'Manage who can log in',
      Icons.people_alt_outlined),
  shifts('shifts', 'Shift Templates', 'Define work schedules', Icons.schedule),
  holidays('holidays', 'Holidays', 'Holiday calendar for payroll',
      Icons.event_outlined),
  lark('lark', 'Integrations', 'Attendance source & Lark sync', Icons.sync),
  about('about', 'About', 'Version and appearance', Icons.info_outline);

  final String slug;
  final String label;
  final String subtitle;
  final IconData icon;
  const _Tab(this.slug, this.label, this.subtitle, this.icon);
}

_Tab? _parseSlug(String? slug) {
  if (slug == null) return null;
  for (final t in _Tab.values) {
    if (t.slug == slug) return t;
  }
  return null;
}

class SettingsScreen extends ConsumerStatefulWidget {
  final String? initialTab;
  const SettingsScreen({super.key, this.initialTab});
  @override
  ConsumerState<SettingsScreen> createState() => _State();
}

class _State extends ConsumerState<SettingsScreen> {
  late _Tab _tab = _parseSlug(widget.initialTab) ?? _Tab.departments;

  bool get _isSuperAdmin {
    final profile = ref.read(userProfileProvider).asData?.value;
    return profile?.appRole == AppRole.SUPER_ADMIN;
  }

  @override
  void didUpdateWidget(SettingsScreen old) {
    super.didUpdateWidget(old);
    final parsed = _parseSlug(widget.initialTab);
    if (parsed != null && parsed != _tab) setState(() => _tab = parsed);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (profile == null || !profile.isAdmin) {
      return const Scaffold(body: Center(child: Text('Admins only.')));
    }
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Settings')),
      body: isMobile(context) ? _mobileLayout() : _desktopLayout(),
    );
  }

  Widget _desktopLayout() {
    return Row(children: [
      SizedBox(
        width: 260,
        child: ListView(children: [
          _tile(_Tab.departments),
          _tile(_Tab.hiringEntities),
          _tile(_Tab.bankAccounts),
          _tile(_Tab.roles),
          if (_isSuperAdmin) _tile(_Tab.users),
          const Divider(height: 24, indent: 16, endIndent: 16),
          _tile(_Tab.shifts),
          _tile(_Tab.holidays),
          _tile(_Tab.lark),
          const Divider(height: 24, indent: 16, endIndent: 16),
          _tile(_Tab.about),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: _body()),
    ]);
  }

  Widget _mobileLayout() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<_Tab>(
            initialValue: _tab,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Section',
            ),
            items: [
              for (final t in _Tab.values)
                if (t != _Tab.users || _isSuperAdmin)
                  DropdownMenuItem(
                    value: t,
                    child: Row(children: [
                      Icon(t.icon, size: 18),
                      const SizedBox(width: 8),
                      Text(t.label),
                    ]),
                  ),
            ],
            onChanged: (next) {
              if (next == null) return;
              setState(() => _tab = next);
              context.go('/settings/${next.slug}');
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _tile(_Tab tab) {
    final selected = _tab == tab;
    final color = selected ? Theme.of(context).colorScheme.primary : null;
    return ListTile(
      leading: Icon(tab.icon, color: color),
      title: Text(tab.label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: color,
          )),
      subtitle: Text(tab.subtitle, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onTap: () {
        setState(() => _tab = tab);
        context.go('/settings/${tab.slug}');
      },
    );
  }

  Widget _body() {
    switch (_tab) {
      case _Tab.departments:
        return const DepartmentsSettingsScreen();
      case _Tab.hiringEntities:
        return const HiringEntitiesSettingsScreen();
      case _Tab.bankAccounts:
        return const CompanyBankAccountsScreen();
      case _Tab.roles:
        return const RolesSettingsScreen();
      case _Tab.users:
        if (!_isSuperAdmin) {
          return const Center(child: Text('Super Admins only.'));
        }
        return const UsersSettingsScreen();
      case _Tab.shifts:
        return const ShiftTemplatesScreen();
      case _Tab.holidays:
        return const HolidaysSettingsScreen();
      case _Tab.lark:
        return const LarkSettingsScreen();
      case _Tab.about:
        return const AboutSettingsScreen();
    }
  }
}
