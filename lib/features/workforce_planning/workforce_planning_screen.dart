import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class WorkforcePlanningScreen extends StatelessWidget {
  const WorkforcePlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Workforce Planning',
      icon: Icons.insights_outlined,
      tagline:
          'Plan headcount against budget and business goals. Map every role to a Responsibility Card, allocate salary envelopes, and track filled-vs-open against the plan.',
      plannedFeatures: [
        'Annual and quarterly headcount plan per brand with budget envelopes',
        'Role slots linked to Responsibility Cards (skills, outcomes, comp band)',
        'Filled / open / pending-approval status per slot',
        'Variance report: planned spend vs actual payroll',
        'Scenario modelling for expansion, hiring freezes, and reorgs',
      ],
    );
  }
}
