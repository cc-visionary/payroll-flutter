import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/money.dart';
import '../../../../../data/repositories/payroll_repository.dart';
import '../providers.dart';

/// Calculation Breakdown tab: Earnings card + Deductions card + Statutory row
/// + YTD row. Reads from `payslip_lines` (category-grouped) and the payslip
/// row's statutory/YTD columns.
///
/// [runId] + [runStatus] are required for the penalty-line "Skip" action in
/// the deductions card — only rendered when the run is still in REVIEW.
class BreakdownTab extends StatelessWidget {
  final Map<String, dynamic> payslip;
  final String? runId;
  final String? runStatus;
  const BreakdownTab({
    super.key,
    required this.payslip,
    this.runId,
    this.runStatus,
  });

  @override
  Widget build(BuildContext context) {
    final lines = (payslip['__lines'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final earnings = lines.where((l) => _isEarning(l['category'] as String)).toList();
    final deductions =
        lines.where((l) => _isDeduction(l['category'] as String)).toList();

    // MediaQuery avoids the LayoutBuilder-vs-IntrinsicHeight conflict
    // (the sibling _StatutoryCard / _YtdCard rows below use their own
    // LayoutBuilders; wrapping IntrinsicHeight inside a LayoutBuilder here
    // would cause intrinsic-dimension assertion failures higher up the tree).
    final twoCol = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        if (!twoCol)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EarningsCard(
                  lines: earnings, total: _dec(payslip['total_earnings'])),
              const SizedBox(height: 16),
              _DeductionsCard(
                lines: deductions,
                total: _dec(payslip['total_deductions']),
                runId: runId,
                runStatus: runStatus,
              ),
            ],
          )
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _EarningsCard(
                    lines: earnings,
                    total: _dec(payslip['total_earnings']),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _DeductionsCard(
                    lines: deductions,
                    total: _dec(payslip['total_deductions']),
                    runId: runId,
                    runStatus: runStatus,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _StatutoryCard(payslip: payslip),
        const SizedBox(height: 16),
        _YtdCard(payslip: payslip),
      ],
    );
  }

  static Decimal _dec(Object? v) => Decimal.parse((v ?? '0').toString());

  static bool _isEarning(String category) {
    const earnings = {
      'BASIC_PAY',
      'OVERTIME_REGULAR',
      'OVERTIME_REST_DAY',
      'OVERTIME_HOLIDAY',
      'NIGHT_DIFFERENTIAL',
      'HOLIDAY_PAY',
      'REST_DAY_PAY',
      'ALLOWANCE',
      'REIMBURSEMENT',
      'INCENTIVE',
      'BONUS',
      'ADJUSTMENT_ADD',
      'THIRTEENTH_MONTH_PAY',
      'TAX_REFUND',
    };
    return earnings.contains(category);
  }

  static bool _isDeduction(String category) {
    // Everything not an earning is a deduction — except we keep statutory EE
    // lines inside the Statutory card, not the Deductions card (they're
    // shown as deductions there with the EE label). But for the Deductions
    // table we want to include them too because they reduce net pay.
    return !_isEarning(category);
  }
}

// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          child,
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  final String description;
  final String? subtitle;
  final String amountText;
  final Color? amountColor;
  final Widget? trailing;
  const _LineRow({
    required this.description,
    required this.amountText,
    this.subtitle,
    this.amountColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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
          ),
          Text(
            amountText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: amountColor,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final List<Map<String, dynamic>> lines;
  final Decimal total;
  const _EarningsCard({required this.lines, required this.total});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Earnings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No earnings.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (int i = 0; i < lines.length; i++) ...[
              _LineRow(
                description: lines[i]['description'] as String? ?? '—',
                subtitle: _subtitleFor(lines[i]),
                amountText: Money.fmtPhp(BreakdownTab._dec(lines[i]['amount'])),
              ),
              if (i < lines.length - 1)
                Divider(height: 1, color: Theme.of(context).dividerColor),
            ],
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total Earnings',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  Money.fmtPhp(total),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeductionsCard extends ConsumerWidget {
  final List<Map<String, dynamic>> lines;
  final Decimal total;
  final String? runId;
  final String? runStatus;
  const _DeductionsCard({
    required this.lines,
    required this.total,
    this.runId,
    this.runStatus,
  });

  bool get _canSkip => runId != null && runStatus == 'REVIEW';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Card(
      title: 'Deductions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No deductions.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (int i = 0; i < lines.length; i++) ...[
              _LineRow(
                description: lines[i]['description'] as String? ?? '—',
                subtitle: _subtitleFor(lines[i]),
                amountText:
                    '-${Money.fmtPhp(BreakdownTab._dec(lines[i]['amount']))}',
                amountColor: const Color(0xFFDC2626),
                trailing: _canSkip
                    ? _skipAction(context, ref, lines[i])
                    : null,
              ),
              if (i < lines.length - 1)
                Divider(height: 1, color: Theme.of(context).dividerColor),
            ],
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total Deductions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '-${Money.fmtPhp(total)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Skip link — only shown on lines backed by a `penalty_installment_id`.
  /// Other deduction categories (statutory, late, cash advance) stay as-is.
  Widget? _skipAction(
      BuildContext context, WidgetRef ref, Map<String, dynamic> line) {
    final installmentId = line['penalty_installment_id'] as String?;
    if (installmentId == null) return null;
    return TextButton.icon(
      onPressed: () => _confirmAndSkip(context, ref, installmentId),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF2563EB),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(40, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.skip_next, size: 14),
      label: const Text('Skip'),
    );
  }

  Future<void> _confirmAndSkip(
      BuildContext context, WidgetRef ref, String installmentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Skip this installment?'),
        content: const Text(
          'This defers the penalty installment to the next pay period. '
          'The payslip needs to be recomputed for the change to take '
          'effect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Skip for this run'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(payrollRepositoryProvider).setPenaltyInstallmentSkip(
            installmentId: installmentId,
            runId: runId!,
            skip: true,
          );
      // Invalidate this payslip + any list viewing it. The user still
      // needs to hit Recompute on the run to rebuild payslip_lines; the
      // snackbar surfaces that next step.
      ref.invalidate(payslipDetailProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Installment skipped. Hit Recompute on the run to rebuild '
          'payslips.',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Skip failed: $e')));
    }
  }
}

/// Renders "quantity × rate × multiplier" if the line carries those fields.
String? _subtitleFor(Map<String, dynamic> line) {
  final q = line['quantity'];
  final r = line['rate'];
  final m = line['multiplier'];
  if (q == null && r == null && m == null) return null;
  final parts = <String>[];
  if (q != null) parts.add('${q.toString()} units');
  if (r != null) parts.add('₱${r.toString()}');
  if (m != null && m.toString() != '1' && m.toString() != '1.00') {
    parts.add('×${m.toString()}');
  }
  if (parts.isEmpty) return null;
  return parts.join(' × ');
}

class _StatutoryCard extends StatelessWidget {
  final Map<String, dynamic> payslip;
  const _StatutoryCard({required this.payslip});

  @override
  Widget build(BuildContext context) {
    final sssEe = BreakdownTab._dec(payslip['sss_ee']);
    final sssEr = BreakdownTab._dec(payslip['sss_er']);
    final phEe = BreakdownTab._dec(payslip['philhealth_ee']);
    final phEr = BreakdownTab._dec(payslip['philhealth_er']);
    final piEe = BreakdownTab._dec(payslip['pagibig_ee']);
    final piEr = BreakdownTab._dec(payslip['pagibig_er']);
    final tax = BreakdownTab._dec(payslip['withholding_tax']);

    return _Card(
      title: 'Statutory Contributions',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(builder: (ctx, c) {
          final cols = c.maxWidth >= 900 ? 4 : c.maxWidth >= 600 ? 2 : 1;
          const spacing = 16.0;
          final w = (c.maxWidth - spacing * (cols - 1)) / cols;
          final tiles = <Widget>[
            _StatTile(
              title: 'SSS',
              rows: [
                ('Employee', sssEe, const Color(0xFFDC2626)),
                ('Employer', sssEr, null),
              ],
            ),
            _StatTile(
              title: 'PhilHealth',
              rows: [
                ('Employee', phEe, const Color(0xFFDC2626)),
                ('Employer', phEr, null),
              ],
            ),
            _StatTile(
              title: 'Pag-IBIG',
              rows: [
                ('Employee', piEe, const Color(0xFFDC2626)),
                ('Employer', piEr, null),
              ],
            ),
            _StatTile(
              title: 'Withholding Tax',
              rows: [
                ('Tax Due', tax, const Color(0xFFDC2626)),
              ],
            ),
          ];
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        }),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final List<(String, Decimal, Color?)> rows;
  const _StatTile({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        for (final r in rows) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                r.$1,
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                Money.fmtPhp(r.$2),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: r.$3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _YtdCard extends StatelessWidget {
  final Map<String, dynamic> payslip;
  const _YtdCard({required this.payslip});

  @override
  Widget build(BuildContext context) {
    final gross = BreakdownTab._dec(payslip['ytd_gross_pay']);
    final taxable = BreakdownTab._dec(payslip['ytd_taxable_income']);
    final tax = BreakdownTab._dec(payslip['ytd_tax_withheld']);
    return _Card(
      title: 'Year-to-Date',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(builder: (ctx, c) {
          final cols = c.maxWidth >= 700 ? 3 : 1;
          const spacing = 16.0;
          final w = (c.maxWidth - spacing * (cols - 1)) / cols;
          final tiles = <Widget>[
            _YtdTile(label: 'YTD Gross Pay', value: gross),
            _YtdTile(label: 'YTD Taxable Income', value: taxable),
            _YtdTile(label: 'YTD Tax Withheld', value: tax),
          ];
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        }),
      ),
    );
  }
}

class _YtdTile extends StatelessWidget {
  final String label;
  final Decimal value;
  const _YtdTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          Money.fmtPhp(value),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
