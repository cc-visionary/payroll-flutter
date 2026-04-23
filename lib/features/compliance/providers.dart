import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/statutory_payable.dart';
import '../../data/models/statutory_payment.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/statutory_payables_repository.dart';
import '../auth/profile_provider.dart';

/// Period selector mode — single month vs custom date range. The screen
/// defaults to [singleMonth] with the current month so HR's first
/// interaction matches the most common use case (close out last month's
/// remittances).
enum PeriodMode { singleMonth, customRange }

/// Filter state shared by the filter bar, the table, and the export action.
class CompliancePeriod {
  final PeriodMode mode;
  final int year;
  final int month;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  const CompliancePeriod({
    required this.mode,
    required this.year,
    required this.month,
    required this.rangeStart,
    required this.rangeEnd,
  });

  /// Default = current calendar year as a custom range (Jan 1 → Dec 31). HR
  /// most often opens this screen to scan year-to-date obligations across
  /// brands; a 12-month window matches that mental model better than the
  /// current month alone. The UI exposes both single-month and range modes
  /// via the toggle pills, and the user's choice survives within a session.
  factory CompliancePeriod.currentMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, 1, 1);
    final end = DateTime(now.year, 12, 31);
    return CompliancePeriod(
      mode: PeriodMode.customRange,
      year: now.year,
      month: now.month,
      rangeStart: start,
      rangeEnd: end,
    );
  }

  /// Inclusive bounds for filtering payables by their (year, month). For
  /// single-month mode this collapses to a single (y, m) pair; for range
  /// mode it spans every month touched by [rangeStart, rangeEnd].
  ({int fromYear, int fromMonth, int toYear, int toMonth}) yearMonthBounds() {
    if (mode == PeriodMode.singleMonth) {
      return (fromYear: year, fromMonth: month, toYear: year, toMonth: month);
    }
    return (
      fromYear: rangeStart.year,
      fromMonth: rangeStart.month,
      toYear: rangeEnd.year,
      toMonth: rangeEnd.month,
    );
  }

  /// Render-friendly label for the period — used in the export filename and
  /// the screen header. Single month → "March 2026"; range → "Mar 1, 2026
  /// to Mar 31, 2026".
  String label() {
    const monthsLong = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const monthsShort = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (mode == PeriodMode.singleMonth) {
      return '${monthsLong[month - 1]} $year';
    }
    String fmt(DateTime d) =>
        '${monthsShort[d.month - 1]} ${d.day}, ${d.year}';
    return '${fmt(rangeStart)} to ${fmt(rangeEnd)}';
  }

  CompliancePeriod copyWith({
    PeriodMode? mode,
    int? year,
    int? month,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) =>
      CompliancePeriod(
        mode: mode ?? this.mode,
        year: year ?? this.year,
        month: month ?? this.month,
        rangeStart: rangeStart ?? this.rangeStart,
        rangeEnd: rangeEnd ?? this.rangeEnd,
      );
}

class CompliancePeriodNotifier extends Notifier<CompliancePeriod> {
  @override
  CompliancePeriod build() => CompliancePeriod.currentMonth();

  void setSingleMonth(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    state = state.copyWith(
      mode: PeriodMode.singleMonth,
      year: year,
      month: month,
      rangeStart: start,
      rangeEnd: end,
    );
  }

  void setRange(DateTime start, DateTime end) {
    state = state.copyWith(
      mode: PeriodMode.customRange,
      rangeStart: start,
      rangeEnd: end,
    );
  }
}

final compliancePeriodProvider =
    NotifierProvider<CompliancePeriodNotifier, CompliancePeriod>(
        CompliancePeriodNotifier.new);

/// Multi-select brand filter. Empty set = "all brands".
class ComplianceBrandFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String hiringEntityId) {
    final next = Set<String>.from(state);
    if (!next.remove(hiringEntityId)) next.add(hiringEntityId);
    state = next;
  }

  void clear() => state = <String>{};
  void setAll(Iterable<String> ids) => state = ids.toSet();
}

final complianceBrandFilterProvider =
    NotifierProvider<ComplianceBrandFilterNotifier, Set<String>>(
        ComplianceBrandFilterNotifier.new);

