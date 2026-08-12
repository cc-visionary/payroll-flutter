import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/role_scorecard.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../auth/profile_provider.dart';

/// Opens the minimal dialog that creates a bare role card from the Roles
/// tab — job title and mission only. Everything else defaults exactly as
/// the old (now-deleted) card editor's new-card mode did: `MONTHLY` wage,
/// 8 hours/day, "Monday to Saturday", active, effective today. The rest —
/// department, brand, salary, responsibilities, KPIs, skills, expectations
/// — is authored afterwards in the workbench's Role details pane;
/// duplicating that form here would recreate the two-places-to-edit-a-role
/// problem this project exists to remove.
///
/// Returns the new card's id, or null if the dialog was cancelled.
Future<String?> showNewRoleDialog(BuildContext context, WidgetRef ref) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NewRoleDialog(ref: ref),
  );
}

class _NewRoleDialog extends StatefulWidget {
  const _NewRoleDialog({required this.ref});

  final WidgetRef ref;

  @override
  State<_NewRoleDialog> createState() => _NewRoleDialogState();
}

class _NewRoleDialogState extends State<_NewRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _jobTitle = TextEditingController();
  final _mission = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _jobTitle.dispose();
    _mission.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = widget.ref.read(userProfileProvider).asData?.value;
    if (profile == null) {
      // Reachable for real, not just in an isolated test: the
      // /workforce-planning router guard only acts once profile != null
      // (see app/router.dart), so an unresolved profile is free passage to
      // this screen, not a barrier — a slow network right after login, or a
      // deep link straight into /workforce-planning/roles/:id, can land a
      // manager here before it has settled. A bare return here would have
      // them fill in the dialog, press Create, and see nothing happen.
      setState(
        () => _error = 'Still loading your profile — try again in a moment.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final card = RoleScorecard(
        id: _newCardId(),
        companyId: profile.companyId,
        jobTitle: _jobTitle.text.trim(),
        missionStatement: _mission.text.trim(),
        responsibilities: const [],
        kpis: const [],
        wageType: 'MONTHLY',
        workHoursPerDay: 8,
        workDaysPerWeek: 'Monday to Saturday',
        isActive: true,
        effectiveDate: DateTime.now(),
      );
      final saved = await widget.ref
          .read(roleScorecardRepositoryProvider)
          .upsert(card);
      widget.ref.invalidate(roleScorecardListProvider);
      if (mounted) Navigator.pop(context, saved.id);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New role'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _jobTitle,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Job title *'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Job title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mission,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mission statement *',
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Mission statement is required'
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                'Wage type, hours, schedule, department and everything else '
                'can be set next in the role details.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _create,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

/// Mirrors the `_uuid()` helper from the old (now-deleted) card editor: a
/// short pseudo-UUID for a new row. The server accepts it since
/// client-generated UUIDs are stored across the schema; collisions are
/// astronomically unlikely.
String _newCardId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rnd = now.toRadixString(16).padLeft(12, '0');
  return '${rnd.substring(0, 8)}-${rnd.substring(8, 12)}-4xxx-yxxx-xxxxxxxxxxxx'
      .replaceAllMapped(RegExp(r'[xy]'), (m) {
        final r = (DateTime.now().microsecond + m.start) & 0xf;
        return (m.group(0) == 'x' ? r : (r & 0x3) | 0x8).toRadixString(16);
      });
}
