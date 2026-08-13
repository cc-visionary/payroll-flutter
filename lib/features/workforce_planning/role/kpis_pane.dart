import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/kpi.dart';
import '../../../data/models/kpi_goal.dart';
import '../../../data/models/role_kpi.dart';
import '../../../data/models/role_outcome.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../documents/providers.dart' show roleScorecardByIdProvider;
import '../../kpi_library/kpi_definition_form.dart';
import '../../kpi_library/kpi_measurable.dart';
import '../../kpi_library/kpi_reading.dart';
import '../removal_lifecycle.dart';
import '../tabs/role_view_tab.dart' show ownerComputedProvider;
import '../wp_providers.dart';

/// Fixed sample counts for the live preview only — never sent anywhere. They
/// exist purely so a manager editing a goal can see roughly what a reading
/// against it would look like before any real numbers exist. Chosen simply:
/// 3 out of 100, a plausible "a few things happened out of a normal-sized
/// batch" for a RATIO/PERCENT KPI; for a plain COUNT/CURRENCY/DURATION KPI
/// only the numerator (3) is used.
const _previewNumerator = 3.0;
const _previewDenominator = 100.0;

/// The third pane of the role workbench: this card's `role_scorecard_kpis`
/// links — what bar THIS role must clear on each measurable. The `kpis`
/// library row (name, unit, cadence, and the EOS definition fields) is
/// authored elsewhere (the KPI Library dialog, or inline here for a
/// brand-new KPI via [KpiDefinitionForm]); this pane only ever edits the
/// per-role goal.
///
/// `target` and `frequency` are legacy free-text columns the card PDF and
/// contract templates still read. They are DERIVED here — from the
/// structured [KpiGoal] and the KPI's cadence — and never typed into
/// directly, so they can never drift from the goal a manager actually set.
///
/// Like [ResponsibilitiesPane], this pane holds its own local mutable draft
/// list and has one `Save` button at the bottom, because
/// `saveRoleScorecardKpis` replaces a card's entire KPI-link set in one call
/// — it is not built for incremental per-row saves.
class KpisPane extends ConsumerStatefulWidget {
  const KpisPane({super.key, required this.cardId, required this.companyId});

  final String cardId;
  final String companyId;

  @override
  ConsumerState<KpisPane> createState() => _KpisPaneState();
}

class _KpisPaneState extends ConsumerState<KpisPane> {
  /// True once [_links] has been captured from `roleKpisProvider`'s first
  /// successful load in this build cycle. Reset to false right after this
  /// pane's own successful save, so the NEXT provider emission (post
  /// invalidation) re-captures fresh server state rather than trusting local
  /// optimistic state — see `ResponsibilitiesPane._captured` for the same
  /// pattern and its rationale.
  bool _captured = false;
  final List<_KpiLinkDraft> _links = [];

  /// The editable state of [_links] as of the last successful capture —
  /// compared structurally against the CURRENT state to decide whether
  /// [_resync] needs to ask before discarding anything (see [_isDirty]).
  /// Never sent anywhere; this is UI-only bookkeeping.
  List<_DraftSnapshot> _baseline = const [];

