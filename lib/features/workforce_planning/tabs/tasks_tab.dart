import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TasksTab extends ConsumerWidget {
  const TasksTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const Center(child: Text('Tasks — available in a later update'));
}
