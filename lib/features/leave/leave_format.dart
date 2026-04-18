/// Formats a leave as "{duration} {unit}" using Lark's original values when
/// available (unit: 1=day, 2=half-day, 0=hour). Falls back to "{leave_days} days"
/// when Lark didn't provide a unit/duration (manual or pre-sync rows).
String formatLeaveDurationUnit({
  required Object? larkUnit,
  required Object? larkDuration,
  required Object? leaveDays,
}) {
  final unit = larkUnit is num ? larkUnit.toInt() : int.tryParse('${larkUnit ?? ''}');
  final duration = larkDuration is num
      ? larkDuration.toDouble()
      : double.tryParse('${larkDuration ?? ''}');
  if (unit != null && duration != null && duration > 0) {
    final label = _unitLabel(unit, duration);
    if (label != null) return '${_trimNumber(duration)} $label';
  }
  final days = leaveDays is num
      ? leaveDays.toDouble()
      : double.tryParse('${leaveDays ?? ''}');
  if (days != null) return '${_trimNumber(days)} ${days == 1 ? "day" : "days"}';
  return '—';
}

String? _unitLabel(int unit, double duration) {
  switch (unit) {
    case 1: return duration == 1 ? 'day' : 'days';
    case 2: return duration == 1 ? 'half-day' : 'half-days';
    case 0: return duration == 1 ? 'hr' : 'hrs';
  }
  return null;
}

String _trimNumber(double n) {
  if (n == n.roundToDouble()) return n.toStringAsFixed(0);
  final s = n.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}
