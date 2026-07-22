import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../app/theme.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../auth/profile_provider.dart';
import '../wp_providers.dart';
import 'role_view_tab.dart' show ownerComputedProvider;
import 'tab_intro.dart';

/// HR-facing Drivers & Scenario editor: the growth-multiplier scenario
/// control, plus create/edit for `wp_drivers` and `wp_rates` — the two
/// scaling inputs a `wp_tasks` row can reference for its times/minutes.
/// Mirrors `KpiLibraryScreen`'s dialog-open/SnackBar/invalidate pattern and
/// `BalanceTab`'s async gates.
///
/// No delete here: the Plan 1 repository has no `deleteDriver`/`deleteRate`
/// (the `wp_tasks` FKs are `on delete set null`, so a delete would be safe
/// at the DB layer, but the write path isn't built) — create/edit only,
/// with delete left as a follow-up.
///
/// Every save invalidates the providers whose numbers derive from
/// drivers/rates/config through `wp_person_load` and `wp_task_computed`
/// (`wpPersonLoadsProvider`, `ownerComputedProvider`), plus the tab's own
/// read provider, so Balance and Role View never show stale hours.
class DriversScenarioTab extends ConsumerWidget {
  const DriversScenarioTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driversAsync = ref.watch(wpDriversProvider);
    final ratesAsync = ref.watch(wpRatesProvider);
    final configAsync = ref.watch(wpConfigProvider);
    final companyId = ref.watch(userProfileProvider).asData?.value?.companyId;

    if (driversAsync.isLoading || ratesAsync.isLoading || configAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = driversAsync.error ?? ratesAsync.error ?? configAsync.error;
    if (err != null) {
      return Center(
        child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
      );
    }

    final drivers = driversAsync.asData!.value;
    final rates = ratesAsync.asData!.value;
    final multiplier = ref.watch(wpGrowthMultiplierProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TabIntro(
              purpose: 'The volume numbers and per-unit rates the hours are '
                  'calculated from.',
              details: [
                (
                  term: 'Driver',
                  meaning: 'A volume the business runs at — orders per month, '
                      'inquiries per month. A task bound to one is recalculated '
                      'whenever the driver changes.',
                ),
                (
                  term: 'Rate',
                  meaning: 'Minutes one unit of work takes — 8 minutes to pick '
                      'and pack an order. Times × minutes ÷ 60 = hours/month.',
                ),
                (
                  term: 'Grows',
                  meaning: 'Marks a driver as demand-sensitive. ONLY tasks bound '
                      'to a growing driver respond to the multiplier below; a '
                      'manual hours figure stays flat at any scenario.',
                ),
                WpGlossary.multiplier,
              ],
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, 'Scenario'),
            const SizedBox(height: 12),
            _scenarioCard(context, ref, multiplier, companyId),
            const SizedBox(height: 32),
            _sectionHeader(context, 'Drivers'),
            const SizedBox(height: 12),
            _driversSection(context, ref, drivers, companyId),
            const SizedBox(height: 32),
            _sectionHeader(context, 'Rates'),
            const SizedBox(height: 12),
            _ratesSection(context, ref, rates, companyId),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );

  // ── Scenario ─────────────────────────────────────────────────────────

  Widget _scenarioCard(
    BuildContext context,
    WidgetRef ref,
    double multiplier,
    String? companyId,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Growth multiplier',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '${multiplier.toStringAsFixed(1)}×',
                  style: AppTheme.mono(context,
                      fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scales growing drivers for projected load on the Balance '
                  'and Role View tabs. 1.0× = current.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: companyId == null
                ? null
                : () => _openMultiplierDialog(context, ref, companyId, multiplier),
            child: const Text('Set multiplier'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMultiplierDialog(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    double current,
  ) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _MultiplierDialog(initial: current),
    );
    if (result == null) return;
    try {
      await ref
          .read(workforcePlanningRepositoryProvider)
          .setGrowthMultiplier(companyId, result);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update multiplier: $e')),
      );
      return;
    }
    ref.invalidate(wpConfigProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(ownerComputedProvider);
  }

  // ── Drivers ──────────────────────────────────────────────────────────

  Widget _driversSection(
    BuildContext context,
    WidgetRef ref,
    List<WpDriver> drivers,
    String? companyId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: FilledButton.icon(
            onPressed: companyId == null
                ? null
                : () => _openDriverForm(context, ref, companyId),
            icon: const Icon(Icons.add),
            label: const Text('New driver'),
          ),
        ),
        const SizedBox(height: 12),
        if (drivers.isEmpty)
          const Text('No drivers yet. Click "New driver".')
        else
          for (final d in drivers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DriverRow(
                driver: d,
                onEdit: companyId == null
                    ? null
                    : () => _openDriverForm(context, ref, companyId, existing: d),
              ),
            ),
      ],
    );
  }

  Future<void> _openDriverForm(
    BuildContext context,
    WidgetRef ref,
    String companyId, {
    WpDriver? existing,
  }) async {
    final result = await showDialog<WpDriver>(
      context: context,
      builder: (_) => _DriverDialog(existing: existing, companyId: companyId),
    );
    if (result == null) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).saveDriver(result);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save driver: $e')),
      );
      return;
    }
    ref.invalidate(wpDriversProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(ownerComputedProvider);
  }

  // ── Rates ────────────────────────────────────────────────────────────

  Widget _ratesSection(
    BuildContext context,
    WidgetRef ref,
    List<WpRate> rates,
    String? companyId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: FilledButton.icon(
            onPressed: companyId == null
                ? null
                : () => _openRateForm(context, ref, companyId),
            icon: const Icon(Icons.add),
            label: const Text('New rate'),
          ),
        ),
        const SizedBox(height: 12),
        if (rates.isEmpty)
          const Text('No rates yet. Click "New rate".')
        else
          for (final r in rates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RateRow(
                rate: r,
                onEdit: companyId == null
                    ? null
                    : () => _openRateForm(context, ref, companyId, existing: r),
              ),
            ),
      ],
    );
  }

  Future<void> _openRateForm(
    BuildContext context,
    WidgetRef ref,
    String companyId, {
    WpRate? existing,
  }) async {
    final result = await showDialog<WpRate>(
      context: context,
      builder: (_) => _RateDialog(existing: existing, companyId: companyId),
    );
    if (result == null) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).saveRate(result);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save rate: $e')),
      );
      return;
    }
    ref.invalidate(wpRatesProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(ownerComputedProvider);
  }
}

