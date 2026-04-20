import 'package:flutter/material.dart';

import '../../widgets/coming_soon_screen.dart';

class HiringScreen extends StatelessWidget {
  const HiringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Hiring',
      icon: Icons.person_search_outlined,
      tagline:
          'Track candidates from sourced to offer accepted. When a hire is confirmed, convert the record into an Employee with one click — no double entry.',
      plannedFeatures: [
        'Candidate pipeline with stage tracking (sourced, screened, interviewed, offered, hired)',
        'Requisition linking to Workforce Planning headcount slots',
        'Interview scheduling and scorecards tied to Responsibility Cards',
        'Offer letter generation via Documents',
        'One-click convert to Employee with pre-filled profile',
      ],
    );
  }
}
