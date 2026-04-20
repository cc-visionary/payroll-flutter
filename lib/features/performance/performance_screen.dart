import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class PerformanceScreen extends StatelessWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Performance',
      icon: Icons.stacked_line_chart_outlined,
      tagline:
          'Goals, reviews, and 1:1s in one place. Tie performance cycles to the outcomes on each Responsibility Card so reviews reflect the role, not vibes.',
      plannedFeatures: [
        'Quarterly goals / OKRs per employee with progress tracking',
        'Review cycles (self, manager, peer) scored against Responsibility Card outcomes',
        'Recurring 1:1 agendas with shared notes and action items',
        'Calibration view across teams to reduce rating drift',
        'Feedback history feeding promotion and comp decisions',
      ],
    );
  }
}
