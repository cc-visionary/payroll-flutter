import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class OffboardingScreen extends StatelessWidget {
  const OffboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Offboarding',
      icon: Icons.logout_outlined,
      tagline:
          'Clean, compliant exits. Track resignation, clearance, final pay, and knowledge handover so nothing is dropped when someone leaves.',
      plannedFeatures: [
        'Resignation intake with last-day planning',
        'Clearance checklist (assets, accesses, pending payables/receivables)',
        'Automated final-pay computation (last salary, unused leave, pro-rated 13th month)',
        'Exit interview collection and anonymized insights',
        'Generated Certificate of Employment via Documents',
      ],
    );
  }
}
