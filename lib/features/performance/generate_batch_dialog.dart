import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/quarter.dart';
import '../../data/repositories/performance_repository.dart';
import 'auto_generate.dart';

/// Confirm dialog for batch-generating performance check-ins for a chosen
/// quarter (HR/Admin). Returns the created/existed counts, or null if
/// cancelled.
Future<BatchGenResult?> showGenerateBatchDialog({
  required BuildContext context,
}) {
  return showDialog<BatchGenResult>(
    context: context,
    builder: (_) => const _GenerateBatchDialog(),
  );
}

class _GenerateBatchDialog extends ConsumerStatefulWidget {
  const _GenerateBatchDialog();

  @override
  ConsumerState<_GenerateBatchDialog> createState() =>
      _GenerateBatchDialogState();
}

class _GenerateBatchDialogState extends ConsumerState<_GenerateBatchDialog> {
  late final List<Quarter> _quarters;
  late final Quarter _currentQuarter;
  late Quarter _quarter;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentQuarter = quarterOf(now);
    _quarters = quarterOptions(now);
    _quarter = _currentQuarter;
  }

  Future<void> _generate() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await generatePerformanceCheckInsForQuarter(
        ref,
        year: _quarter.year,
        quarter: _quarter.quarter,
      );
      ref.invalidate(performanceCheckInListProvider);
      ref.invalidate(checkInPeriodNamesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate check-ins'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Creates a check-in for every active employee for the selected '
              'quarter (regular staff → quarterly; probationary → reached '
              'milestones). Existing check-ins are left untouched.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Quarter>(
              initialValue: _quarter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Quarter',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final q in _quarters)
                  DropdownMenuItem(
                    value: q,
                    child: Text(q == _currentQuarter
                        ? '${q.periodName} (current)'
                        : q.periodName),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _quarter = v ?? _quarter),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _generate,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate'),
        ),
      ],
    );
  }
}
