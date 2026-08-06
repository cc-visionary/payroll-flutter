import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../app/theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../documents/providers.dart' show roleScorecardByIdProvider;
import '../allocation.dart';
import '../wp_providers.dart';
import 'role_view_tab.dart' show ownerComputedProvider;

/// One decimal, dropping a trailing `.0` — mirrors the rounding in
/// `allocation.dart` so what's typed and what's shown always agree.
String _fmtPct(double v) {
  final rounded = (v * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

String _fmtHours(double v) => '${v.toStringAsFixed(1)}h';

/// The per-accountability assignment editor: one row per PRIMARY/CONTRIBUTOR
/// holder with a live `= 100%` check, one-click simplifiers that rewrite
/// every row's percentage at once, and read-only derived hours so the manager
/// never has to do the `taskHours * pct/100` math by hand.
///
/// Mirrors `UnassignedTab`'s provider-read/invalidate/`StatusChip` shape so
/// the two surfaces don't drift into different conventions for the same
/// underlying `wp_task_assignments` table.
class AssignmentPanel extends ConsumerStatefulWidget {
  final String taskId;
  final String companyId;
  final double taskHours;
  final List<RoleScorecard> cards;
  final List<Employee> employees;

  const AssignmentPanel({
    super.key,
    required this.taskId,
    required this.companyId,
    required this.taskHours,
    required this.cards,
    required this.employees,
  });

  @override
  ConsumerState<AssignmentPanel> createState() => _AssignmentPanelState();
}

class _AssignmentPanelState extends ConsumerState<AssignmentPanel> {
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};
  // Refreshed at the top of every build() so the focus-loss listener below
  // always resolves the CURRENT row for an id, never the one closed over the
  // first time the FocusNode was created (see _focusNodeFor).
  final _rowsById = <String, WpTaskAssignment>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(WpTaskAssignment a) {
    final text = _fmtPct(a.allocationPct);
    final existing = _controllers[a.id];
    if (existing == null) {
      return _controllers[a.id] = TextEditingController(text: text);
    }
    // Don't fight an in-progress edit — only resync from the server value
    // once the field has lost focus (e.g. after a simplifier rewrote it).
    final focused = _focusNodes[a.id]?.hasFocus ?? false;
    if (!focused && existing.text != text) {
      existing.text = text;
    }
    return existing;
  }

  FocusNode _focusNodeFor(WpTaskAssignment a) =>
      _focusNodes.putIfAbsent(a.id, () {
        final node = FocusNode();
        node.addListener(() {
          if (node.hasFocus) return;
          final current = _rowsById[a.id]; // always the freshly-built row
          if (current != null) _commitPct(current);
        });
        return node;
      });

  @override
  Widget build(BuildContext context) {
    final byTaskAsync = ref.watch(wpAssignmentsByTaskProvider);

    if (byTaskAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }
    if (byTaskAsync.hasError) {
      return Text(
        'Error: ${byTaskAsync.error}',
        style: const TextStyle(color: Colors.red),
      );
    }

    final byTask =
        byTaskAsync.asData?.value ?? const <String, List<WpTaskAssignment>>{};
    final rows = byTask[widget.taskId] ?? const <WpTaskAssignment>[];
    // Refresh so the focus-loss listener (see _focusNodeFor) always commits
    // against the row this build actually rendered, not a stale one.
    for (final r in rows) {
      _rowsById[r.id] = r;
    }

    // hoursPerMonth on the task is direct-hours only — null for every
    // driver/rate-costed task. Prefer the computed view's real hours; fall
    // back to widget.taskHours only when the computed row hasn't loaded yet.
    final allComputed =
        ref.watch(wpAllTaskComputedProvider).asData?.value ??
        const <WpTaskComputed>[];
    double? computedHours;
    for (final c in allComputed) {
      if (c.taskId == widget.taskId) {
        computedHours = c.hoursPerMonthBase;
        break;
      }
    }
    final hours = computedHours ?? widget.taskHours;

    final total = allocationTotal(rows.map((r) => r.allocationPct));
    final withinTolerance = (total - 100).abs() <= 0.05;
    final primaryIndex = rows.indexWhere((r) => r.assignmentRole == 'PRIMARY');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Assigned', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            StatusChip(
              label: withinTolerance ? '= 100%' : '⚠ ${_fmtPct(total)}%',
              tone: withinTolerance ? StatusTone.success : StatusTone.warning,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final row in rows) _assignmentRow(context, row, hours),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              onPressed: rows.isEmpty ? null : () => _splitEqually(rows),
              child: const Text('Split equally'),
            ),
            OutlinedButton(
              onPressed: (rows.length < 2 || primaryIndex < 0)
                  ? null
                  : () => _ownerMajority(rows, primaryIndex),
              child: const Text('Owner majority'),
            ),
            OutlinedButton(
              onPressed: rows.isEmpty ? null : () => _clear(rows),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () => _addContributor(rows),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add contributor'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _assignmentRow(
    BuildContext context,
    WpTaskAssignment a,
    double hours,
  ) {
    final isPrimary = a.assignmentRole == 'PRIMARY';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(_targetLabel(a), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          StatusChip(
            label: isPrimary ? 'PRIMARY' : 'CONTRIBUTOR',
            tone: isPrimary ? StatusTone.info : StatusTone.neutral,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: TextField(
              key: ValueKey('pct-${a.id}'),
              controller: _controllerFor(a),
              focusNode: _focusNodeFor(a),
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
              ],
              style: AppTheme.mono(context),
              decoration: const InputDecoration(
                isDense: true,
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commitPct(a),
            ),
          ),
          const SizedBox(width: 12),
          if (!isPrimary)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _delete(a),
            )
          else
            const SizedBox(width: 40),
          Expanded(
            flex: 2,
            child: Text(
              _derivedLabel(a, hours),
              textAlign: TextAlign.right,
              style: AppTheme.mono(context),
            ),
          ),
        ],
      ),
    );
  }

  String _targetLabel(WpTaskAssignment a) {
    if (a.roleScorecardId != null) {
      for (final c in widget.cards) {
        if (c.id == a.roleScorecardId) return c.jobTitle;
      }
      return a.roleScorecardId!;
    }
    if (a.employeeId != null) {
      for (final e in widget.employees) {
        if (e.id == a.employeeId) return e.fullName;
      }
      return a.employeeId!;
    }
    return a.id;
  }

  String _derivedLabel(WpTaskAssignment a, double hours) {
    // No real hours to derive from (driver/rate-costed task not yet computed,
    // or genuinely zero): say so rather than render a confidently wrong 0.0h.
    if (hours <= 0) return 'preview unavailable';
    final rowHours = hours * a.allocationPct / 100;
    if (a.roleScorecardId != null) {
      final n = widget.employees
          .where(
            (e) =>
                e.roleScorecardId == a.roleScorecardId &&
                e.employmentStatus == 'ACTIVE' &&
                e.deletedAt == null,
          )
          .length;
      if (n == 0) return 'no active holder';
      final each = rowHours / n;
      return '$n ${n == 1 ? 'person' : 'people'}, ${_fmtHours(each)} each';
    }
    return _fmtHours(rowHours);
  }

  Future<void> _commitPct(WpTaskAssignment a) async {
    final raw = _controllers[a.id]?.text ?? '';
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || parsed == a.allocationPct) return;
    try {
      await ref
          .read(workforcePlanningRepositoryProvider)
          .upsertAssignment(
            WpTaskAssignment(
              id: a.id,
              companyId: widget.companyId,
              taskId: widget.taskId,
              roleScorecardId: a.roleScorecardId,
              employeeId: a.employeeId,
              assignmentRole: a.assignmentRole,
              allocationPct: parsed,
            ),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update %: $e')));
      }
    } finally {
      // Always resync, success or failure — a failed write can leave the
      // panel showing numbers the DB doesn't have, and this is cheap/idempotent.
      if (mounted) _invalidate([a.roleScorecardId]);
    }
  }

  Future<void> _delete(WpTaskAssignment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove contributor?'),
        content: Text('Remove ${_targetLabel(a)} from this accountability?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(workforcePlanningRepositoryProvider)
          .deleteAssignment(a.id);
      if (mounted) {
        _controllers.remove(a.id)?.dispose();
        _focusNodes.remove(a.id)?.dispose();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not remove: $e')));
      }
    } finally {
      if (mounted) _invalidate([a.roleScorecardId]);
    }
  }

  Future<void> _splitEqually(List<WpTaskAssignment> rows) =>
      _writeAll(rows, splitEqually(rows.length));

  Future<void> _ownerMajority(List<WpTaskAssignment> rows, int primaryIndex) =>
      _writeAll(rows, ownerMajority(rows.length, primaryIndex: primaryIndex));

  Future<void> _clear(List<WpTaskAssignment> rows) =>
      _writeAll(rows, clearAllocations(rows.length));

  Future<void> _writeAll(List<WpTaskAssignment> rows, List<double> pcts) async {
    final map = {for (var i = 0; i < rows.length; i++) rows[i].id: pcts[i]};
    try {
      await ref.read(workforcePlanningRepositoryProvider).setAllocations(map);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update allocations: $e')),
        );
      }
    } finally {
      // setAllocations is a per-row loop with no transaction, so a mid-loop
      // failure can still have persisted rows 0..k-1 — always resync.
      if (mounted) _invalidate(rows.map((r) => r.roleScorecardId));
    }
  }

  Future<void> _addContributor(List<WpTaskAssignment> rows) async {
    final existingCardIds = rows
        .map((r) => r.roleScorecardId)
        .whereType<String>()
        .toSet();
    final existingEmployeeIds = rows
        .map((r) => r.employeeId)
        .whereType<String>()
        .toSet();
    final availableCards = widget.cards
        .where((c) => !existingCardIds.contains(c.id))
        .toList();
    final availableEmployees = widget.employees
        .where((e) => !existingEmployeeIds.contains(e.id))
        .toList();

    final picked = await showDialog<_ContributorPick>(
      context: context,
      builder: (_) => _AddContributorDialog(
        cards: availableCards,
        employees: availableEmployees,
      ),
    );
    if (picked == null || !mounted) return;

    try {
      await ref
          .read(workforcePlanningRepositoryProvider)
          .upsertAssignment(
            WpTaskAssignment(
              id: '',
              companyId: widget.companyId,
              taskId: widget.taskId,
              roleScorecardId: picked.cardId,
              employeeId: picked.employeeId,
              assignmentRole: 'CONTRIBUTOR',
              allocationPct: 0,
            ),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add contributor: $e')),
        );
      }
    } finally {
      if (mounted) _invalidate([picked.cardId]);
    }
  }

  /// Mirrors `UnassignedTab._invalidate` / `TasksTab._invalidateAfterTaskChange`
  /// — an allocation write moves hours between holders, which Balance,
  /// Role View, and the role cards themselves all derive numbers from.
  void _invalidate([Iterable<String?> cardIds = const []]) {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(ownerComputedProvider);
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(wpTaskAssignmentsProvider);
    for (final id in cardIds.whereType<String>().toSet()) {
      ref.invalidate(roleScorecardByIdProvider(id));
    }
  }
}

