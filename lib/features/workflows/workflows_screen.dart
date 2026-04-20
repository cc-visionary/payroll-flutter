import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class WorkflowsScreen extends StatelessWidget {
  const WorkflowsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Workflows',
      icon: Icons.alt_route_outlined,
      tagline:
          'Design approvals and automations visually. Route leave requests, expense claims, contract changes, and more through the right people without chasing over chat.',
      plannedFeatures: [
        'Visual builder for multi-step approval chains',
        'Triggers from Lark, attendance anomalies, and employee lifecycle events',
        'Conditional routing by brand, amount, or role',
        'SLA tracking with auto-escalation if approvers go silent',
        'Full audit trail of who approved what and when',
      ],
    );
  }
}
