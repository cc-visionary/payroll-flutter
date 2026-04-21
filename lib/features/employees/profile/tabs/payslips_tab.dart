import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/money.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/payroll_repository.dart';
import '../widgets/info_card.dart';

class PayslipsTab extends ConsumerStatefulWidget {
  final Employee employee;
  const PayslipsTab({super.key, required this.employee});

  @override
  ConsumerState<PayslipsTab> createState() => _PayslipsTabState();
}

class _PayslipsTabState extends ConsumerState<PayslipsTab> {
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, 1, 1);
    _to = DateTime(now.year, 12, 31);
  }

  Future<void> _pick(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payslipsByEmployeeProvider(
      PayslipsByEmployeeQuery(
        employeeId: widget.employee.id,
        from: _from,
        to: _to,
      ),
    ));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _DateRangeBar(
          from: _from,
          to: _to,
          onPickFrom: () => _pick(true),
          onPickTo: () => _pick(false),
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
          ),
          data: (items) {
            final totals = _Totals.from(items);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalsRow(totals: totals),
                const SizedBox(height: 12),
                _ThirteenthMonthCard(
                  employeeId: widget.employee.id,
                  from: _from,
                  to: _to,
                ),
                const SizedBox(height: 16),
                _History(items: items),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _DateRangeBar extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  const _DateRangeBar({
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('From'),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onPickFrom,
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text(from.toIso8601String().substring(0, 10)),
        ),
        const SizedBox(width: 16),
        const Text('To'),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onPickTo,
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text(to.toIso8601String().substring(0, 10)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Totals {
  final Decimal gross;
  final Decimal deductions;
  final Decimal net;
  final Decimal tax;
  final Decimal sss;
  final Decimal philhealth;
  final Decimal pagibig;
  const _Totals({
    required this.gross,
    required this.deductions,
    required this.net,
    required this.tax,
    required this.sss,
    required this.philhealth,
    required this.pagibig,
  });

  Decimal get benefits => sss + philhealth + pagibig;

  factory _Totals.from(List<PayslipWithPeriod> items) {
    var gross = Decimal.zero;
    var ded = Decimal.zero;
    var net = Decimal.zero;
    var tax = Decimal.zero;
    var sss = Decimal.zero;
    var ph = Decimal.zero;
    var pi = Decimal.zero;
    for (final it in items) {
      gross += it.payslip.grossPay;
      ded += it.payslip.totalDeductions;
      net += it.payslip.netPay;
      tax += it.payslip.withholdingTax;
      sss += it.payslip.sssEe;
      ph += it.payslip.philhealthEe;
      pi += it.payslip.pagibigEe;
    }
    return _Totals(
      gross: gross,
      deductions: ded,
      net: net,
      tax: tax,
      sss: sss,
      philhealth: ph,
      pagibig: pi,
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final _Totals totals;
  const _TotalsRow({required this.totals});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _Totalcard(
        title: 'Total Gross Pay',
        value: Money.fmtPhp(totals.gross),
        bg: const Color(0xFFEFF6FF),
        fg: const Color(0xFF1D4ED8),
      ),
      _Totalcard(
        title: 'Total Deductions',
        value: Money.fmtPhp(totals.deductions),
        bg: const Color(0xFFFEF2F2),
        fg: const Color(0xFFB91C1C),
      ),
      _Totalcard(
        title: 'Total Net Pay',
        value: Money.fmtPhp(totals.net),
        bg: const Color(0xFFECFDF5),
        fg: const Color(0xFF047857),
      ),
      _Totalcard(
        title: 'Total Withholding Tax',
        value: Money.fmtPhp(totals.tax),
        bg: const Color(0xFFFEFCE8),
        fg: const Color(0xFF854D0E),
      ),
      _Totalcard(
        title: 'Total Benefits (EE)',
        value: Money.fmtPhp(totals.benefits),
        bg: const Color(0xFFF5F3FF),
        fg: const Color(0xFF6D28D9),
        subtitle:
            'SSS: ${Money.fmtPhp(totals.sss)} · PhilHealth: ${Money.fmtPhp(totals.philhealth)} · Pag-IBIG: ${Money.fmtPhp(totals.pagibig)}',
      ),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 1200
          ? 5
          : c.maxWidth >= 900
              ? 3
              : c.maxWidth >= 600
                  ? 2
                  : 1;
      const spacing = 12.0;
      // Chunk cards into rows; wrap each row in IntrinsicHeight so every card
      // in that row shares the tallest card's height, even when one has a
      // multi-line subtitle (e.g. the benefits breakdown).
      final rows = <List<Widget>>[];
      for (int i = 0; i < cards.length; i += cols) {
        rows.add(cards.sublist(
          i,
          (i + cols) > cards.length ? cards.length : i + cols,
        ));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: spacing),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) const SizedBox(width: spacing),
                    Expanded(child: rows[r][i]),
                  ],
                  // Fill trailing space in the last row so the cards
                  // don't stretch across the full width when there are
                  // fewer than `cols` items left.
                  for (int i = rows[r].length; i < cols; i++) ...[
                    const SizedBox(width: spacing),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _Totalcard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Color bg;
  final Color fg;
  const _Totalcard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.85)),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _History extends StatelessWidget {
  final List<PayslipWithPeriod> items;
  const _History({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              'Payslip History',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No payslips in this date range.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: Theme.of(context).dividerColor),
              _PayslipRow(item: items[i]),
            ],
        ],
      ),
    );
  }
}

