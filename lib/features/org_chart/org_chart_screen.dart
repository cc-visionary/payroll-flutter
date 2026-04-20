import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class OrgChartScreen extends StatelessWidget {
  const OrgChartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Org Chart',
      icon: Icons.account_tree_outlined,
      tagline:
          'Live reporting structure across every brand under Luxium. See who reports to whom, spot span-of-control issues, and drill into any team.',
      plannedFeatures: [
        'Interactive tree view grouped by brand (HAVIT, GAMECOVE, OGKILZ, etc.)',
        'Manager / direct report relationships driven by the Employee record',
        'Vacant roles from Workforce Planning shown in-line',
        'Filter by brand, department, or location',
        'Export as PDF or PNG for investor and stakeholder decks',
      ],
    );
  }
}
