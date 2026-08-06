import 'package:flutter/material.dart';

import '../templates/employment_contract_inputs.dart';

class AnnexAEditor extends StatelessWidget {
  final List<ContractResponsibility> responsibilities;
  final ValueChanged<List<ContractResponsibility>> onResponsibilitiesChanged;
  final List<ContractKpi> kpis;
  final ValueChanged<List<ContractKpi>> onKpisChanged;
  const AnnexAEditor({
    super.key,
    required this.responsibilities,
    required this.onResponsibilitiesChanged,
    required this.kpis,
    required this.onKpisChanged,
  });

  void _addResponsibility() {
    onResponsibilitiesChanged([
      ...responsibilities,
      const ContractResponsibility(area: '', tasks: []),
    ]);
  }

  void _removeResponsibility(int idx) {
    final next = [...responsibilities]..removeAt(idx);
    onResponsibilitiesChanged(next);
  }

  void _setResponsibility(int idx, ContractResponsibility r) {
    final next = [...responsibilities];
    next[idx] = r;
    onResponsibilitiesChanged(next);
  }

  void _addKpi() {
    onKpisChanged([...kpis, const ContractKpi(metric: '', frequency: '')]);
  }

  void _removeKpi(int idx) {
    final next = [...kpis]..removeAt(idx);
    onKpisChanged(next);
  }

  void _setKpi(int idx, ContractKpi k) {
    final next = [...kpis];
    next[idx] = k;
    onKpisChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsibilities',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < responsibilities.length; i++)
          _ResponsibilityCard(
            index: i,
            responsibility: responsibilities[i],
            onChanged: (r) => _setResponsibility(i, r),
            onRemove: () => _removeResponsibility(i),
          ),
        TextButton.icon(
          onPressed: _addResponsibility,
          icon: const Icon(Icons.add),
          label: const Text('Add responsibility area'),
        ),
        const SizedBox(height: 16),
        Text('KPIs (optional)', style: Theme.of(context).textTheme.labelMedium),
        for (var i = 0; i < kpis.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: kpis[i].metric,
                    decoration: const InputDecoration(
                      labelText: 'Metric',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (s) => _setKpi(
                      i,
                      ContractKpi(metric: s, frequency: kpis[i].frequency),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: kpis[i].frequency,
                    decoration: const InputDecoration(
                      labelText: 'Frequency',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (s) => _setKpi(
                      i,
                      ContractKpi(metric: kpis[i].metric, frequency: s),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove KPI',
                  onPressed: () => _removeKpi(i),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: _addKpi,
          icon: const Icon(Icons.add),
          label: const Text('Add KPI'),
        ),
      ],
    );
  }
}

class _ResponsibilityCard extends StatelessWidget {
  final int index;
  final ContractResponsibility responsibility;
  final ValueChanged<ContractResponsibility> onChanged;
  final VoidCallback onRemove;
  const _ResponsibilityCard({
    required this.index,
    required this.responsibility,
    required this.onChanged,
    required this.onRemove,
  });

  void _setArea(String s) =>
      onChanged(ContractResponsibility(area: s, tasks: responsibility.tasks));

  void _addTask() => onChanged(
    ContractResponsibility(
      area: responsibility.area,
      tasks: [...responsibility.tasks, ''],
    ),
  );

  void _setTask(int i, String s) {
    final next = [...responsibility.tasks];
    next[i] = s;
    onChanged(ContractResponsibility(area: responsibility.area, tasks: next));
  }

  void _removeTask(int i) {
    final next = [...responsibility.tasks]..removeAt(i);
    onChanged(ContractResponsibility(area: responsibility.area, tasks: next));
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
                  initialValue: responsibility.area,
                  decoration: InputDecoration(
                    labelText: 'Area ${index + 1} title',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _setArea,
                ),
              ),
              IconButton(
                tooltip: 'Remove area',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          for (var ti = 0; ti < responsibility.tasks.length; ti++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: responsibility.tasks[ti],
                      decoration: const InputDecoration(
                        labelText: 'Task',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (s) => _setTask(ti, s),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove task',
                    onPressed: () => _removeTask(ti),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: _addTask,
            icon: const Icon(Icons.add),
            label: const Text('Add task'),
          ),
        ],
      ),
    );
  }
}
