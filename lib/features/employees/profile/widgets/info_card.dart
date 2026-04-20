import 'package:flutter/material.dart';

import '../../../../app/status_colors.dart';

/// A bordered card with a small uppercase label and a large value below it.
/// Used for the four header tiles (Hire Date, Regularization Date, OT Eligible,
/// Reports To) and for sub-stat cards inside tabs.
class InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  const InfoCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A filled rounded chip used for status / type badges in the header and lists.
/// Pass a named [tone] for semantic color; otherwise a neutral surface tone is used.
///
/// Colors are pulled from `StatusPalette` (lib/app/status_colors.dart) — the
/// canonical brand-aligned source of truth. ChipTone is kept as a thin
/// backward-compatible alias for downstream callers.
class StatusChip extends StatelessWidget {
  final String label;
  final ChipTone tone;
  const StatusChip({super.key, required this.label, this.tone = ChipTone.neutral});

  @override
  Widget build(BuildContext context) {
    final s = StatusPalette.of(context, _toStatusTone(tone));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: s.foreground,
        ),
      ),
    );
  }

  static StatusTone _toStatusTone(ChipTone t) => switch (t) {
        ChipTone.success => StatusTone.success,
        ChipTone.warning => StatusTone.warning,
        ChipTone.danger => StatusTone.danger,
        ChipTone.info => StatusTone.info,
        ChipTone.neutral => StatusTone.neutral,
      };
}

enum ChipTone { success, warning, danger, info, neutral }

/// Tone mapping for common status strings (RELEASED, APPROVED, etc.).
ChipTone toneForStatus(String status) {
  switch (status.toUpperCase()) {
    case 'RELEASED':
    case 'APPROVED':
    case 'COMPLETED':
    case 'ACTIVE':
    case 'PAID':
    case 'DEDUCTED':
      return ChipTone.success;
    case 'REVIEW':
    case 'PENDING':
    case 'PENDING_APPROVAL':
    case 'DRAFT_IN_REVIEW':
    case 'DRAFT':
      return ChipTone.warning;
    case 'CANCELLED':
    case 'REJECTED':
    case 'RECALLED':
    case 'SEPARATED':
      return ChipTone.danger;
    default:
      return ChipTone.neutral;
  }
}
