import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Assets',
      icon: Icons.devices_other_outlined,
      tagline:
          'Track every laptop, phone, access card, and tool issued to employees. Assign on onboarding, recover on offboarding, and never lose sight of company property again.',
      plannedFeatures: [
        'Asset registry with serial, purchase date, and book value',
        'Assignment history per employee',
        'Condition and depreciation tracking',
        'Onboarding auto-assignment and offboarding recovery checklist',
        'QR-tagged asset labels for quick audits',
      ],
    );
  }
}