/// Multi-select agency filter. Empty set = "all agencies".
class ComplianceAgencyFilterNotifier extends Notifier<Set<StatutoryAgency>> {
  @override
  Set<StatutoryAgency> build() => <StatutoryAgency>{};

  void toggle(StatutoryAgency a) {
    final next = Set<StatutoryAgency>.from(state);
    if (!next.remove(a)) next.add(a);
    state = next;
  }

  void clear() => state = <StatutoryAgency>{};
}

final complianceAgencyFilterProvider =
    NotifierProvider<ComplianceAgencyFilterNotifier, Set<StatutoryAgency>>(
        ComplianceAgencyFilterNotifier.new);

// ---------------------------------------------------------------------------
// Data providers
// ---------------------------------------------------------------------------

final compliancePayablesProvider =
    FutureProvider<List<StatutoryPayable>>((ref) async {
  final repo = ref.watch(statutoryPayablesRepositoryProvider);
  final p = ref.watch(compliancePeriodProvider);
  final b = p.yearMonthBounds();
  return repo.listPayables(
    fromYear: b.fromYear,
    fromMonth: b.fromMonth,
    toYear: b.toYear,
    toMonth: b.toMonth,
  );
});

final compliancePaidSummariesProvider =
    FutureProvider<List<StatutoryPaymentSummary>>((ref) async {
  final repo = ref.watch(statutoryPayablesRepositoryProvider);
  final p = ref.watch(compliancePeriodProvider);
  final b = p.yearMonthBounds();
  return repo.listPaidSummaries(
    fromYear: b.fromYear,
    fromMonth: b.fromMonth,
    toYear: b.toYear,
    toMonth: b.toMonth,
  );
});

/// Joined payable + paid summary, scoped + filtered ready for the table.
/// Computed entirely on the client so the SQL views stay simple.
class CompliancePayableRow {
  final StatutoryPayable payable;
  final StatutoryPaymentSummary? paid;

  const CompliancePayableRow({required this.payable, this.paid});

  /// Convenience: hash key for grouping / lookups.
  String get key =>
      '${payable.hiringEntityId}|${payable.periodYear}|${payable.periodMonth}|${payable.agency.dbValue}';
}

final complianceTableRowsProvider =
    FutureProvider<List<CompliancePayableRow>>((ref) async {
  final payables = await ref.watch(compliancePayablesProvider.future);
  final paid = await ref.watch(compliancePaidSummariesProvider.future);
  final brandFilter = ref.watch(complianceBrandFilterProvider);
  final agencyFilter = ref.watch(complianceAgencyFilterProvider);

  final paidByKey = <String, StatutoryPaymentSummary>{
    for (final s in paid)
      '${s.hiringEntityId}|${s.periodYear}|${s.periodMonth}|${s.agency.dbValue}':
          s,
  };

  bool brandMatches(String id) =>
      brandFilter.isEmpty || brandFilter.contains(id);
  bool agencyMatches(StatutoryAgency a) =>
      agencyFilter.isEmpty || agencyFilter.contains(a);

  return [
    for (final p in payables)
      if (brandMatches(p.hiringEntityId) && agencyMatches(p.agency))
        CompliancePayableRow(
          payable: p,
          paid: paidByKey['${p.hiringEntityId}|${p.periodYear}|${p.periodMonth}|${p.agency.dbValue}'],
        ),
  ];
});

/// Count of employees with NULL hiring_entity_id — surfaces the "Unassigned"
/// warning chip in the filter bar.
final complianceUnassignedCountProvider =
    FutureProvider<int>((ref) async {
  final repo = ref.watch(statutoryPayablesRepositoryProvider);
  final profile = await ref.watch(userProfileProvider.future);
  if (profile == null || profile.companyId.isEmpty) return 0;
  return repo.unassignedEmployeeCount(profile.companyId);
});