  /// Whether each baseline link (by kpiId) was measurable AT THE MOMENT it
  /// was captured — i.e. the same `isMeasurableForRole` reading `_buildRow`
  /// renders, taken once and frozen. Absent (no entry) means "unknown": the
  /// library hadn't finished loading yet when this capture ran, so nothing
  /// meaningful was recorded rather than a guessed true/false that could
  /// later read as a false regression once the library actually resolves.
  ///
  /// This is what lets the Save guard (see `build`'s `blockedLinks`) tell
  /// "always-been-unmeasurable legacy debt" (grandfathered — see the
  /// sibling-preservation test) apart from "became unmeasurable since this
  /// pane last captured" (blocked — e.g. the KPI Library dialog stripped its
  /// formula or source while this pane sat open with the same baseline).
  /// `_DraftSnapshot` deliberately does not carry this: that snapshot drives
  /// `_isDirty`, which is about USER-EDITED fields, and measurability is
  /// never user-edited directly.
  Map<String, bool> _baselineMeasurableByKpiId = {};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final d in _links) {
      d.dispose();
    }
    super.dispose();
  }

  void _captureFrom(
    List<RoleKpi> kpis,
    Map<String, Kpi> libraryById, {
    required bool libraryLoaded,
  }) {
    // Recapturing replaces every draft wholesale (initial load, post-save,
    // or an explicit resync) — the outgoing drafts' controllers are not
    // referenced anywhere else, so they must be disposed here rather than
    // leaked.
    for (final d in _links) {
      d.dispose();
    }
    _links
      ..clear()
      ..addAll(kpis.map(_KpiLinkDraft.fromRoleKpi));
    _baseline = _links.map(_DraftSnapshot.of).toList();
    _baselineMeasurableByKpiId = libraryLoaded
        ? {
            for (final d in _links)
              if (d.kpiId != null)
                d.kpiId!: isMeasurableForRole(
                  defined: _definitionGaps(d, libraryById).isEmpty,
                  goal: d.goal,
                ),
          }
        : const {};
    _captured = true;
  }

  /// Whether anything in [_links] has changed since [_baseline] was taken —
  /// an added/removed row, a different KPI, or an edited goal. Used only to
  /// decide whether [_resync] needs to confirm before discarding.
  bool get _isDirty {
    if (_links.length != _baseline.length) return true;
    for (var i = 0; i < _links.length; i++) {
      if (_DraftSnapshot.of(_links[i]) != _baseline[i]) return true;
    }
    return false;
  }

  void _invalidateAfterSave() {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(ownerComputedProvider);
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(wpTaskAssignmentsProvider);
    ref.invalidate(roleScorecardByIdProvider(widget.cardId));
    ref.invalidate(roleKpisProvider(widget.cardId));
    // Adding/removing a role->KPI link changes what the Needs-attention
    // strip's "N roles with no KPI" signal sees (it reads `card.kpis`
    // straight off roleScorecardListProvider, already invalidated above) and
    // the KPI Library's people and roles counts for every KPI added to or
    // removed from this card — without these the library can show a
    // role/people count that no longer matches what was just saved until
    // something else happens to invalidate them.
    ref.invalidate(kpiAssignedEmployeesProvider);
    ref.invalidate(kpiRoleTitlesProvider);
    // Force a resync from the next successful load rather than trust local
    // state, which a partially-failed save could have left disagreeing with
    // the server.
    _captured = false;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // A row with neither a picked/created kpiId nor a name typed into it
      // describes nothing yet — skip it rather than send a link the
      // repository can't resolve.
      final saveable = _links.where((d) => d.name.trim().isNotEmpty).toList();
      final links = [
        for (final d in saveable)
          KpiLinkInput(
            kpiId: d.kpiId,
            name: d.name.trim(),
            // Only a link that arrived WITHOUT a stored goal forwards its
            // legacy `target`. This pane cannot save one row at a time (see
            // the class comment), so every link on the card rides in every
            // save with `writeGoal: true` below — including the ones the
            // manager never looked at. For those, `target` is untouched prose
            // that predates goals ("Consistently high quality"), the only
            // copy of it that exists, and what role_card_pdf.dart and the
            // contract's Annex A print; sending '' would have the repository
            // write NULL over it.
            //
            // A link that DID arrive with a goal is genuinely this pane's to
            // author: its stored `target` was DERIVED from that goal, so
            // sending nothing is what lets clearing the goal also clear the
            // text, instead of resurrecting a bar nobody holds.
            target: d.hadStoredGoal ? '' : (d.legacyTarget ?? ''),
            frequency: d.legacyFrequency ?? '',
            goal: d.goal,
            unit: d.unit,
            // Required. The repository's saveRoleScorecardKpis deliberately
            // does NOT fall back to `kpi.cadence` for an existing library KPI
            // (see that method's comment) because it previously silently
            // rewrote every link's frequency to "Weekly" on any card save.
            // This pane is the caller that must supply the real value on
            // every link — sourced from the picked library KPI, or from the
            // KpiDefinitionForm draft for a brand-new one, never a bare
            // 'WEEKLY' default written by this pane itself.
            cadence: d.cadence,
            // This pane renders the goal editor, so a null goal here means
            // "this role has no goal for this KPI" and must be written as
            // such — otherwise clearing the direction dropdown would appear
            // to work and change nothing. A caller with no goal editor would
            // leave this false, meaning "no opinion", and the repository
            // would preserve whatever goal is already stored. This pane is
            // currently the only caller, so that branch has no live user —
            // see saveRoleScorecardKpis for why it is nonetheless kept.
            writeGoal: true,
            // Always sent, never conditionally omitted — see
            // KpiLinkInput.outcomeId. This pane saves every link on the card
            // in every call, so a null here must mean "no outcome", not "no
            // opinion".
            outcomeId: d.outcomeId,
          ),
      ];
      await ref
          .read(roleScorecardRepositoryProvider)
          .saveRoleScorecardKpis(widget.cardId, widget.companyId, links);
      _invalidateAfterSave();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('KPIs saved.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addExisting(Kpi kpi) {
    setState(() {
      _links.add(
        _KpiLinkDraft(
          kpiId: kpi.id,
          name: kpi.name,
          unit: kpi.unit,
          cadence: kpi.cadence,
          valueType: kpi.valueType,
          numeratorLabel: kpi.numeratorLabel,
          numeratorSource: kpi.numeratorSource,
          denominatorLabel: kpi.denominatorLabel,
          denominatorSource: kpi.denominatorSource,
        ),
      );
    });
  }

  void _remove(_KpiLinkDraft draft) {
    setState(() => _links.remove(draft));
    draft.dispose();
  }

  /// Explicit resync: `roleKpisProvider` is watched, but [_captured] only
  /// flips false right after THIS pane's own save (see its doc comment), so
  /// another screen invalidating the same provider — e.g. the KPI Library
  /// dialog editing this KPI's unit, or a different workbench tab touching
  /// the card — would otherwise leave [_links] silently stale beside a
  /// provider that has already moved on (the exact gap Task 4's
  /// `ResponsibilitiesPane` was flagged for and never closed).
  ///
  /// This discards unsaved local edits, same trade-off `_invalidateAfterSave`
  /// already makes after a successful save — but unlike that path, nothing
  /// here has actually been saved, so a dirty draft is confirmed first. A
  /// pristine one reloads silently.
  Future<void> _resync() async {
    if (_isDirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard unsaved KPI changes?'),
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
    ref.invalidate(roleKpisProvider(widget.cardId));
    // The outcome picker's options come from this provider too — a resync
    // means the role's outcomes may have changed underneath us as well (e.g.
    // OutcomesPane, or another session), and a stale option list could name
    // an outcome that no longer exists.
    ref.invalidate(roleOutcomesProvider(widget.cardId));
    // Same reasoning as _invalidateAfterSave: a resync means this card's
    // on-role KPI set may have changed underneath us (e.g. another session's
    // edit). Unlike _invalidateAfterSave, nothing here invalidates
    // roleScorecardListProvider by another path, so it is invalidated
    // explicitly — the Needs-attention strip's "N roles with no KPI" signal
    // reads `card.kpis` straight off it, and would otherwise show this
    // card's PRE-resync KPI count until something else happened to refresh
    // it. The KPI Library's people/roles counts are read fresh from their
    // own providers for the same reason.
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(kpiAssignedEmployeesProvider);
    ref.invalidate(kpiRoleTitlesProvider);
    setState(() => _captured = false);
  }

  @override
  Widget build(BuildContext context) {
    final kpisAsync = ref.watch(roleKpisProvider(widget.cardId));
    final libraryAsync = ref.watch(kpiLibraryProvider);
    final library = libraryAsync.asData?.value ?? const <Kpi>[];
    final libraryById = {for (final k in library) k.id: k};
    final outcomes =
        ref.watch(roleOutcomesProvider(widget.cardId)).asData?.value ??
        const <RoleOutcome>[];

    return kpisAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load KPIs: $e'),
      ),
      data: (kpis) {
        if (!_captured) {
          _captureFrom(kpis, libraryById, libraryLoaded: libraryAsync.hasValue);
        }
        // Pure inheritance sharpens what used to be `validateKpiSet`'s job:
        // that function refused to let an EMPLOYEE be curated onto an
        // unmeasurable KPI. There is no curation step left to refuse at —
        // linking a KPI to a role now assigns it to every holder the moment
        // this saves.
        //
        // Not a blanket "every link must be measurable" gate: a legacy card
        // can carry KPIs that only ever had a typed prose target and no
        // library definition (see the sibling-preservation save path
        // below), and requiring the whole card to become measurable before
        // an unrelated edit could be saved would make that legacy content
        // un-editable. A currently-unmeasurable link is only blocked when:
        //   (a) it is NEW this session (absent from `_baseline` — a manager
        //       adding a brand-new, still-undefined KPI today, landing on
        //       every holder with zero friction), or
        //   (b) it REGRESSED since this pane's last capture — it read as
        //       measurable then (`_baselineMeasurableByKpiId[kpiId] ==
        //       true`) and does not now. This is the case a blanket "skip
        //       everything in baseline" gate missed: the KPI Library dialog
        //       can strip a formula or source from a KPI already linked to
        //       this role, at any time, from a completely different screen,
        //       and this pane must not keep saving that link as if nothing
        //       changed just because it predates this editing session.
        // An always-been-unmeasurable link (`_baselineMeasurableByKpiId
        // [kpiId] == false`) or one with no recorded baseline reading at all
        // (library hadn't loaded at capture time — unknown, not false) is
        // grandfathered: nothing proves it got WORSE, so an unrelated save
        // must still go through.
        final blockedLinks = _links.where((d) {
          final gaps = _definitionGaps(d, libraryById);
          if (isMeasurableForRole(defined: gaps.isEmpty, goal: d.goal)) {
            return false;
          }
          final isNew = !_baseline.any((b) => b.kpiId == d.kpiId);
          if (isNew) return true;
          return _baselineMeasurableByKpiId[d.kpiId] == true;
        }).length;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'KPIs',
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
                      key: const ValueKey('kpis-pane-resync'),
                      tooltip:
                          'Reload from the server — discards unsaved changes '
                          'on this pane',
                      onPressed: _saving ? null : _resync,
                      icon: const Icon(Icons.refresh),
                    ),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _showAddDialog(context, library),
                      icon: const Icon(Icons.add),
                      label: const Text('Add KPI'),
                    ),
                  ],
                ),
                if (_links.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No KPIs are tracked on this role yet.'),
                  )
                else
                  for (final draft in _links)
                    _buildRow(context, draft, libraryById, outcomes),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                if (blockedLinks > 0) ...[
                  const SizedBox(height: 12),
                  _hint(
                    context,
                    StatusTone.danger,
                    '$blockedLinks newly added KPI(s) are not measurable yet '
                    '— every holder of this role would inherit it the moment '
                    'this saves. Give it a goal and a complete definition, '
                    'or remove it, before saving.',
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      key: const ValueKey('kpis-pane-save'),
                      onPressed: (_saving || blockedLinks > 0) ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Whether [draft] is "defined" for measurability purposes. An existing
  /// library KPI's definition fields aren't carried on the `RoleKpi` row (its
  /// embed only selects name/unit/cadence), so they're cross-referenced
  /// against the full library list here. A brand-new draft carries its own
  /// definition fields directly (from the [KpiDefinitionForm] the manager
  /// just filled in). Either way, a library row that can't be found (still
  /// loading, or not in the active list) is treated as not-defined — a safe
  /// default, never a crash.
  List<String> _definitionGaps(
    _KpiLinkDraft draft,
    Map<String, Kpi> libraryById,
  ) {
    final lib = draft.kpiId == null ? null : libraryById[draft.kpiId];
    return kpiDefinitionGaps(
      valueType: lib?.valueType ?? draft.valueType,
      unit: lib?.unit ?? draft.unit,
      numeratorLabel: lib?.numeratorLabel ?? draft.numeratorLabel,
      numeratorSource: lib?.numeratorSource ?? draft.numeratorSource,
      denominatorLabel: lib?.denominatorLabel ?? draft.denominatorLabel,
      denominatorSource: lib?.denominatorSource ?? draft.denominatorSource,
    );
  }

  /// Names what is actually missing, rather than always saying "set a goal".
  /// A KPI needs both a goal on THIS role and a complete library definition;
  /// telling a manager to set a goal they have already set, when the real gap
  /// is a missing numerator source in the library, sends them to the wrong
  /// screen.
  String _notMeasurableHint(List<String> gaps, bool hasGoal) {
    if (!hasGoal && gaps.isEmpty) {
      return 'This KPI is not measurable yet — set a goal.';
    }
    final definition =
        'its definition is incomplete (${gaps.join(', ')}) — edit it in the '
        'KPI Library';
    if (hasGoal) {
      return 'This KPI is not measurable yet — $definition.';
    }
    return 'This KPI is not measurable yet — set a goal, and $definition.';
  }

  Widget _buildRow(
    BuildContext context,
    _KpiLinkDraft draft,
    Map<String, Kpi> libraryById,
    List<RoleOutcome> outcomes,
  ) {
    final key = identityHashCode(draft);
    // Computed even when there is no goal: the hint below names every gap,
    // and a row missing both a goal and a formula must say so.
    final gaps = _definitionGaps(draft, libraryById);
    final measurable = isMeasurableForRole(
      defined: gaps.isEmpty,
      goal: draft.goal,
    );
    final suggestion = draft.goal == null && (draft.legacyTarget ?? '').isNotEmpty
        ? parseLegacyTarget(draft.legacyTarget)
        : null;

    double? previewValue;
    if (draft.goal != null) {
      previewValue = computeReadingValue(
        valueType: draft.valueType,
        unit: draft.unit,
        numerator: _previewNumerator,
        denominator: _previewDenominator,
      );
    }
    final onTrack = isOnTrack(previewValue, draft.goal);

    return Padding(
      key: ValueKey('kpi-row-$key'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.name.isEmpty ? '(unnamed KPI)' : draft.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (draft.cadence != null) ...[
                Text(
                  frequencyLabelFromCadence(draft.cadence) ?? draft.cadence!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                key: ValueKey('kpi-remove-$key'),
                tooltip: 'Remove KPI',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  // removalActionForKpiLink always returns delete today
                  // (Spec B, not yet built, is what would ever flip
                  // hasLogs to true) — wired in now so that future flip is
                  // a one-line change.
                  final action = removalActionForKpiLink(hasLogs: false);
                  if (action == RemovalAction.delete) _remove(draft);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _goalEditor(context, draft, key),
          const SizedBox(height: 8),
          _outcomePicker(context, draft, key, outcomes),
          const SizedBox(height: 6),
          if (draft.goal != null)
            Text(
              'Goal: ${formatGoal(draft.goal!, draft.unit)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          if (!measurable)
            _hint(
              context,
              StatusTone.warning,
              _notMeasurableHint(gaps, draft.goal != null),
            ),
          if (suggestion != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _hint(
                    context,
                    StatusTone.info,
                    'Suggested: ${formatGoal(suggestion, draft.unit)}',
                  ),
                ),
                TextButton(
                  key: ValueKey('kpi-accept-suggestion-$key'),
                  onPressed: () => setState(() {
                    draft.direction = suggestion.direction;
                    // Written to the controllers, not the plain-string
                    // getters — the Value/To fields bind these controllers
                    // directly, so this is what actually makes the accepted
                    // suggestion visible on screen (a stable row key means
                    // TextFormField.initialValue would never be re-read).
                    draft.valueController.text = suggestion.value.toString();
                    draft.valueMaxController.text =
                        suggestion.valueMax?.toString() ?? '';
                  }),
                  child: const Text('Use suggestion'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Preview (sample ${_previewNumerator.toInt()}/'
            '${_previewDenominator.toInt()}): '
            '${previewValue == null ? '—' : previewValue.toStringAsFixed(1)}'
            ' · ${onTrack == null ? '—' : (onTrack ? 'on track' : 'off track')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, StatusTone tone, String text) {
    final color = StatusPalette.of(context, tone).foreground;
    return Text(text, style: TextStyle(fontSize: 12, color: color));
  }

  /// Which `role_outcomes` row this link proves. Lists every outcome AUTHORED
  /// ON THIS ROLE — including one whose stored area matches none of the
  /// role's current responsibility areas (`OutcomesPane`'s "orphan" case) —
  /// grouped by the area string each outcome is filed under, plus a
  /// "— none —" option.
  ///
  /// Deliberately not filtered down to only outcomes on the role's CURRENT
  /// areas: an outcome does not stop existing just because the area it was
  /// written under got renamed on the Responsibilities tab, and a picker that
  /// hid it would not make that KPI's proof go away — it would just make a
  /// manager who can no longer find it recreate a duplicate. `OutcomesPane`
  /// makes the same call for its own orphan section, for the same reason.
  Widget _outcomePicker(
    BuildContext context,
    _KpiLinkDraft draft,
    int key,
    List<RoleOutcome> outcomes,
  ) {
    final byArea = <String, List<RoleOutcome>>{};
    for (final o in outcomes) {
      (byArea[o.responsibilityArea] ??= []).add(o);
    }
    final ids = outcomes.map((o) => o.id).toSet();
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('— none —')),
    ];
    for (final entry in byArea.entries) {
      items.add(
        DropdownMenuItem<String?>(
          // A header, not a choice — this pane groups by area for
          // readability only; the link still points straight at the outcome,
          // never at the area (see [RoleOutcome]'s doc comment on why an
          // area is not a row this could point to instead).
          enabled: false,
          value: ' header:${entry.key}',
          child: Text(
            entry.key,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      for (final o in entry.value) {
        items.add(
          DropdownMenuItem<String?>(value: o.id, child: Text('  ${o.text}')),
        );
      }
    }
    // Defensive: `roleOutcomesProvider` and `roleKpisProvider` resolve
    // independently, so the very first frame can show a KPI whose stored
    // outcomeId isn't in [outcomes] yet (still loading) — or, more
    // permanently, one that pointed at an outcome since deleted elsewhere.
    // `outcome_id` is `on delete set null`, so the latter self-heals on the
    // next load; either way, a value with no matching item throws inside
    // DropdownButtonFormField (it asserts exactly one match), so give it a
    // placeholder entry rather than crash the pane.
    if (draft.outcomeId != null && !ids.contains(draft.outcomeId)) {
      items.add(
        DropdownMenuItem<String?>(
          value: draft.outcomeId,
          child: const Text('(loading outcome…)'),
        ),
      );
    }
    return SizedBox(
      width: 360,
      child: DropdownButtonFormField<String?>(
        key: ValueKey('kpi-outcome-picker-$key'),
        initialValue: draft.outcomeId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Proves outcome',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: items,
        onChanged: (v) => setState(() => draft.outcomeId = v),
      ),
    );
  }

  Widget _goalEditor(BuildContext context, _KpiLinkDraft draft, int key) {
    final isBetween = draft.direction == GoalDirection.between;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<GoalDirection?>(
            key: ValueKey('kpi-direction-$key'),
            initialValue: draft.direction,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Goal',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('(none)')),
              DropdownMenuItem(value: GoalDirection.gte, child: Text('≥')),
              DropdownMenuItem(value: GoalDirection.lte, child: Text('≤')),
              DropdownMenuItem(value: GoalDirection.eq, child: Text('=')),
              DropdownMenuItem(
                value: GoalDirection.between,
                child: Text('between'),
              ),
            ],
            onChanged: (v) => setState(() => draft.direction = v),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: TextFormField(
            key: ValueKey('kpi-value-$key'),
            controller: draft.valueController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: isBetween ? 'From' : 'Value',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            // The controller already holds the latest text; this only needs
            // to trigger a rebuild so the derived goal/preview text below
            // catches up.
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (isBetween) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: ValueKey('kpi-value-max-$key'),
              controller: draft.valueMaxController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'To',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            (draft.unit == null || draft.unit!.trim().isEmpty)
                ? '(no unit)'
                : draft.unit!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Future<void> _showAddDialog(BuildContext context, List<Kpi> library) async {
    final result = await showDialog<_AddKpiResult>(
      context: context,
      builder: (_) => _AddKpiDialog(companyId: widget.companyId, library: library),
    );
    if (result == null) return;
    if (result.existing != null) {
      _addExisting(result.existing!);
    } else if (result.newDraft != null) {
      await _createAndAddLibraryKpi(result.newName!, result.newDraft!);
    }
  }

  /// Creates the library row for an inline-defined KPI, WITH its definition,
  /// then links the row by the returned id.
  ///
  /// The definition has to be written here because [KpiLinkInput] carries
  /// only unit and cadence: routing a brand-new KPI through
  /// `saveRoleScorecardKpis`'s find-or-create instead inserted it as
  /// `value_type = 'COUNT'` with a null numerator, whatever the manager had
  /// just filled in — so the KPI read "not measurable yet" forever and could
  /// never join anyone's tracked set. `saveLibraryKpi` already accepts all
  /// eight definition fields; widening `KpiLinkInput` (and the `Kpi` the
  /// repository builds from it) would have duplicated that surface for no
  /// gain.
  ///
  /// Creating the row at Add time rather than at Save time also means the
  /// library is the single author of library rows — `saveLibraryKpi` resolves
  /// the name case-insensitively and reactivates a retired match, exactly as
  /// picking an existing KPI would have.
  Future<void> _createAndAddLibraryKpi(
    String name,
    KpiDefinitionDraft draft,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(roleScorecardRepositoryProvider)
          .saveLibraryKpi(
            companyId: widget.companyId,
            name: name,
            measurementUnit: draft.unit,
            valueType: draft.valueType,
            numeratorLabel: draft.numeratorLabel,
            numeratorSource: draft.numeratorSource,
            denominatorLabel: draft.denominatorLabel,
            denominatorSource: draft.denominatorSource,
            unit: draft.unit,
            // From the KpiDefinitionForm's emitted draft — that form defaults
            // its own cadence to 'WEEKLY' until the manager changes it. This
            // pane must never hardcode a bare 'WEEKLY' itself.
            cadence: draft.cadence,
            proofType: draft.proofType,
            writeDefinition: true,
          );
      // The picker, the name-resolution list and the source autocomplete all
      // read the library; a KPI created here must show up in each of them
      // without a reload.
      ref.invalidate(kpiLibraryProvider);
      ref.invalidate(kpiLibraryAllProvider);
      ref.invalidate(kpiSourcesProvider);
      if (!mounted) return;
      _addExisting(created);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the KPI: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// A local, not-yet-persisted draft of one `role_scorecard_kpis` link. Direct
/// text fields ([value], [valueMax]) back the goal editor; [goal] derives
/// from them for the preview and the eventual save.
class _KpiLinkDraft {
  String? kpiId;
  String name;
  String? unit;
  String? cadence;

  // Definition fields, only meaningful for a brand-new (kpiId == null) draft
  // — an existing library KPI's definition is looked up by kpiId instead.
  String? valueType;
  String? numeratorLabel;
  String? numeratorSource;
  String? denominatorLabel;
  String? denominatorSource;

  String? legacyTarget;
  String? legacyFrequency;

  /// The `role_outcomes` row this link proves, or null for "none picked".
  /// See role_outcomes (20260814000002).
  String? outcomeId;

  /// Whether this link already carried a structured goal when it was loaded.
  ///
  /// A load-time fact, never edited — clearing the goal editor does not make
  /// this false. It is the one thing the repository cannot know and the pane
  /// can, and it decides whether [legacyTarget] is prose worth preserving (no
  /// stored goal → it is the only copy) or merely the previous goal's derived
  /// rendering (stored goal → clearing the goal must clear it too). See the
  /// `target:` argument in `_KpisPaneState._save`.
  ///
  /// False for a row added in this session: a brand-new link has no history
  /// to protect.
  final bool hadStoredGoal;

  GoalDirection? direction;

  /// Backed by controllers, not plain strings: `TextFormField.initialValue`
  /// is read once and never revisited by `didUpdateWidget`, so a programmatic
  /// change (e.g. "Use suggestion") that only wrote a new string into a
  /// stable-keyed row would update [goal] and the derived preview text but
  /// leave the on-screen field showing the OLD number — the exact bug this
  /// was built to prevent. `_goalEditor` binds these directly.
  final TextEditingController valueController;
  final TextEditingController valueMaxController;

  String get value => valueController.text;
  String get valueMax => valueMaxController.text;

  _KpiLinkDraft({
    required this.kpiId,
    required this.name,
    this.unit,
    this.cadence,
    this.valueType,
    this.numeratorLabel,
    this.numeratorSource,
    this.denominatorLabel,
    this.denominatorSource,
    this.legacyTarget,
    this.legacyFrequency,
    this.outcomeId,
    this.hadStoredGoal = false,
    this.direction,
    String? initialValue,
    String? initialValueMax,
  }) : valueController = TextEditingController(text: initialValue ?? ''),
       valueMaxController = TextEditingController(text: initialValueMax ?? '');

  /// Must be called once this draft is no longer displayed (removed, or
  /// replaced wholesale by a recapture) — `TextFormField` never disposes a
  /// controller it did not create itself.
  void dispose() {
    valueController.dispose();
    valueMaxController.dispose();
  }

  factory _KpiLinkDraft.fromRoleKpi(RoleKpi kpi) => _KpiLinkDraft(
    kpiId: kpi.kpiId,
    name: kpi.name,
    unit: kpi.unit,
    cadence: kpi.cadence,
    legacyTarget: kpi.target,
    legacyFrequency: kpi.frequency,
    outcomeId: kpi.outcomeId,
    hadStoredGoal: kpi.goal != null,
    direction: kpi.goal?.direction,
    initialValue: kpi.goal == null ? '' : _trim(kpi.goal!.value),
    initialValueMax: kpi.goal?.valueMax == null
        ? ''
        : _trim(kpi.goal!.valueMax!),
  );

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// The structured goal this draft currently describes, or null if the
  /// manager hasn't picked a direction/value yet.
  KpiGoal? get goal {
    final d = direction;
    if (d == null) return null;
    final v = double.tryParse(value.trim());
    if (v == null) return null;
    if (d == GoalDirection.between) {
      final vMax = double.tryParse(valueMax.trim());
      if (vMax == null || vMax <= v) return null;
      return KpiGoal(direction: d, value: v, valueMax: vMax);
    }
    return KpiGoal(direction: d, value: v);
  }
}

/// A structural fingerprint of one draft's editable fields — kpiId, name,
/// goal direction and both value texts. Used only to detect whether
/// [_KpisPaneState] has anything unsaved before [_KpisPaneState._resync]
/// discards it; never sent anywhere.
class _DraftSnapshot {
  final String? kpiId;
  final String name;
  final GoalDirection? direction;
  final String value;
  final String valueMax;
  final String? outcomeId;

  const _DraftSnapshot({
    required this.kpiId,
    required this.name,
    required this.direction,
    required this.value,
    required this.valueMax,
    required this.outcomeId,
  });

  factory _DraftSnapshot.of(_KpiLinkDraft d) => _DraftSnapshot(
    kpiId: d.kpiId,
    name: d.name,
    direction: d.direction,
    value: d.value,
    valueMax: d.valueMax,
    outcomeId: d.outcomeId,
  );

  @override
  bool operator ==(Object other) =>
      other is _DraftSnapshot &&
      other.kpiId == kpiId &&
      other.name == name &&
      other.direction == direction &&
      other.value == value &&
      other.valueMax == valueMax &&
      other.outcomeId == outcomeId;

  @override
  int get hashCode =>
      Object.hash(kpiId, name, direction, value, valueMax, outcomeId);
}

class _AddKpiResult {
  final Kpi? existing;
  final String? newName;
  final KpiDefinitionDraft? newDraft;
  _AddKpiResult.existing(this.existing) : newName = null, newDraft = null;
  _AddKpiResult.newKpi(this.newName, this.newDraft) : existing = null;
}

/// "Add KPI": pick an existing library KPI by name, or define a brand-new
/// one inline via [KpiDefinitionForm] when the typed name doesn't match.
/// Mirrored the old (now-deleted) responsibility-card editor's `_kpiEditor`
/// Autocomplete pattern, minus its free-text target/frequency fields — this
/// pane derives those, it never collects them directly.
class _AddKpiDialog extends ConsumerStatefulWidget {
  const _AddKpiDialog({required this.companyId, required this.library});

  final String companyId;
  final List<Kpi> library;

  @override
  ConsumerState<_AddKpiDialog> createState() => _AddKpiDialogState();
}

class _AddKpiDialogState extends ConsumerState<_AddKpiDialog> {
  final _nameCtl = TextEditingController();
  Kpi? _picked;
  KpiDefinitionDraft _newDraft = KpiDefinitionDraft();

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  /// Case-insensitive exact match against the library. Typing a KPI's exact
  /// name must resolve to that KPI just as reliably as clicking its
  /// Autocomplete suggestion does — a manager who types the full correct
  /// name and presses Save without clicking the row must never fall into
  /// the "define a new KPI" branch, which would seed the link's cadence from
  /// [KpiDefinitionForm]'s bare default instead of this KPI's real one.
  ///
  /// Matches against [kpiLibraryAllProvider] (every row, active or not) —
  /// NOT `widget.library` (active-only, the Autocomplete's suggestion
  /// source). `upsertKpi` resolves a name against every row server-side and
  /// silently reactivates a deactivated match, so a manager who types a
  /// retired KPI's exact name (correctly absent from suggestions) must still
  /// get that KPI's real cadence rather than an accidental new one. Falls
  /// back to `widget.library` while the wider list is still loading, so an
  /// active KPI still resolves immediately rather than waiting on a second
  /// fetch.
  Kpi? _matchByName(String name) {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return null;
    final all = ref.read(kpiLibraryAllProvider).asData?.value ?? widget.library;
    for (final k in all) {
      if (k.name.trim().toLowerCase() == target) return k;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sources =
        ref.watch(kpiSourcesProvider).asData?.value ?? const <String>[];
    // Watched (not just read from `_matchByName`) so that once this
    // provider's fetch resolves, this dialog rebuilds and a name typed
    // before it loaded gets re-resolved without needing another keystroke.
    ref.watch(kpiLibraryAllProvider);
    final typedMatchesExisting = _picked != null;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add KPI', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Autocomplete<Kpi>(
                initialValue: TextEditingValue(text: _nameCtl.text),
                optionsBuilder: (v) => v.text.isEmpty
                    ? widget.library
                    : widget.library.where(
                        (k) => k.name.toLowerCase().contains(
                          v.text.toLowerCase(),
                        ),
                      ),
                displayStringForOption: (k) => k.name,
                onSelected: (k) => setState(() {
                  _picked = k;
                  _nameCtl.text = k.name;
                }),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'KPI name',
                      helperText:
                          'Pick an existing KPI, or type a new name to '
                          'define one.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      _nameCtl.text = v;
                      // Re-resolve on every keystroke rather than only on a
                      // suggestion tap: a name that now exactly matches a
                      // library KPI (however it got typed) IS that KPI.
                      _picked = _matchByName(v);
                    }),
                  );
                },
              ),
              if (!typedMatchesExisting && _nameCtl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                KpiDefinitionForm(
                  knownSources: sources,
                  onChanged: (d) => _newDraft = d,
                ),
              ] else if (_picked != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Unit: ${_picked!.unit ?? '(none)'} · '
                  'Cadence: ${_picked!.cadence}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // _picked can resolve to a deactivated row (typed by exact
                // name, not offered as a suggestion) — the server reactivates
                // it silently on save, so the manager deserves to know that
                // is what "Add" is about to do here.
                if (!_picked!.isActive) ...[
                  const SizedBox(height: 4),
                  Text(
                    'This KPI was retired — adding it here reactivates it.',
                    style: TextStyle(
                      fontSize: 12,
                      color: StatusPalette.of(
                        context,
                        StatusTone.warning,
                      ).foreground,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final name = _nameCtl.text.trim();
                      if (name.isEmpty) return;
                      // Re-check by name here too, belt-and-braces: whatever
                      // got the field into its current text, an exact match
                      // against the library must never be treated as new.
                      final matched = _picked ?? _matchByName(name);
                      if (matched != null) {
                        Navigator.pop(context, _AddKpiResult.existing(matched));
                      } else {
                        Navigator.pop(
                          context,
                          _AddKpiResult.newKpi(name, _newDraft),
                        );
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
