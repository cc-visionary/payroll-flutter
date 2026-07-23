import 'package:flutter/material.dart';

/// A one-line statement of what a tab is for, with optional detail behind a
/// "How this works" toggle.
///
/// This module carries a lot of non-obvious vocabulary — derived ownership,
/// weighted responsibilities, load against capacity, growth multiplier — and
/// none of it was on screen. Someone opening a tab could see the numbers
/// without knowing what question they answer or how they were produced, which
/// is how a planning tool gets mistrusted and then ignored.
///
/// Deliberately compact: one sentence always, the rest only on request. Help
/// that cannot be dismissed becomes furniture people stop reading.
class TabIntro extends StatefulWidget {
  const TabIntro({
    super.key,
    required this.purpose,
    required this.details,
    this.trailing,
  });

  /// One sentence: the question this tab answers.
  final String purpose;

  /// Label/body pairs shown when expanded. Keep each body to a sentence or two.
  final List<({String term, String meaning})> details;

  /// Optional actions rendered on the same row (buttons, counts).
  final Widget? trailing;

  @override
  State<TabIntro> createState() => _TabIntroState();
}

class _TabIntroState extends State<TabIntro> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(widget.purpose,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 6),
            if (widget.details.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open ? Icons.expand_less : Icons.help_outline, size: 15),
                label: Text(_open ? 'Hide' : 'How this works'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            if (widget.trailing != null) ...[const Spacer(), widget.trailing!],
          ],
        ),
        if (_open)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in widget.details)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        children: [
                          TextSpan(
                            text: '${d.term}  ',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, color: cs.onSurface),
                          ),
                          TextSpan(text: d.meaning),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shared vocabulary, defined once so the same word never means two things on
/// two tabs.
class WpGlossary {
  static const derived = (
    term: 'Derived',
    meaning: 'The task has no named owner, so it reaches whoever holds its role '
        'card — split evenly if the role has more than one holder.',
  );
  static const weighted = (
    term: 'Weighted responsibility',
    meaning: 'A responsibility with estimated hours. Behavioural standards and '
        'required skills live on the role card instead and carry no hours, so '
        'they never appear here.',
  );
  static const load = (
    term: 'Load',
    meaning: 'Hours of modelled work ÷ that person\'s monthly capacity '
        '(160h unless overridden). Over 100% = Over, 80-100% = OK, below = Under.',
  );
  static const notCosted = (
    term: 'Needs costing',
    meaning: 'Real work nobody has estimated yet. It contributes 0 hours, so '
        'every load figure that includes it is understated.',
  );
  static const unassigned = (
    term: 'Unassigned',
    meaning: 'Costed work that reaches nobody — no named owner, and either no '
        'role card or a card with no active holder. It is missing from every '
        'person\'s load.',
  );
  static const multiplier = (
    term: 'Growth multiplier',
    meaning: 'Scenario dial in Drivers. Only tasks driven by a volume driver '
        'flagged "grows" respond to it; a manual hours figure is flat forever.',
  );
  static const node = (
    term: 'Node',
    meaning: 'The value-chain stage a task belongs to (Source & land, Fulfil, '
        'After-sales…). Grouping only — it has no effect on the hours.',
  );
  static const proposeRole = (
    term: 'Propose role from these',
    meaning: 'When several unassigned responsibilities form a coherent job, '
        'draft a new (inactive) role card seeded with them — turning a pile of '
        'unowned work into the role you need to staff, hours already totalled.',
  );
  static const needsAttention = (
    term: 'Needs attention',
    meaning: 'Gaps derived from the current plan, grouped People / Process / '
        'Structure / Tools — over-capacity people, unowned or uncosted work, '
        'unstaffed critical roles, KPIs measuring nobody. Each links to its fix.',
  );
}
