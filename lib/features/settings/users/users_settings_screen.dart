import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/managed_user.dart';
import '../../../data/models/role.dart';
import '../../../data/repositories/role_repository.dart';
import '../../../data/repositories/user_management_repository.dart';

class UsersSettingsScreen extends ConsumerWidget {
  const UsersSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(managedUsersProvider);
    final rolesAsync = ref.watch(roleListProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Users', style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _openAddDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add User'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Manage who can log in to the payroll app. Email is used as the login identifier — passwords are set here, not via email.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
            data: (users) {
              if (users.isEmpty) {
                return const Center(child: Text('No users yet.'));
              }
              final roles = rolesAsync.asData?.value ?? const <Role>[];
              return ListView.separated(
                itemCount: users.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _UserTile(
                  user: users[i],
                  roles: roles,
                  onChanged: () => ref.invalidate(managedUsersProvider),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _openAddDialog(BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      builder: (_) => _AddUserDialog(
        onCreated: () => ref.invalidate(managedUsersProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User tile
// ---------------------------------------------------------------------------

class _UserTile extends ConsumerWidget {
  final ManagedUser user;
  final List<Role> roles;
  final VoidCallback onChanged;
  const _UserTile({required this.user, required this.roles, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = roles.firstWhere(
      (r) => r.code == user.roleCode,
      orElse: () => Role(id: '', code: user.roleCode ?? '—', name: user.roleCode ?? '—', permissions: const [], isSystem: false),
    );
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(user.displayName(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Chip(
                label: Text(role.code, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              if (user.isInactive)
                const StatusChip(label: 'Inactive', tone: StatusTone.danger),
            ]),
            const SizedBox(height: 2),
            Text(
              user.email + (user.linkedEmployeeName == null ? ' · no employee link' : ' · linked: ${user.linkedEmployeeName}'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 2),
            if (user.mustChangePassword)
              const Text(
                '⚠ Must change password on next login',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              )
            else if (user.lastSignInAt != null)
              Text(
                'Last sign-in: ${_relative(user.lastSignInAt!)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              )
            else
              const Text('Never signed in', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ),
        PopupMenuButton<_UserAction>(
          onSelected: (a) => _onAction(context, ref, a),
          itemBuilder: (_) => [
            const PopupMenuItem(value: _UserAction.changeRole, child: Text('Change role')),
            const PopupMenuItem(value: _UserAction.setPassword, child: Text('Set new password')),
            const PopupMenuItem(value: _UserAction.linkEmployee, child: Text('Link / unlink employee')),
            if (user.isInactive)
              const PopupMenuItem(value: _UserAction.reactivate, child: Text('Reactivate'))
            else
              const PopupMenuItem(value: _UserAction.deactivate, child: Text('Deactivate', style: TextStyle(color: Colors.red))),
          ],
        ),
      ]),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, _UserAction action) async {
    final repo = ref.read(userManagementRepositoryProvider);
    try {
      switch (action) {
        case _UserAction.changeRole:
          await showDialog(
            context: context,
            builder: (_) => _ChangeRoleDialog(user: user, roles: roles),
          );
          break;
        case _UserAction.setPassword:
          await showDialog(
            context: context,
            builder: (_) => _SetPasswordDialog(user: user),
          );
          break;
        case _UserAction.linkEmployee:
          await showDialog(
            context: context,
            builder: (_) => _LinkEmployeeDialog(user: user),
          );
          break;
        case _UserAction.deactivate:
          final ok = await _confirm(context, 'Deactivate ${user.displayName()}?', 'They will be unable to sign in until reactivated.');
          if (ok) await repo.deactivate(user.userId);
          break;
        case _UserAction.reactivate:
          await repo.reactivate(user.userId);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    onChanged();
  }
}

enum _UserAction { changeRole, setPassword, linkEmployee, deactivate, reactivate }

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return ok == true;
}

String _relative(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Add user dialog
// ---------------------------------------------------------------------------

String _generateTempPassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(14, (_) => chars[r.nextInt(chars.length)]).join();
}

class _AddUserDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _AddUserDialog({required this.onCreated});
  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _roleCode = 'PAYROLL_ADMIN';
  String? _employeeId;
  bool _saving = false;
  String? _error;
  String? _createdPassword;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    final pw = _password.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Valid email is required.');
      return;
    }
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userManagementRepositoryProvider).create(
            email: email,
            password: pw,
            roleCode: _roleCode,
            employeeId: _employeeId,
          );
      widget.onCreated();
      setState(() => _createdPassword = pw);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_createdPassword != null) {
      return AlertDialog(
        title: const Text('User created'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_email.text} can now sign in. The temporary password is shown below — copy it now, it will not be shown again.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Expanded(child: SelectableText(_createdPassword!, style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy',
                onPressed: () => Clipboard.setData(ClipboardData(text: _createdPassword!)),
              ),
            ]),
          ),
        ]),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      );
    }
    final unlinkedAsync = ref.watch(unlinkedEmployeesProvider(null));
    final rolesAsync = ref.watch(roleListProvider);
    return AlertDialog(
      title: const Text('Add User'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), isDense: true),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Temporary password (min 8)',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Generate',
                  onPressed: () {
                    final pw = _generateTempPassword();
                    _password.text = pw;
                    _confirm.text = pw;
                  },
                ),
              ),
              obscureText: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder(), isDense: true),
              obscureText: false,
            ),
            const SizedBox(height: 12),
            rolesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Roles: $e'),
              data: (roles) => DropdownButtonFormField<String>(
                value: roles.any((r) => r.code == _roleCode) ? _roleCode : roles.first.code,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder(), isDense: true),
                items: [for (final r in roles) DropdownMenuItem(value: r.code, child: Text('${r.name}  (${r.code})'))],
                onChanged: (v) => setState(() => _roleCode = v!),
              ),
            ),
            const SizedBox(height: 12),
            unlinkedAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Employees: $e'),
              data: (emps) => DropdownButtonFormField<String?>(
                value: _employeeId,
                decoration: const InputDecoration(labelText: 'Link to employee (optional)', border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('(none — standalone user)')),
                  for (final e in emps) DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => _employeeId = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Set password dialog
// ---------------------------------------------------------------------------

class _SetPasswordDialog extends ConsumerStatefulWidget {
  final ManagedUser user;
  const _SetPasswordDialog({required this.user});
  @override
  ConsumerState<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<_SetPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _newPassword;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userManagementRepositoryProvider).setPassword(widget.user.userId, pw);
      setState(() => _newPassword = pw);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_newPassword != null) {
      return AlertDialog(
        title: const Text('Password set'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.user.email} must change this password on next login. Copy it now — it will not be shown again.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Expanded(child: SelectableText(_newPassword!, style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => Clipboard.setData(ClipboardData(text: _newPassword!)),
              ),
            ]),
          ),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      );
    }
    return AlertDialog(
      title: Text('Set new password — ${widget.user.email}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _password,
            decoration: InputDecoration(
              labelText: 'New password (min 8)',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () {
                  final pw = _generateTempPassword();
                  _password.text = pw;
                  _confirm.text = pw;
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            decoration: const InputDecoration(labelText: 'Confirm', border: OutlineInputBorder(), isDense: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Set password'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Change role dialog
// ---------------------------------------------------------------------------

class _ChangeRoleDialog extends ConsumerStatefulWidget {
  final ManagedUser user;
  final List<Role> roles;
  const _ChangeRoleDialog({required this.user, required this.roles});
  @override
  ConsumerState<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends ConsumerState<_ChangeRoleDialog> {
  late String _selected = widget.user.roleCode ?? widget.roles.first.code;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userManagementRepositoryProvider).updateRole(widget.user.userId, _selected);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change role — ${widget.user.email}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in widget.roles)
            RadioListTile<String>(
              value: r.code,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v!),
              title: Text(r.name),
              subtitle: Text(r.code, style: const TextStyle(fontFamily: 'monospace')),
              dense: true,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Link/unlink employee dialog
// ---------------------------------------------------------------------------

class _LinkEmployeeDialog extends ConsumerStatefulWidget {
  final ManagedUser user;
  const _LinkEmployeeDialog({required this.user});
  @override
  ConsumerState<_LinkEmployeeDialog> createState() => _LinkEmployeeDialogState();
}

class _LinkEmployeeDialogState extends ConsumerState<_LinkEmployeeDialog> {
  late String? _selected = widget.user.linkedEmployeeId;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userManagementRepositoryProvider).linkEmployee(widget.user.userId, _selected);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empsAsync = ref.watch(unlinkedEmployeesProvider(widget.user.userId));
    return AlertDialog(
      title: Text('Link / unlink employee — ${widget.user.email}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: empsAsync.when(
          loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('$e', style: const TextStyle(color: Colors.red)),
          data: (emps) => DropdownButtonFormField<String?>(
            value: _selected,
            decoration: const InputDecoration(labelText: 'Employee', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('(none — unlink)')),
              for (final e in emps) DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
            ],
            onChanged: (v) => setState(() => _selected = v),
          ),
        ),
      ),
      actions: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
