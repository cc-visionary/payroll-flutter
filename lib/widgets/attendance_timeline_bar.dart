import 'package:flutter/material.dart';

/// Single-day attendance timeline bar — green/red/yellow segments showing
/// worked / late-in / early-out / OT relative to the scheduled shift.
///
/// Same renderer used by:
///   - the company-wide Attendance Timeline view
///     (`lib/features/attendance/attendance_screen.dart`)
///   - the per-employee shared Attendance tab Timeline mode
///     (`lib/features/employees/profile/tabs/attendance_tab.dart`)
///
/// Pass null for any of the times to fall through to a label-only render
/// (e.g. "Absent", "No data").
class AttendanceDayTimelineBar extends StatelessWidget {
  /// Actual clock-in time (local) — minutes since 00:00 of the row's date.
  final int? actualInMin;

  /// Actual clock-out time (local) — minutes since 00:00.
  final int? actualOutMin;

  /// Scheduled shift start (local) — minutes since 00:00.
  final int? scheduledInMin;

  /// Scheduled shift end (local) — minutes since 00:00.
  final int? scheduledOutMin;

  final bool earlyInApproved;
  final bool lateOutApproved;
  final int graceMinutesLate;
  final int graceMinutesEarlyOut;

  /// Empty-state label shown when the row has no record / no clock-in
  /// (e.g. "Absent", "Rest day", "No data"). Color-coded.
  final String? emptyLabel;
  final Color? emptyLabelColor;

  /// 06:00 → 18:00 → 0..24 — the visible hour range. Default 0..24.
  final int startHour;
  final int endHour;

