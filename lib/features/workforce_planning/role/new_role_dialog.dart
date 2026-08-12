import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/role_scorecard.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../auth/profile_provider.dart';
import '../../responsibility_cards/scorecard_base_salary.dart';

/// Opens the minimal dialog that creates a bare role card from the Roles
/// tab — job title, mission, and an optional base salary. Everything else
/// defaults exactly as the old (now-deleted) card editor's new-card mode
/// did: `MONTHLY` wage, 8 hours/day, "Monday to Saturday", active,
/// effective today. The rest — department, brand, responsibilities, KPIs,
/// skills, expectations — is authored afterwards in the workbench's Role
/// details pane; duplicating that form here would recreate the
/// two-places-to-edit-a-role problem this project exists to remove.
///
/// Base salary is the one exception to "author it in the details pane
/// afterwards", and it has to be: `base_salary` is settable only at CREATION
/// and immutable thereafter (see [resolveScorecardBaseSalaryOnSave]), so the
/// details pane renders it permanently read-only. If this dialog did not
/// collect it, no surface in the app could set it at all — and payroll falls
/// back to it for every holder with no `compensation_changes` row
/// (`compute_service.dart`), so a role created without it and then staffed
/// pays a basic of ₱0 on a released payslip.
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
  final _baseSalary = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _jobTitle.dispose();
    _mission.dispose();
    _baseSalary.dispose();
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
        // Creation is the ONLY moment this is settable — every later save
        // routes through the same helper with isEdit: true and keeps the
        // stored value. Reusing the helper here rather than parsing inline
        // keeps that invariant expressed in exactly one place.
        baseSalary: resolveScorecardBaseSalaryOnSave(
          isEdit: false,
          existingBaseSalary: null,
          typedText: _baseSalary.text,
        ),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _baseSalary,
                decoration: const InputDecoration(
                  labelText: 'Base salary (PHP)',
                  helperMaxLines: 3,
                  helperText:
                      "The role's default pay. Used by offer letters, and by "
                      'any employee who has no compensation record yet. '
                      'Locked once the role exists — later pay changes go '
                      'through "Adjust Compensation" on the employee.',
                ),
                // Optional, but anything typed must parse with the same
                // Decimal.tryParse the save path uses.
                // resolveScorecardBaseSalaryOnSave returns null for whatever
                // it cannot read, so without this a typo ("50,000") would
                // save as "no salary set" and say nothing about it.
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return null;
                  return Decimal.tryParse(text) == null
                      ? 'Enter a plain number, e.g. 25000'
                      : null;
                },
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

/// The new row's id, generated client-side (the schema stores client-made
/// UUIDs throughout).
///
/// A real v4 from `package:uuid`, not the old card editor's hand-rolled
/// `_uuid()`, which drew its "random" digits from a truncated microsecond
/// clock and so had far less entropy than its shape suggested. That matters
/// because `upsert()` is select-then-insert-or-update: a collision would not
/// fail loudly, it would silently UPDATE somebody else's role card.
String _newCardId() => const Uuid().v4();
