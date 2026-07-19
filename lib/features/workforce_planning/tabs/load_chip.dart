import 'package:flutter/material.dart';

import '../../../app/status_colors.dart';
import '../capacity_math.dart';

/// Load band as an app-standard StatusChip so it matches every other status
/// chip in the product (brand-tuned, light/dark aware).
class LoadStatusChip extends StatelessWidget {
  final LoadStatus status;
  const LoadStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (String label, StatusTone tone) = switch (status) {
      LoadStatus.over => ('Over', StatusTone.danger),
      LoadStatus.ok => ('OK', StatusTone.success),
      LoadStatus.under => ('Under', StatusTone.warning),
    };
    return StatusChip(label: label, tone: tone);
  }
}