/// Payments rows for one (brand × period × agency) — for the View Payments
/// dialog. Family argument is the row key built from the same identifiers.
class StatutoryPaymentsQuery {
  final String hiringEntityId;
  final int periodYear;
  final int periodMonth;
  final StatutoryAgency agency;
  const StatutoryPaymentsQuery({
    required this.hiringEntityId,
    required this.periodYear,
    required this.periodMonth,
    required this.agency,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StatutoryPaymentsQuery &&
          other.hiringEntityId == hiringEntityId &&
          other.periodYear == periodYear &&
          other.periodMonth == periodMonth &&
          other.agency == agency);

  @override
  int get hashCode =>
      Object.hash(hiringEntityId, periodYear, periodMonth, agency);
}

final statutoryPaymentsProvider = FutureProvider.family<List<StatutoryPayment>,
    StatutoryPaymentsQuery>((ref, q) async {
  final repo = ref.watch(statutoryPayablesRepositoryProvider);
  return repo.listPayments(
    hiringEntityId: q.hiringEntityId,
    periodYear: q.periodYear,
    periodMonth: q.periodMonth,
    agency: q.agency,
  );
});

/// Per-employee breakdown for one (brand × period × agency).
final statutoryBreakdownProvider = FutureProvider.family<
    List<StatutoryPayableBreakdownRow>, StatutoryPaymentsQuery>((ref, q) async {
  final repo = ref.watch(statutoryPayablesRepositoryProvider);
  return repo.listBreakdown(
    hiringEntityId: q.hiringEntityId,
    periodYear: q.periodYear,
    periodMonth: q.periodMonth,
    agency: q.agency,
  );
});

/// Re-export the hiring-entity list provider so widgets in this feature can
/// import a single file.
final complianceBrandsProvider = hiringEntityListProvider;

// ---------------------------------------------------------------------------
// Sidebar notification badge — pending statutory payables
// ---------------------------------------------------------------------------

/// Count of (brand × month × agency) payable rows that are still owing
/// (amount paid total < amount due) across the current month and any prior
/// months that haven't been fully settled. Drives the Compliance nav badge.
///
/// Permission-gated to HR/Admin to mirror the nav-item visibility.
/// Refreshes itself every 60s after the initial fetch so the badge reflects
/// remittances made in another tab/session within roughly a minute.
class PendingStatutoryPayablesCountNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final profile = await ref.watch(userProfileProvider.future);
    if (profile == null || !profile.isHrOrAdmin) return 0;

    final repo = ref.watch(statutoryPayablesRepositoryProvider);

    // Window: from the start of an arbitrary "lookback" 24 months back so
    // we always catch unpaid older months without scanning the whole table.
    // (The view only emits rows for periods that had released payslips, so
    // this is bounded.) The upper bound is the current month — future-period
    // payables don't exist yet.
    final now = DateTime.now();
    final fromDate = DateTime(now.year - 2, now.month, 1);

    final payables = await repo.listPayables(
      fromYear: fromDate.year,
      fromMonth: fromDate.month,
      toYear: now.year,
      toMonth: now.month,
    );
    final paid = await repo.listPaidSummaries(
      fromYear: fromDate.year,
      fromMonth: fromDate.month,
      toYear: now.year,
      toMonth: now.month,
    );

    final paidByKey = <String, StatutoryPaymentSummary>{
      for (final s in paid)
        '${s.hiringEntityId}|${s.periodYear}|${s.periodMonth}|${s.agency.dbValue}':
            s,
    };

    var count = 0;
    for (final p in payables) {
      final key =
          '${p.hiringEntityId}|${p.periodYear}|${p.periodMonth}|${p.agency.dbValue}';
      final paidAmount = paidByKey[key]?.amountPaid;
      final status = classifyPayable(p.amountDue, paidAmount ?? Decimal.zero);
      // Anything that isn't fully settled (Unpaid / Partial) counts. Overpaid
      // is treated as "settled" — variance is surfaced separately in the
      // ledger UI, not as a badge.
      if (status == PayableStatus.unpaid || status == PayableStatus.partial) {
        count++;
      }
    }

    // Schedule a self-refresh after 60s. `Future.delayed` is fire-and-forget
    // — Riverpod auto-disposes the AsyncNotifier when no widgets watch it,
    // and `invalidateSelf` on a disposed provider is a no-op.
    Future.delayed(const Duration(seconds: 60), () {
      ref.invalidateSelf();
    });

    return count;
  }
}

final pendingStatutoryPayablesCountProvider =
    AsyncNotifierProvider<PendingStatutoryPayablesCountNotifier, int>(
        PendingStatutoryPayablesCountNotifier.new);
