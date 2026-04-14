import 'package:flutter/material.dart';
import '../../widgets/placeholder_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        title: 'Settings',
        description: 'Company, departments, shifts, leave types, penalty types, tax tables (read-only).',
      );
}