class _PayslipRow extends StatelessWidget {
  final PayslipWithPeriod item;
  const _PayslipRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = item.payslip;
    final periodText = item.periodStart == null || item.periodEnd == null
        ? '—'
        : '${item.periodStart!.toIso8601String().substring(0, 10)} - ${item.periodEnd!.toIso8601String().substring(0, 10)}';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      periodText,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    StatusChip(
                      label: p.approvalStatus == 'DRAFT_IN_REVIEW'
                          ? 'REVIEW'
                          : p.approvalStatus,
                      tone: toneForStatus(p.approvalStatus),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Pay date: ${item.payDate == null ? '—' : item.payDate!.toIso8601String().substring(0, 10)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Gross: ${Money.fmtPhp(p.grossPay)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'Deductions: -${Money.fmtPhp(p.totalDeductions)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Net Pay',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Money.fmtPhp(p.netPay),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/payslips/${p.id}'),
                icon: const Icon(Icons.picture_as_pdf, size: 14),
                label: const Text('PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Full-width breakdown of the 13th-month accrual within the current date
/// range. Computed live from `payslip_lines` on RELEASED runs whose period
/// overlaps the range — no stored running value, no drift.
/// Payout = `(Σ basic − Σ late) ÷ 12`, applied once at the total row.
class _ThirteenthMonthCard extends ConsumerWidget {
  final String employeeId;
  final DateTime from;
  final DateTime to;
  const _ThirteenthMonthCard({
    required this.employeeId,
    required this.from,
    required this.to,
  });

  static const _bg = Color(0xFFEEF2FF);
  static const _fg = Color(0xFF4338CA);
  static const _fgSoft = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(thirteenthMonthBreakdownProvider(
      ThirteenthMonthBreakdownQuery(
        employeeId: employeeId,
        from: from,
        to: to,
      ),
    ));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '13th Month Accrued',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _fg,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Payout at year-end or separation · Scoped to selected date range',
                      style: TextStyle(fontSize: 11, color: _fgSoft),
                    ),
                  ],
                ),
              ),
              async.when(
                loading: () => const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const Text(
                  '—',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _fg,
                  ),
                ),
                data: (bd) => Text(
                  Money.fmtPhp(bd.thirteenthMonthPayout),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Formula: (Σ Basic Pay − Σ Late/UT) ÷ 12',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _fg,
                fontFamily: 'GeistMono',
              ),
            ),
          ),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (e, _) => Text(
              'Could not load breakdown: $e',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
            ),
            data: (bd) {
              if (bd.contributions.isEmpty) {
                return Text(
                  'No released payslips in this date range.',
                  style: TextStyle(fontSize: 12, color: _fg.withValues(alpha: 0.8)),
                );
              }
              return _ThirteenthMonthTable(breakdown: bd);
            },
          ),
        ],
      ),
    );
  }
}

class _ThirteenthMonthTable extends StatelessWidget {
  final ThirteenthMonthBreakdown breakdown;
  const _ThirteenthMonthTable({required this.breakdown});

  List<ThirteenthMonthContribution> get contributions => breakdown.contributions;

