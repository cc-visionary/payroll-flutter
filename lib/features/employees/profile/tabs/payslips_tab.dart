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
