import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/role_outcome.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../role_structure.dart';
import '../wp_providers.dart';

/// Sits between [ResponsibilitiesPane] and `KpisPane` in the role workbench:
/// this is where a manager writes the two-to-four outcomes ("customers
/// receive the correct product") that a role's KPIs will later be picked to
/// prove. Without this pane the natural failure mode is one KPI per
/// responsibility — this exists specifically to make that not the path of
/// least resistance.
///
/// Areas are NOT authored here and are NOT rows of their own: they are
/// [areasByRole]'s grouping of this card's ACTIVE `wp_tasks`, the exact same
/// derivation `ResponsibilitiesPane` and the Organization tab use. This pane
/// only ever writes `role_outcomes`, keyed on `(role_scorecard_id,
/// responsibility_area)` as a plain string match — there is no foreign key
/// from an outcome back to the area that produced it (see [RoleOutcome]'s
/// doc comment and migration `20260814000002`).
///
/// That has one direct consequence this pane has to be honest about: renaming
/// or deleting an area on the Responsibilities tab does not touch or move the
/// outcomes filed under its old name — they still exist, still count, and
/// simply stop matching any area this pane currently shows. Hiding them would
/// make a rename look consequence-free when it silently orphaned a manager's
/// prior work. Instead, an outcome whose stored area no longer appears in
/// [areasByRole] renders under a separate "Outcomes with no matching area on
/// this role" section at the bottom, labelled as exactly that, still editable
/// and still deletable — never grouped under a current area it does not
/// belong to, and never left off the pane entirely.
///
/// Like `ResponsibilitiesPane`/`KpisPane`, this pane owns its own local
/// mutable draft and its own `Save` button — the workbench deliberately has
/// no form key spanning panes, so a manager fixing one outcome must not be
/// blocked by an unrelated empty field elsewhere. Unlike `ResponsibilitiesPane`
/// (which persists every action immediately through its own dialogs), text
/// here is staged in-memory exactly like `KpisPane`'s links, with the same
/// dirty-check-before-discard on [_resync].
class OutcomesPane extends ConsumerStatefulWidget {
  const OutcomesPane({super.key, required this.cardId, required this.companyId});

  final String cardId;
  final String companyId;

  @override
  ConsumerState<OutcomesPane> createState() => _OutcomesPaneState();
}

class _OutcomesPaneState extends ConsumerState<OutcomesPane> {
  /// True once [_areas]/[_orphans] have been captured from the first
  /// successful combined load of `wpTasksProvider` and
  /// `roleOutcomesProvider`. Reset to false after this pane's own save, or by
  /// [_resync] — mirrors `KpisPane._captured`, including why: it exists to
  /// keep draft object identity stable across ordinary rebuilds (rows are
  /// keyed by `identityHashCode`), not to protect unsaved edits.
  bool _captured = false;

  final List<_AreaDraft> _areas = [];

  /// Outcomes whose stored `responsibility_area` matches none of this card's
  /// CURRENT areas. See the class doc comment for why these exist and why
  /// they are shown rather than hidden.
  final List<_OrphanDraft> _orphans = [];

  /// A structural fingerprint of [_areas]/[_orphans] as of the last
  /// successful capture, used only to decide whether [_resync] needs to
  /// confirm before discarding unsaved edits.
  List<_Snapshot> _baseline = const [];

  bool _saving = false;
  String? _error;

  void _captureFrom(List<WpTask> tasks, List<RoleOutcome> outcomes) {
    final areaNames = areasByRole(tasks)[widget.cardId] ?? const <String>[];
    _areas
      ..clear()
      ..addAll([for (final a in areaNames) _AreaDraft(a)]);
    final areaByName = {for (final a in _areas) a.area: a};
    _orphans.clear();
    for (final o in outcomes) {
      final draft = _OutcomeDraft(id: o.id, text: o.text);
      final area = areaByName[o.responsibilityArea];
      if (area != null) {
        area.outcomes.add(draft);
      } else {
        _orphans.add(_OrphanDraft(o.responsibilityArea, draft));
      }
    }
    _baseline = _snapshot();
    _captured = true;
  }

