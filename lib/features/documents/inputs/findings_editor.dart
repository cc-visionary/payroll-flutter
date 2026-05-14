import 'package:flutter/material.dart';

import '../templates/non_reg_inputs.dart';

class FindingsEditor extends StatelessWidget {
  final List<FindingSection> findings;
  final ValueChanged<List<FindingSection>> onChanged;
  const FindingsEditor({
    super.key,
    required this.findings,
    required this.onChanged,
  });

  void _addFinding() {
    onChanged([
      ...findings,
      const FindingSection(title: '', standard: '', finding: ''),
    ]);
  }

  void _removeFinding(int idx) {
    final next = [...findings]..removeAt(idx);
    onChanged(next);
  }

  void _setFinding(int idx, FindingSection f) {
    final next = [...findings];
    next[idx] = f;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < findings.length; i++)
          _FindingCard(
            index: i,
            finding: findings[i],
            onChanged: (f) => _setFinding(i, f),
            onRemove: () => _removeFinding(i),
          ),
        TextButton.icon(
          onPressed: _addFinding,
          icon: const Icon(Icons.add),
          label: const Text('Add finding section'),
        ),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  final int index;
  final FindingSection finding;
  final ValueChanged<FindingSection> onChanged;
  final VoidCallback onRemove;
  const _FindingCard({
    required this.index,
    required this.finding,
    required this.onChanged,
    required this.onRemove,
  });

  void _setTitle(String s) => onChanged(FindingSection(
        title: s,
        standard: finding.standard,
        finding: finding.finding,
        subFindings: finding.subFindings,
      ));

  void _setStandard(String s) => onChanged(FindingSection(
        title: finding.title,
        standard: s,
        finding: finding.finding,
        subFindings: finding.subFindings,
      ));

  void _setFinding(String s) => onChanged(FindingSection(
        title: finding.title,
        standard: finding.standard,
        finding: s,
        subFindings: finding.subFindings,
      ));

  void _addSub() => onChanged(FindingSection(
        title: finding.title,
        standard: finding.standard,
        finding: finding.finding,
        subFindings: [
          ...finding.subFindings,
          const SubFinding(title: '', body: ''),
        ],
      ));

  void _setSub(int i, SubFinding s) {
    final next = [...finding.subFindings];
    next[i] = s;
    onChanged(FindingSection(
      title: finding.title,
      standard: finding.standard,
      finding: finding.finding,
      subFindings: next,
    ));
  }

  void _removeSub(int i) {
    final next = [...finding.subFindings]..removeAt(i);
    onChanged(FindingSection(
      title: finding.title,
      standard: finding.standard,
      finding: finding.finding,
      subFindings: next,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: finding.title,
                  decoration: InputDecoration(
                    labelText: 'Section ${index + 1} title',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _setTitle,
                ),
              ),
              IconButton(
                tooltip: 'Remove section',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: finding.standard,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Standard',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _setStandard,
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: finding.finding,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Finding',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _setFinding,
          ),
          const SizedBox(height: 8),
          Text(
            'Sub-findings (optional)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          for (var si = 0; si < finding.subFindings.length; si++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: finding.subFindings[si].title,
                      decoration: const InputDecoration(
                        labelText: 'Sub-finding title',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (s) => _setSub(
                        si,
                        SubFinding(
                          title: s,
                          body: finding.subFindings[si].body,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: finding.subFindings[si].body,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Sub-finding body',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (s) => _setSub(
                        si,
                        SubFinding(
                          title: finding.subFindings[si].title,
                          body: s,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove sub-finding',
                    onPressed: () => _removeSub(si),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: _addSub,
            icon: const Icon(Icons.add),
            label: const Text('Add sub-finding'),
          ),
        ],
      ),
    );
  }
}
