import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Documents',
      icon: Icons.description_outlined,
      tagline:
          'Generate contracts, certificates, and letters from employee data — no copy-paste, no version drift. Template once, issue hundreds.',
      plannedFeatures: [
        'Template library (employment contracts, COE, promotion letters, NDAs)',
        'Merge fields auto-filled from Employee, Responsibility Card, and Comp data',
        'E-signature routing through Workflows',
        'Signed-document vault attached to the employee 201 file',
        'Bulk issuance for annual COE runs and policy re-acknowledgments',
      ],
    );
  }
}
