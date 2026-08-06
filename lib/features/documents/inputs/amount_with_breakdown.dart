import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../providers.dart';

class AmountWithBreakdown extends StatelessWidget {
  final Decimal value;
  final FinalPayBreakdown? breakdown;
  final bool locked;
  final ValueChanged<Decimal> onChanged;
  const AmountWithBreakdown({
    super.key,
    required this.value,
    required this.breakdown,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: value.toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: !locked,
          decoration: const InputDecoration(
            prefixText: '₱ ',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (s) {
            try {
              onChanged(Decimal.parse(s));
            } catch (_) {
              /* ignore parse errors mid-typing */
            }
          },
        ),
        if (breakdown != null) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('Breakdown'),
            tilePadding: EdgeInsets.zero,
            children: [
              _row(
                '13th-month accrual',
                breakdown!.thirteenthMonthAvailable
                    ? '+ ₱ ${breakdown!.thirteenthMonth}'
                    : '— (not computed)',
              ),
              _row('Last cutoff net pay', '+ ₱ ${breakdown!.lastNetPay}'),
              _row(
                'Unused leave conversion',
                '+ ₱ ${breakdown!.unusedLeaveConversion}',
              ),
              _row(
                'Cash advance (outstanding)',
                '− ₱ ${breakdown!.outstandingCashAdvance}',
              ),
              const Divider(height: 1),
              _row('Total', '₱ ${breakdown!.total}', bold: true),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            fontFamily: 'monospace',
          ),
        ),
      ],
    ),
  );
}