// ── Rows ───────────────────────────────────────────────────────────────

class _DriverRow extends StatelessWidget {
  final WpDriver driver;
  final VoidCallback? onEdit;
  const _DriverRow({required this.driver, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              driver.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              driver.value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: AppTheme.mono(context),
            ),
          ),
          const SizedBox(width: 12),
          StatusChip(
            label: driver.grows ? 'Grows' : 'Fixed',
            tone: driver.grows ? StatusTone.info : StatusTone.neutral,
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
          ],
        ],
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  final WpRate rate;
  final VoidCallback? onEdit;
  const _RateRow({required this.rate, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rate.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              '${rate.minutesEach.toStringAsFixed(1)} min',
              textAlign: TextAlign.right,
              style: AppTheme.mono(context),
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
          ],
        ],
      ),
    );
  }
}

// ── Dialogs ────────────────────────────────────────────────────────────

/// Small numeric dialog for the scenario growth multiplier. 0.5–5.0 in
/// 0.5 steps (9 divisions); the current value is echoed in `AppTheme.mono`
/// above the slider.
class _MultiplierDialog extends StatefulWidget {
  final double initial;
  const _MultiplierDialog({required this.initial});

  @override
  State<_MultiplierDialog> createState() => _MultiplierDialogState();
}

class _MultiplierDialogState extends State<_MultiplierDialog> {
  late double _value = widget.initial.clamp(0.5, 5.0).toDouble();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set growth multiplier'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_value.toStringAsFixed(1)}×',
              style: AppTheme.mono(context, fontSize: 24, fontWeight: FontWeight.w600),
            ),
            Slider(
              value: _value,
              min: 0.5,
              max: 5.0,
              divisions: 9,
              label: '${_value.toStringAsFixed(1)}×',
              onChanged: (v) => setState(() => _value = v),
            ),
            Text(
              'Scales growing drivers across Balance and Role View. '
              '1.0× = current.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
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
          onPressed: () => Navigator.pop(context, _value),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Create/edit dialog for a `wp_drivers` row. Caller persists the returned
/// [WpDriver] via `WorkforcePlanningRepository.saveDriver`.
class _DriverDialog extends StatefulWidget {
  final WpDriver? existing;
  final String companyId;
  const _DriverDialog({this.existing, required this.companyId});

  @override
  State<_DriverDialog> createState() => _DriverDialogState();
}

class _DriverDialogState extends State<_DriverDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _value =
      TextEditingController(text: (widget.existing?.value ?? 0).toString());
  late bool _grows = widget.existing?.grows ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final driver = WpDriver(
      id: widget.existing?.id ?? '',
      companyId: widget.existing?.companyId ?? widget.companyId,
      name: _name.text.trim(),
      value: double.tryParse(_value.text.trim()) ?? 0,
      grows: _grows,
      note: widget.existing?.note,
      sortOrder: widget.existing?.sortOrder ?? 0,
    );
    Navigator.pop(context, driver);
  }

  InputDecoration _dec(String label) => InputDecoration(
      labelText: label, border: const OutlineInputBorder(), isDense: true);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New driver' : 'Edit driver'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _name, autofocus: true, decoration: _dec('Name')),
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppTheme.mono(context),
                decoration: _dec('Value'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _grows,
                onChanged: (v) => setState(() => _grows = v),
                title: const Text('Grows with the multiplier'),
                subtitle: const Text(
                  'Scaled by the scenario growth multiplier when a task '
                  'references this driver.',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Create/edit dialog for a `wp_rates` row. Caller persists the returned
/// [WpRate] via `WorkforcePlanningRepository.saveRate`.
class _RateDialog extends StatefulWidget {
  final WpRate? existing;
  final String companyId;
  const _RateDialog({this.existing, required this.companyId});

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _minutes = TextEditingController(
      text: (widget.existing?.minutesEach ?? 0).toString());
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final rate = WpRate(
      id: widget.existing?.id ?? '',
      companyId: widget.existing?.companyId ?? widget.companyId,
      name: _name.text.trim(),
      minutesEach: double.tryParse(_minutes.text.trim()) ?? 0,
      note: widget.existing?.note,
    );
    Navigator.pop(context, rate);
  }

  InputDecoration _dec(String label) => InputDecoration(
      labelText: label, border: const OutlineInputBorder(), isDense: true);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New rate' : 'Edit rate'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _name, autofocus: true, decoration: _dec('Name')),
              const SizedBox(height: 12),
              TextField(
                controller: _minutes,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppTheme.mono(context),
                decoration: _dec('Minutes each'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
