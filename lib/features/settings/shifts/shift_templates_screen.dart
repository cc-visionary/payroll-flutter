import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/shift_template.dart';
import '../../../data/repositories/shift_template_repository.dart';
import '../../auth/profile_provider.dart';
import '../../lark/lark_repository.dart';
import '../../../widgets/syncing_dialog.dart';

class ShiftTemplatesScreen extends ConsumerStatefulWidget {
  const ShiftTemplatesScreen({super.key});
  @override
  ConsumerState<ShiftTemplatesScreen> createState() => _State();
}

class _State extends ConsumerState<ShiftTemplatesScreen> {
  bool _syncing = false;
  String? _summary;
  List<String> _errors = const [];

  Future<void> _sync() async {
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    setState(() { _syncing = true; _summary = null; _errors = const []; });
    try {
      final res = await runWithSyncingDialog(
        context,
        'Shift Templates',
        () => ref.read(larkRepositoryProvider).syncShifts(profile.companyId),
      );
      setState(() {
        _summary = 'Synced: ${res.created} created, ${res.updated} updated'
            '${res.errors.isNotEmpty ? " — ${res.errors.length} error(s)" : ""}';
        _errors = res.errors;
      });
      ref.invalidate(shiftTemplateListProvider);
      ref.invalidate(syncHistoryProvider);
    } catch (e) {
      setState(() { _summary = 'Error: $e'; _errors = const []; });
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(shiftTemplateListProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Shift Templates', style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          FilledButton.icon(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: const Text('Sync from Lark'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text('Shift templates are synced from Lark. Click "Sync from Lark" to fetch the latest shifts.',
            style: TextStyle(color: Colors.grey)),
        if (_summary != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_summary!)),
        if (_errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE6E6),
                border: Border.all(color: const Color(0xFFFFB3B3)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF8A1F1F))),
                  const SizedBox(height: 4),
                  for (final e in _errors)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: SelectableText('• $e', style: const TextStyle(color: Color(0xFF8A1F1F), fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No shift templates yet. Click "Sync from Lark".'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _ShiftTile(shift: rows[i]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _ShiftTile extends ConsumerWidget {
  final ShiftTemplate shift;
  const _ShiftTile({required this.shift});

  String _fmt(String t) => t.substring(0, 5);

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${shift.code}"?'),
        content: const Text(
          'This permanently removes the shift template. If any attendance '
          'record or role scorecard still references it, the delete will fail '
          'and the row will stay.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shiftTemplateRepositoryProvider).delete(shift.id);
      ref.invalidate(shiftTemplateListProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Shift "${shift.code}" deleted.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = (shift.scheduledWorkMinutes / 60).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(shift.code,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(width: 8),
                Chip(
                    label: Text(shift.name),
                    visualDensity: VisualDensity.compact),
                const SizedBox(width: 8),
                if (shift.isOvernight)
                  const Chip(
                      label: Text('Overnight'),
                      backgroundColor: Color(0xFFF5E6FF),
                      visualDensity: VisualDensity.compact),
                if (shift.isFromLark) ...[
                  const SizedBox(width: 4),
                  const Chip(
                      label: Text('Lark'),
                      backgroundColor: Color(0xFFE6F0FF),
                      visualDensity: VisualDensity.compact),
                ],
              ]),
              const SizedBox(height: 4),
              Text(
                '${_fmt(shift.startTime)} – ${_fmt(shift.endTime)} '
                '• ${shift.breakMinutes} min break'
                '${shift.breakStartTime != null ? " (${_fmt(shift.breakStartTime!)}–${_fmt(shift.breakEndTime!)})" : ""}'
                ' • ${shift.graceMinutesLate} min grace',
                style: const TextStyle(color: Colors.grey),
              ),
              Text('$hours hours work time',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }
}
