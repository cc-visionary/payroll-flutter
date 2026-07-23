import '../../app/status_colors.dart';

/// Tinted, borderless chip tone for a criticality level (null = no chip).
StatusTone? criticalityTone(String? c) {
  switch (c) {
    case 'CRITICAL':
      return StatusTone.danger;
    case 'HIGH':
      return StatusTone.warning;
    case 'MEDIUM':
      return StatusTone.info;
    case 'LOW':
      return StatusTone.neutral;
    default:
      return null;
  }
}

/// Human label for a criticality level (null = unset).
String? criticalityLabel(String? c) =>
    (c == null || criticalityTone(c) == null)
        ? null
        : '${c[0]}${c.substring(1).toLowerCase()}';