  const AttendanceDayTimelineBar({
    super.key,
    required this.actualInMin,
    required this.actualOutMin,
    required this.scheduledInMin,
    required this.scheduledOutMin,
    this.earlyInApproved = false,
    this.lateOutApproved = false,
    this.graceMinutesLate = 0,
    this.graceMinutesEarlyOut = 0,
    this.emptyLabel,
    this.emptyLabelColor,
    this.startHour = 0,
    this.endHour = 24,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (ctx, c) => Stack(
          children: [
            // Track
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            ..._buildSegments(c.maxWidth),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSegments(double width) {
    if (actualInMin == null) {
      final label = emptyLabel;
      if (label == null) return const [];
      return [
        Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: emptyLabelColor ?? Colors.grey,
            ),
          ),
        ),
      ];
    }

    const red = Color(0xFFEF4444);
    const yellow = Color(0xFFF59E0B);
    const green = Color(0xFF22C55E);
    final totalMin = (endHour - startHour) * 60;

    final actualIn = actualInMin!;
    final actualOut = actualOutMin;
    final schedIn = scheduledInMin;
    final schedOut = scheduledOutMin;

    final segments = <(int, int, Color, String)>[];
    String tip(int s, int e, String desc) =>
        '${_fmtTime(s)} → ${_fmtTime(e)}  •  $desc';

    if (schedIn == null || schedOut == null) {
      // No shift info — single green bar from in→out (15min if no out).
      final end = actualOut ?? actualIn + 15;
      segments.add((actualIn, end, green, tip(actualIn, end, 'Worked')));
    } else {
      // 1. Early-in OT (only when approved).
      if (actualIn < schedIn && earlyInApproved) {
        segments.add((actualIn, schedIn, green,
            tip(actualIn, schedIn, 'Early in (${schedIn - actualIn} min, approved)')));
      }
      // 2. Late-in undertime (always counted).
      if (actualIn > schedIn + graceMinutesLate) {
        final endClamped = actualIn.clamp(schedIn, schedOut);
        segments.add((schedIn, endClamped, red,
            tip(schedIn, endClamped, 'Late in (${actualIn - schedIn} min, undertime)')));
      }
      // 3. Normal worked window.
      final normStart = actualIn > schedIn ? actualIn : schedIn;
      final normEnd = actualOut == null
          ? schedOut
          : (actualOut < schedOut ? actualOut : schedOut);
      if (normEnd > normStart) {
        segments.add((normStart, normEnd, green, tip(normStart, normEnd, 'Worked')));
      }
      // 4. Early-out undertime.
      if (actualOut != null && actualOut < schedOut - graceMinutesEarlyOut) {
        segments.add((actualOut, schedOut, yellow,
            tip(actualOut, schedOut, 'Early out (${schedOut - actualOut} min, undertime)')));
      }
      // 5. Late-out OT (only when approved).
      if (actualOut != null && actualOut > schedOut && lateOutApproved) {
        segments.add((schedOut, actualOut, green,
            tip(schedOut, actualOut, 'Late out / OT (${actualOut - schedOut} min, approved)')));
      }
    }

    final ghosts = <Widget>[
      if (schedIn != null)
        _ScheduledTick(
          leftPct: (schedIn - startHour * 60) / totalMin,
          trackWidth: width,
          tooltip: 'Scheduled start ${_fmtTime(schedIn)}',
        ),
      if (schedOut != null)
        _ScheduledTick(
          leftPct: (schedOut - startHour * 60) / totalMin,
          trackWidth: width,
          tooltip: 'Scheduled end ${_fmtTime(schedOut)}',
        ),
    ];

    return [
      ...ghosts,
      for (final seg in segments)
        Positioned(
          left: ((seg.$1 - startHour * 60) / totalMin) * width,
          top: 6,
          bottom: 6,
          width: (((seg.$2 - seg.$1) / totalMin) * width).clamp(2.0, width),
          child: Tooltip(
            message: seg.$4,
            child: Container(
              decoration: BoxDecoration(
                color: seg.$3.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
    ];
  }
}

/// Hour-tick header strip (e.g. "00:00 02:00 04:00 ... 24:00") — shared
/// between the two timeline views so they line up under the same bars.
class AttendanceTimelineHeader extends StatelessWidget {
  final int startHour;
  final int endHour;
  final int labelStepHours;
  const AttendanceTimelineHeader({
    super.key,
    this.startHour = 0,
    this.endHour = 24,
    this.labelStepHours = 2,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final hours = endHour - startHour;
      final labelCount = (hours ~/ labelStepHours) + 1;
      const labelWidth = 36.0;
      return SizedBox(
        height: 20,
        child: Stack(
          clipBehavior: Clip.none,
          children: List.generate(labelCount, (i) {
            final hour = startHour + i * labelStepHours;
            final x = ((i * labelStepHours) / hours) * c.maxWidth;
            final isLast = i == labelCount - 1;
            return Positioned(
              left: isLast
                  ? (c.maxWidth - labelWidth).clamp(0.0, c.maxWidth)
                  : (x - labelWidth / 2)
                      .clamp(0.0, c.maxWidth - labelWidth),
              width: labelWidth,
              child: Text(
                '${hour.toString().padLeft(2, '0')}:00',
                textAlign: isLast ? TextAlign.right : TextAlign.left,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            );
          }),
        ),
      );
    });
  }
}

class _ScheduledTick extends StatelessWidget {
  final double leftPct;
  final double trackWidth;
  final String tooltip;
  const _ScheduledTick({
    required this.leftPct,
    required this.trackWidth,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    const hitWidth = 8.0;
    final x = leftPct * trackWidth;
    return Positioned(
      left: x - hitWidth / 2,
      top: 0,
      bottom: 0,
      width: hitWidth,
      child: Tooltip(
        message: tooltip,
        child: CustomPaint(
          painter: _DashedLinePainter(color: Colors.grey.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 3.0;
    const gap = 3.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(size.width / 2, y),
          Offset(size.width / 2, (y + dash).clamp(0, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _fmtTime(int totalMin) {
  final h = (totalMin ~/ 60) % 24;
  final m = totalMin % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
