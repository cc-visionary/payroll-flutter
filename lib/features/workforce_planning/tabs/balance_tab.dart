import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BalanceTab extends ConsumerWidget {
  const BalanceTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const Center(child: Text('Balance'));
}
