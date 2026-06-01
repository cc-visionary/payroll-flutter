/// Allowed status transitions for performance check-ins.
const Map<String, Set<String>> kCheckInTransitions = {
  'DRAFT':        {'SUBMITTED', 'SKIPPED'},
  'SUBMITTED':    {'UNDER_REVIEW', 'SKIPPED'},
  'UNDER_REVIEW': {'COMPLETED', 'SKIPPED'},
  'COMPLETED':    <String>{},
  'SKIPPED':      <String>{},
};

bool canCheckInTransition({required String from, required String to}) =>
    (kCheckInTransitions[from] ?? const <String>{}).contains(to);

class IllegalCheckInTransition implements Exception {
  final String from;
  final String to;
  IllegalCheckInTransition(this.from, this.to);
  @override
  String toString() => 'Illegal check-in status transition: $from → $to';
}

void validateCheckInTransition({required String from, required String to}) {
  if (from == to) return;
  if (!canCheckInTransition(from: from, to: to)) {
    throw IllegalCheckInTransition(from, to);
  }
}
