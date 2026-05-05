import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'templates/template_registry.dart';

/// Two-pane scaffold: form on the left, PDF preview on the right.
/// Phases 5-7 replace the form panel with per-template forms; this
/// shell exists so the router can wire the route immediately.
class GenerateScreen extends ConsumerStatefulWidget {
  final String templateId;
  final String? employeeId;
  const GenerateScreen({
    super.key,
    required this.templateId,
    this.employeeId,
  });

  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  @override
  Widget build(BuildContext context) {
    final tpl = findTemplateById(widget.templateId);
    if (tpl == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generate Document')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Template not found.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/documents'),
                child: const Text('Back to documents'),
              ),
            ],
          ),
        ),
      );
    }
    final phaseLabel =
        const {'quitclaim': 5, 'coe': 6, 'nte': 7}[tpl.id]?.toString() ?? '?';
    return Scaffold(
      appBar: AppBar(title: Text(tpl.name)),
      body: Row(
        children: [
          Container(
            width: 480,
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Form for "${tpl.name}" — implemented in Phase $phaseLabel.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          const Expanded(
            child: Center(child: Text('Preview placeholder')),
          ),
        ],
      ),
    );
  }
}
