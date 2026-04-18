import 'package:flutter/material.dart';

/// Three-step timeline: Created → Computed → Released, matching the payrollos
/// layout. Green circle + checkmark for completed, blue circle + step number
/// for current, gray for pending.
class PayrollStatusTimeline extends StatelessWidget {
  final String status; // DRAFT, COMPUTING, REVIEW, RELEASED, CANCELLED
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? releasedAt;
  const PayrollStatusTimeline({
    super.key,
    required this.status,
    required this.createdAt,
    this.approvedAt,
    this.releasedAt,
  });

  @override
  Widget build(BuildContext context) {
    if (status == 'CANCELLED') return const SizedBox.shrink();

    final steps = <_StepSpec>[
      _StepSpec(
        label: 'Created',
        state: _StepState.completed,
        date: createdAt,
      ),
      _StepSpec(
        label: 'Computed',
        state: status == 'DRAFT'
            ? _StepState.pending
            : status == 'COMPUTING'
                ? _StepState.current
                : _StepState.completed,
        date: status != 'DRAFT' ? createdAt : null,
      ),
      _StepSpec(
        label: 'Released',
        state: status == 'RELEASED'
            ? _StepState.completed
            : status == 'REVIEW'
                ? _StepState.current
                : _StepState.pending,
        date: releasedAt,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _Node(step: steps[i], index: i + 1),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: steps[i].state == _StepState.completed
                        ? const Color(0xFF22C55E)
                        : Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { completed, current, pending }

class _StepSpec {
  final String label;
  final _StepState state;
  final DateTime? date;
  const _StepSpec({required this.label, required this.state, this.date});
}

class _Node extends StatelessWidget {
  final _StepSpec step;
  final int index;
  const _Node({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    final bg = switch (step.state) {
      _StepState.completed => const Color(0xFF22C55E),
      _StepState.current => const Color(0xFF2563EB),
      _StepState.pending => const Color(0xFFE5E7EB),
    };
    final fg = step.state == _StepState.pending
        ? const Color(0xFF6B7280)
        : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(
            child: step.state == _StepState.completed
                ? Icon(Icons.check, color: fg, size: 22)
                : Text(
                    '$index',
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          step.date == null ? 'Pending' : _short(step.date!),
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }

  static String _short(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}
