import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../auth/profile_provider.dart';

class HiringScreen extends ConsumerWidget {
  const HiringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.isHrOrAdmin ?? false;
    if (!canManage) {
      return Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(title: const Text('Hiring')),
        body: const Center(
          child: Text('You do not have permission to view applicants.'),
        ),
      );
    }
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Hiring'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => context.go('/hiring/new'),
              icon: const Icon(Icons.add),
              label: const Text('New applicant'),
            ),
          ),
        ],
      ),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Kanban coming in Task 10.')),
      ),
    );
  }
}
