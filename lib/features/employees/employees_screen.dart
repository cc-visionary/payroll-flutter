import 'package:flutter/material.dart';
import '../../widgets/placeholder_screen.dart';

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        title: 'Employees',
        description: 'Employee list, CRUD, bank accounts, government IDs — coming in Phase 6.',
      );
}
