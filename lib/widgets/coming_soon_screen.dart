import 'package:flutter/material.dart';

import '../app/breakpoints.dart';
import '../app/shell.dart';
import '../app/tokens.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String tagline;
  final List<String> plannedFeatures;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.tagline,
    required this.plannedFeatures,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = isMobile(context);
    final p = LuxiumColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      drawer: mobile ? const AppDrawer() : null,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(LuxiumSpacing.xl),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(LuxiumSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: p.ctaTint,
                            borderRadius:
                                BorderRadius.circular(LuxiumRadius.lg),
                          ),
                          child: Icon(icon, color: p.cta, size: 22),
                        ),
                        const SizedBox(width: LuxiumSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: theme.textTheme.titleLarge),
                              const SizedBox(height: 2),
                              _SoonChip(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: LuxiumSpacing.lg),
                    Text(
                      tagline,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: p.subdued,
                        height: 1.5,
                      ),
                    ),
                    if (plannedFeatures.isNotEmpty) ...[
                      const SizedBox(height: LuxiumSpacing.xl),
                      Text(
                        'PLANNED',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: p.soft,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: LuxiumSpacing.md),
                      for (final f in plannedFeatures)
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: LuxiumSpacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: p.cta,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: LuxiumSpacing.md),
                              Expanded(
                                child: Text(
                                  f,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: p.foreground,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoonChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.ctaTint,
        borderRadius: BorderRadius.circular(LuxiumRadius.pill),
      ),
      child: Text(
        'Coming soon',
        style: TextStyle(
          color: p.cta,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
