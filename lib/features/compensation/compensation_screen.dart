import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class CompensationScreen extends StatelessWidget {
  const CompensationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Compensation',
      icon: Icons.account_balance_wallet_outlined,
      tagline:
          'Salary bands, benefits, and total rewards in one source of truth. Keep offers consistent, spot pay inequities, and run comp reviews with real data.',
      plannedFeatures: [
        'Salary bands per role and level, brand-aware',
        'Benefits catalog (HMO, allowances, statutory contributions)',
        'Total compensation statements per employee',
        'Annual comp review cycles with budget envelopes',
        'Pay equity analysis across gender, tenure, and brand',
      ],
    );
  }
}
