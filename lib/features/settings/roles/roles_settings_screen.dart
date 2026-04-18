import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/role.dart';
import '../../../data/repositories/role_repository.dart';

class RolesSettingsScreen extends ConsumerWidget {
  const RolesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(roleListProvider);
    final countsAsync = ref.watch(roleUserCountsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Roles & Permissions',
              style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _openForm(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add Role'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Manage user roles and their permissions. System roles cannot be deleted but their permissions can be customized.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        _InfoBanner(
          message:
              'Permissions are informational. Admin access is currently controlled by the app_role JWT claim; this screen will drive enforcement in a future release.',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: rolesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: Colors.red))),
            data: (roles) => roles.isEmpty
                ? const Center(child: Text('No roles defined.'))
                : ListView.separated(
                    itemCount: roles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _RoleTile(
                      role: roles[i],
                      userCount: countsAsync.asData?.value[roles[i].id] ?? 0,
                      onEdit: () =>
                          _openForm(context, ref, existing: roles[i]),
                      onDelete: roles[i].isSystem
                          ? null
                          : () => _confirmDelete(context, ref, roles[i]),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Role? existing,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => _RoleForm(
        existing: existing,
        onSaved: () {
          ref.invalidate(roleListProvider);
          ref.invalidate(roleUserCountsProvider);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Role r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete role?'),
        content: Text(
            'Remove "${r.name}"? User assignments for this role will also be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(roleRepositoryProvider).deleteRole(r.id);
    ref.invalidate(roleListProvider);
    ref.invalidate(roleUserCountsProvider);
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;
  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final s = StatusPalette.of(context, StatusTone.info);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 18, color: s.foreground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: TextStyle(color: s.foreground, fontSize: 13)),
        ),
      ]),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final Role role;
  final int userCount;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  const _RoleTile({
    required this.role,
    required this.userCount,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final permCount = role.hasWildcard ? 'All' : '${role.permissions.length}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(role.name,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Chip(
                label: Text(role.code,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              if (role.isSystem)
                const StatusChip(label: 'System', tone: StatusTone.info),
            ]),
            const SizedBox(height: 2),
            Text(
              '$userCount user${userCount == 1 ? '' : 's'} assigned • $permCount permission${permCount == '1' ? '' : 's'}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (role.description != null && role.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(role.description!,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
          ]),
        ),
        TextButton(onPressed: onEdit, child: const Text('Edit')),
        if (onDelete != null)
          TextButton(
            onPressed: onDelete,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
      ]),
    );
  }
}

class _RoleForm extends ConsumerStatefulWidget {
  final Role? existing;
  final VoidCallback onSaved;
  const _RoleForm({required this.existing, required this.onSaved});

  @override
  ConsumerState<_RoleForm> createState() => _FormState();
}

class _FormState extends ConsumerState<_RoleForm> {
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final Set<String> _selected = {...(widget.existing?.permissions ?? [])};
  bool _saving = false;
  String? _error;

  bool get _isSystem => widget.existing?.isSystem ?? false;
  bool get _hasWildcard => _selected.contains('*');

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase();
    final name = _name.text.trim();
    if (code.isEmpty || name.isEmpty) {
      setState(() => _error = 'Code and name are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(roleRepositoryProvider).upsert(
            id: widget.existing?.id,
            code: code,
            name: name,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            permissions: _selected.toList()..sort(),
            isSystem: _isSystem,
          );
      widget.onSaved();
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
      title: Text(widget.existing == null ? 'Add Role' : 'Edit Role'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      enabled: !_isSystem,
                      decoration: InputDecoration(
                        labelText: 'Code',
                        hintText: 'e.g. REGIONAL_MANAGER',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: _isSystem ? 'System role — locked' : null,
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_]')),
                        LengthLimitingTextInputFormatter(50),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Text('Permissions',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_hasWildcard)
                    const StatusChip(
                        label: 'Wildcard (*) — all permissions',
                        tone: StatusTone.warning),
                ]),
                const SizedBox(height: 8),
                if (_hasWildcard)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'This role has the wildcard permission — individual selections are ignored.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                for (final entry in kPermissionCatalog.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(entry.key,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: Colors.grey)),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final p in entry.value)
                        FilterChip(
                          label: Text(p,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                          selected: _selected.contains(p),
                          onSelected: _hasWildcard
                              ? null
                              : (v) => setState(() {
                                    if (v) {
                                      _selected.add(p);
                                    } else {
                                      _selected.remove(p);
                                    }
                                  }),
                        ),
                    ],
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
