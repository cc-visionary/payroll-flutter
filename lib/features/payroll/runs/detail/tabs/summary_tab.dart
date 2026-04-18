import 'package:flutter/material.dart';

import '../../../../../core/money.dart';
import '../providers.dart';

class PayrollSummaryTab extends StatelessWidget {
  final PayrollRunDetail detail;
  const PayrollSummaryTab({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        LayoutBuilder(builder: (ctx, c) {
          final cols = c.maxWidth >= 900 ? 2 : 1;
          const spacing = 16.0;
          final w = (c.maxWidth - spacing * (cols - 1)) / cols;
          final cards = <Widget>[
            _TotalsCard(detail: detail),
            _StatutoryCard(detail: detail),
            _WorkflowCard(detail: detail),
          ];
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [for (final c in cards) SizedBox(width: w, child: c)],
          );
        }),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final Widget value;
  final bool emphasized;
  final bool divider;
  const _Row({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.divider = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (divider) const Divider(height: 1),
          if (divider) const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: emphasized
                      ? null
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: emphasized ? FontWeight.w600 : null,
                ),
              ),
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: emphasized ? 17 : 13,
                  fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                ),
                child: value,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final PayrollRunDetail detail;
  const _TotalsCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final run = detail.run;
    return _Card(
      title: 'Payroll Totals',
      child: Column(
        children: [
          _Row(
            label: 'Employees',
            value: Text(run.employeeCount.toString()),
          ),
          _Row(
            label: 'Total Gross Pay',
            value: Text(Money.fmtPhp(run.totalGrossPay)),
          ),
          _Row(
            label: 'Total Deductions',
            value: Text(
              '-${Money.fmtPhp(run.totalDeductions)}',
              style: const TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
          _Row(
            label: 'Total Net Pay',
            value: Text(Money.fmtPhp(run.totalNetPay)),
            emphasized: true,
            divider: true,
          ),
        ],
      ),
    );
  }
}

class _StatutoryCard extends StatelessWidget {
  final PayrollRunDetail detail;
  const _StatutoryCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Statutory Contributions',
      child: Column(
        children: [
          _Row(
            label: 'SSS (EE / ER)',
            value: Text(
              '${Money.fmtPhp(detail.totalSssEe)} / ${Money.fmtPhp(detail.totalSssEr)}',
            ),
          ),
          _Row(
            label: 'PhilHealth (EE / ER)',
            value: Text(
              '${Money.fmtPhp(detail.totalPhilhealthEe)} / ${Money.fmtPhp(detail.totalPhilhealthEr)}',
            ),
          ),
          _Row(
            label: 'Pag-IBIG (EE / ER)',
            value: Text(
              '${Money.fmtPhp(detail.totalPagibigEe)} / ${Money.fmtPhp(detail.totalPagibigEr)}',
            ),
          ),
          _Row(
            label: 'Withholding Tax',
            value: Text(Money.fmtPhp(detail.totalWithholdingTax)),
            divider: true,
          ),
        ],
      ),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  final PayrollRunDetail detail;
  const _WorkflowCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final run = detail.run;
    return _Card(
      title: 'History',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkflowEntry(
            label: 'Created',
            date: run.createdAt,
            byEmail: run.createdByEmail,
          ),
          if (run.approvedAt != null)
            _WorkflowEntry(
              label: 'Approved',
              date: run.approvedAt!,
              byEmail: run.approvedByEmail,
            ),
          if (run.releasedAt != null)
            _WorkflowEntry(
              label: 'Released',
              date: run.releasedAt!,
              // Release doesn't stamp a separate user; it's usually the
              // same admin who approved, so fall back to approvedByEmail.
              byEmail: run.approvedByEmail,
            ),
        ],
      ),
    );
  }
}

class _WorkflowEntry extends StatelessWidget {
  final String label;
  final DateTime date;
  final String? byEmail;
  const _WorkflowEntry({
    required this.label,
    required this.date,
    this.byEmail,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: muted),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmtDateTime(date),
                style: const TextStyle(fontSize: 13),
              ),
              if (byEmail != null && byEmail!.isNotEmpty)
                Text(
                  'by $byEmail',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtDateTime(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = d.toLocal();
    final h = local.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final m = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, ${local.year}, $h12:$m $period';
  }
}
