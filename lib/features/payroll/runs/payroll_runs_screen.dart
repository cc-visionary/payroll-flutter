import 'package:flutter/material.dart';
import '../../../widgets/placeholder_screen.dart';

class PayrollRunsScreen extends StatelessWidget {
  const PayrollRunsScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        title: 'Payroll',
        description:
            'Runs with 3-state workflow: In Review → Send Payslip Approvals → Refresh Sync → Release.',
      );
}
