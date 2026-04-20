import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class ComplianceScreen extends StatelessWidget {
  const ComplianceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Compliance',
      icon: Icons.verified_user_outlined,
      tagline:
          'Philippine statutory obligations without the spreadsheets. Automate SSS, PhilHealth, Pag-IBIG, and BIR filings, and keep policy acknowledgments auditable.',
      plannedFeatures: [
        'Monthly SSS, PhilHealth, and Pag-IBIG contribution schedules and export files',
        'BIR 1601-C, 2316, and alphalist generation tied to payroll runs',
        'DOLE-compliant 201 file checklist per employee',
        'Policy library with e-acknowledgment trail (handbook, data privacy, code of conduct)',
        'Compliance calendar with deadline reminders and ownership',
      ],
    );
  }
}