class _ContributorPick {
  final String? cardId;
  final String? employeeId;
  const _ContributorPick({this.cardId, this.employeeId});
}

class _AddContributorDialog extends StatefulWidget {
  final List<RoleScorecard> cards;
  final List<Employee> employees;
  const _AddContributorDialog({required this.cards, required this.employees});

  @override
  State<_AddContributorDialog> createState() => _AddContributorDialogState();
}

class _AddContributorDialogState extends State<_AddContributorDialog> {
  bool _isCard = true;
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final items = _isCard
        ? [
            for (final c in widget.cards)
              DropdownMenuItem(value: c.id, child: Text(c.jobTitle)),
          ]
        : [
            for (final e in widget.employees)
              DropdownMenuItem(value: e.id, child: Text(e.fullName)),
          ];

    return AlertDialog(
      title: const Text('Add contributor'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Role card')),
                ButtonSegment(value: false, label: Text('Employee')),
              ],
              selected: {_isCard},
              onSelectionChanged: (s) => setState(() {
                _isCard = s.first;
                _selectedId = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedId,
              hint: Text(_isCard ? 'Choose a role card' : 'Choose an employee'),
              items: items,
              onChanged: (v) => setState(() => _selectedId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () => Navigator.pop(
                  context,
                  _isCard
                      ? _ContributorPick(cardId: _selectedId)
                      : _ContributorPick(employeeId: _selectedId),
                ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