  static const _fg = _ThirteenthMonthCard._fg;
  static const _fgSoft = _ThirteenthMonthCard._fgSoft;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _periodLabel(ThirteenthMonthContribution c) {
    final s = c.periodStart;
    final e = c.periodEnd;
    if (s == null && e == null) {
      return c.payDate == null
          ? '—'
          : 'Pay ${_fmtDate(c.payDate!)}';
    }
    if (s != null && e != null) {
      final sameMonth = s.year == e.year && s.month == e.month;
      if (sameMonth) {
        return '${_monthNames[s.month - 1]} ${s.day}–${e.day}, ${s.year}';
      }
      final sameYear = s.year == e.year;
      if (sameYear) {
        return '${_monthNames[s.month - 1]} ${s.day} – '
            '${_monthNames[e.month - 1]} ${e.day}, ${s.year}';
      }
      return '${_fmtDate(s)} – ${_fmtDate(e)}';
    }
    return _fmtDate((s ?? e)!);
  }

  String _fmtDate(DateTime d) =>
      '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final divider = Colors.white.withValues(alpha: 0.7);

    TableRow header() => TableRow(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.45),
          ),
          children: [
            _th('Period'),
            _th('Basic Pay', end: true),
            _th('Late/UT', end: true),
            _th('Net Basic', end: true),
          ],
        );

    TableRow rowFor(ThirteenthMonthContribution c) => TableRow(
          children: [
            _cell(_periodLabel(c)),
            _basicPayCell(c),
            _cell(
              c.lateDeduction <= Decimal.zero
                  ? '—'
                  : '−${Money.fmtPhp(c.lateDeduction)}',
              end: true,
              mono: true,
              color: c.lateDeduction <= Decimal.zero
                  ? _fgSoft
                  : const Color(0xFFB91C1C),
            ),
            _cell(Money.fmtPhp(c.netBasic),
                end: true, mono: true, bold: true),
          ],
        );

    TableRow totalRow() => TableRow(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: divider, width: 1)),
          ),
          children: [
            _cell('Total (${contributions.length} '
                'release${contributions.length == 1 ? "" : "s"})',
                bold: true),
            _cell(Money.fmtPhp(breakdown.totalBasic),
                end: true, mono: true, bold: true),
            _cell(
              breakdown.totalLate <= Decimal.zero
                  ? '—'
                  : '−${Money.fmtPhp(breakdown.totalLate)}',
              end: true,
              mono: true,
              bold: true,
              color: breakdown.totalLate <= Decimal.zero
                  ? _fgSoft
                  : const Color(0xFFB91C1C),
            ),
            _cell(Money.fmtPhp(breakdown.totalNetBasic),
                end: true, mono: true, bold: true),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2.4),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.1),
            3: FlexColumnWidth(1.2),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            header(),
            for (final c in contributions) rowFor(c),
            totalRow(),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '13th Month = ${Money.fmtPhp(breakdown.totalNetBasic)} ÷ 12',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _fg,
                    fontFamily: 'GeistMono',
                  ),
                ),
              ),
              Text(
                Money.fmtPhp(breakdown.thirteenthMonthPayout),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _fg,
                  fontFamily: 'GeistMono',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _th(String text, {bool end = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          text,
          textAlign: end ? TextAlign.end : TextAlign.start,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _fg,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget _cell(
    String text, {
    bool end = false,
    bool mono = false,
    bool bold = false,
    Color? color,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Text(
          text,
          textAlign: end ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            fontFamily: mono ? 'GeistMono' : null,
            color: color ?? _fg,
          ),
        ),
      );

  /// Renders the Basic Pay cell showing each `days × daily wage` bucket on its
  /// own line, with the payslip's total beneath in bold. Monthly-wage rows
  /// come through with `days == 0 && rate == 0` — we skip the composition
  /// line there and just show the total.
  Widget _basicPayCell(ThirteenthMonthContribution c) {
    final items = c.basicItems
        .where((i) => i.days > Decimal.zero && i.rate > Decimal.zero)
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final i in items)
            Text(
              '${_fmtDays(i.days)} × ${Money.fmtPhp(i.rate)}',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'GeistMono',
                color: _fgSoft,
              ),
            ),
          if (items.isNotEmpty) const SizedBox(height: 2),
          Text(
            Money.fmtPhp(c.basicPay),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'GeistMono',
              color: _fg,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDays(Decimal d) {
    // Drop trailing zeros — "10.000" → "10", "9.500" → "9.5".
    final s = d.toString();
    if (!s.contains('.')) return '$s days';
    var trimmed = s.replaceFirst(RegExp(r'0+$'), '');
    if (trimmed.endsWith('.')) trimmed = trimmed.substring(0, trimmed.length - 1);
    return '$trimmed ${d == Decimal.one ? "day" : "days"}';
  }
}
