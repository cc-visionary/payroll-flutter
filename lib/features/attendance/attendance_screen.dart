import 'package:flutter/material.dart';
import '../../widgets/placeholder_screen.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        title: 'Attendance',
        description: 'Daily grid, CSV/XLSX import, approvals, Lark sync.',
      );
}
