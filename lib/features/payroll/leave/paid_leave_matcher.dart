import 'package:decimal/decimal.dart';

/// One APPROVED leave request, reduced to what paid-leave resolution needs.
/// `start`/`end` are inclusive calendar dates (UTC midnight).
class ApprovedLeaveDay {
  final DateTime start;
  final DateTime end;
  final bool isPaid;
  final String typeName;
  final Decimal leaveDays;
  const ApprovedLeaveDay({
    required this.start,
    required this.end,
    required this.isPaid,
    required this.typeName,
    required this.leaveDays,
  });
}

/// Result of resolving a single attendance date against approved leaves.
class PaidLeaveResolution {
  /// An approved request (paid or unpaid) spans this date.
  final bool covered;

  /// A PAID approved request spans this date.
  final bool isPaid;

  /// Paid fraction for the day: 0.0, 0.5, or 1.0.
  final Decimal fraction;

  /// Name of the covering paid type (null unless [isPaid]).
  final String? typeName;

  PaidLeaveResolution({
    required this.covered,
    required this.isPaid,
    required this.fraction,
    required this.typeName,
  });

  // `Decimal.zero` is a `static final` (not `const`) in the `decimal`
  // package, so `none` can't be a compile-time constant either — it's
  // built once as a static final instead.
  static final none = PaidLeaveResolution(
    covered: false,
    isPaid: false,
    fraction: Decimal.zero,
    typeName: null,
  );
}

bool _spans(ApprovedLeaveDay r, DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final s = DateTime.utc(r.start.year, r.start.month, r.start.day);
  final e = DateTime.utc(r.end.year, r.end.month, r.end.day);
  return !d.isBefore(s) && !d.isAfter(e);
}

/// Resolve whether [date] is a paid leave day. Only ON_LEAVE attendance days
/// ([statusIsLeave] true) are ever considered covered/paid here — the
/// attendance status is authoritative for "was the person on leave," and the
/// approved request supplies the paid flag, type, and fraction.
///
/// Fraction rule: a covering PAID request that is single-date with
/// leaveDays <= 0.5 pays half; everything else pays a full day. (Multi-day
/// half-day spans are rare and treated as full days — refined only if needed.)
PaidLeaveResolution resolvePaidLeaveForDay({
  required DateTime date,
  required bool statusIsLeave,
  required List<ApprovedLeaveDay> approved,
}) {
  if (!statusIsLeave) return PaidLeaveResolution.none;
  ApprovedLeaveDay? covering;
  for (final r in approved) {
    if (_spans(r, date)) {
      covering = r;
      // Prefer a paid covering request if multiple overlap.
      if (r.isPaid) break;
    }
  }
  if (covering == null) return PaidLeaveResolution.none;
  if (!covering.isPaid) {
    return PaidLeaveResolution(
      covered: true,
      isPaid: false,
      fraction: Decimal.zero,
      typeName: null,
    );
  }
  final half =
      _sameDate(covering.start, covering.end) &&
      covering.leaveDays <= Decimal.parse('0.5');
  return PaidLeaveResolution(
    covered: true,
    isPaid: true,
    fraction: half ? Decimal.parse('0.5') : Decimal.one,
    typeName: covering.typeName,
  );
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
