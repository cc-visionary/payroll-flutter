import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Onboarding',
      icon: Icons.rocket_launch_outlined,
      tagline:
          'Standardised first-30-60-90 day journeys so every new hire lands prepared. Checklists, document signing, IT provisioning, and buddy assignments in one place.',
      plannedFeatures: [
        'Pre-boarding checklist (contract, BIR 2305, SSS/PhilHealth/Pag-IBIG forms)',
        'First-day provisioning (laptop, email, BigSeller/ERPNext access)',
        'Role-specific 30/60/90 day milestones from the Responsibility Card',
        'Buddy / manager assignment with automatic check-in reminders',
        'Progress dashboard per new hire for HR and hiring manager',
      ],
    );
  }
}