  List<_Snapshot> _snapshot() => [
    for (final a in _areas)
      for (final o in a.outcomes) (id: o.id, area: a.area, text: o.text),
    for (final orp in _orphans)
      (id: orp.outcome.id, area: orp.area, text: orp.outcome.text),
  ];

  bool get _isDirty {
    final current = _snapshot();
    if (current.length != _baseline.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != _baseline[i]) return true;
    }
    return false;
  }

  /// Every drafted outcome with non-blank text, in area order then orphan
  /// order — a blank draft (an "Add outcome" row nobody typed into) is
  /// dropped here rather than sent, matching `role_outcomes`'s
  /// `text_not_blank` check.
  List<RoleOutcome> _currentOutcomes() {
    final result = <RoleOutcome>[];
    for (final a in _areas) {
      for (final o in a.outcomes) {
        final text = o.text.trim();
        if (text.isEmpty) continue;
        result.add(
          RoleOutcome(
            id: o.id,
            companyId: widget.companyId,
            roleScorecardId: widget.cardId,
            responsibilityArea: a.area,
            text: text,
          ),
        );
      }
    }
    for (final orp in _orphans) {
      final text = orp.outcome.text.trim();
      if (text.isEmpty) continue;
      result.add(
        RoleOutcome(
          id: orp.outcome.id,
          companyId: widget.companyId,
          roleScorecardId: widget.cardId,
          responsibilityArea: orp.area,
          text: text,
        ),
      );
    }
    return result;
  }

  void _addOutcome(int areaIndex) {
    setState(
      () => _areas[areaIndex].outcomes.add(
        _OutcomeDraft(id: const Uuid().v4(), text: ''),
      ),
    );
  }

  void _removeFromArea(_AreaDraft area, _OutcomeDraft draft) {
    setState(() => area.outcomes.remove(draft));
  }

  void _removeOrphan(_OrphanDraft orphan) {
    setState(() => _orphans.remove(orphan));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final current = _currentOutcomes();
      final currentIds = current.map((o) => o.id).toSet();
      // `saveOutcomes` upserts; it never deletes a row dropped from the list
      // it is given (see its doc comment) — this pane is the caller that
      // removes them explicitly.
      final removedIds = [
        for (final s in _baseline)
          if (!currentIds.contains(s.id)) s.id,
      ];
      final repo = ref.read(roleScorecardRepositoryProvider);
      for (final id in removedIds) {
        await repo.deleteOutcome(id);
      }
      if (current.isNotEmpty) {
        await repo.saveOutcomes(widget.cardId, current);
      }
      ref.invalidate(roleOutcomesProvider(widget.cardId));
      _captured = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Outcomes saved.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Explicit resync: both providers are watched, but [_captured] only flips
  /// false right after this pane's own save (see its doc comment), so another
  /// screen changing this card's tasks or outcomes would otherwise leave
  /// [_areas]/[_orphans] silently stale. Mirrors `KpisPane._resync`: a dirty
  /// draft is confirmed before it is discarded, a pristine one reloads
  /// silently.
  Future<void> _resync() async {
    if (_isDirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard unsaved outcome changes?'),
          content: const Text(
            'Reloading replaces this pane with what is saved on the server. '
            'Anything you have typed here that has not been saved will be '
            'lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Discard and reload'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }
    ref.invalidate(wpTasksProvider);
    ref.invalidate(roleOutcomesProvider(widget.cardId));
    setState(() => _captured = false);
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(wpTasksProvider);
    final outcomesAsync = ref.watch(roleOutcomesProvider(widget.cardId));

    return tasksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load responsibility areas: $e'),
      ),
      data: (tasks) => outcomesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Could not load outcomes: $e'),
        ),
        data: (outcomes) {
          if (!_captured) _captureFrom(tasks, outcomes);
          return _build(context);
        },
      ),
    );
  }

  Widget _build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Outcomes',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_saving) ...[
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                ],
                IconButton(
                  key: const ValueKey('outcomes-pane-resync'),
                  tooltip:
                      'Reload from the server — discards unsaved changes '
                      'on this pane',
                  onPressed: _saving ? null : _resync,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'What should be true if each area\'s work is done well. Two to '
              'four per area is usually enough to guide the KPIs that prove '
              'them.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_areas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'This role has no responsibility areas yet — add '
                  'responsibilities first.',
                ),
              )
            else
              for (var i = 0; i < _areas.length; i++) _buildArea(context, i),
            if (_orphans.isNotEmpty) _buildOrphanSection(context),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArea(BuildContext context, int areaIndex) {
    final area = _areas[areaIndex];
    return Padding(
      key: ValueKey('outcome-area-${identityHashCode(area)}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            area.area,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          if (area.outcomes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                'No outcomes written for this area yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            for (final o in area.outcomes) _buildOutcomeRow(context, area, o),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: TextButton.icon(
              onPressed: _saving ? null : () => _addOutcome(areaIndex),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add outcome'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeRow(
    BuildContext context,
    _AreaDraft area,
    _OutcomeDraft draft,
  ) {
    final key = identityHashCode(draft);
    return Padding(
      key: ValueKey('outcome-row-$key'),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              // Keyed by draft identity, not list position: an unkeyed field
              // is matched positionally, so removing row i would leave every
              // surviving field showing the text of the row before it — on
              // screen the LAST row would look deleted instead of row i.
              key: ValueKey('outcome-text-$key'),
              initialValue: draft.text,
              decoration: const InputDecoration(
                hintText: 'What should be true if this area is done well',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => draft.text = v,
            ),
          ),
          IconButton(
            key: ValueKey('outcome-remove-$key'),
            tooltip: 'Remove outcome',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : () => _removeFromArea(area, draft),
          ),
        ],
      ),
    );
  }

  Widget _buildOrphanSection(BuildContext context) {
    final s = StatusPalette.of(context, StatusTone.warning);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, size: 16, color: s.foreground),
              const SizedBox(width: 6),
              Text(
                'Outcomes with no matching area on this role',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The area these were written for was renamed or removed from '
            'this role\'s responsibilities. Nothing was deleted — re-file '
            'each one under the area it now belongs to, or remove it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          for (final orp in _orphans) _buildOrphanRow(context, orp),
        ],
      ),
    );
  }

  Widget _buildOrphanRow(BuildContext context, _OrphanDraft orphan) {
    final key = identityHashCode(orphan.outcome);
    return Padding(
      key: ValueKey('outcome-orphan-row-$key'),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(label: 'was: ${orphan.area}', tone: StatusTone.warning),
                const SizedBox(height: 4),
                TextFormField(
                  key: ValueKey('outcome-orphan-text-$key'),
                  initialValue: orphan.outcome.text,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => orphan.outcome.text = v,
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('outcome-orphan-remove-$key'),
            tooltip: 'Remove outcome',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : () => _removeOrphan(orphan),
          ),
        ],
      ),
    );
  }
}

typedef _Snapshot = ({String id, String area, String text});

class _AreaDraft {
  final String area;
  final List<_OutcomeDraft> outcomes = [];
  _AreaDraft(this.area);
}

class _OutcomeDraft {
  final String id;
  String text;
  _OutcomeDraft({required this.id, required this.text});
}

/// An outcome whose stored [area] matches none of the role's current
/// [_AreaDraft]s. See [OutcomesPane]'s class doc comment.
class _OrphanDraft {
  final String area;
  final _OutcomeDraft outcome;
  _OrphanDraft(this.area, this.outcome);
}
