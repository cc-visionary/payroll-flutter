/// Allowed status transitions for the applicants pipeline.
/// Derived from spec 2026-05-30-hiring-mvp-design.md, §"Status pipeline".
/// HIRED is set only by the conversion flow — never manually.
const Map<String, Set<String>> kApplicantTransitions = {
  'NEW':            {'SCREENING', 'REJECTED', 'WITHDRAWN'},
  'SCREENING':      {'INTERVIEW',  'REJECTED', 'WITHDRAWN'},
  'INTERVIEW':      {'ASSESSMENT', 'OFFER', 'REJECTED', 'WITHDRAWN'},
  'ASSESSMENT':     {'OFFER', 'REJECTED', 'WITHDRAWN'},
  'OFFER':          {'OFFER_ACCEPTED', 'REJECTED', 'WITHDRAWN'},
  'OFFER_ACCEPTED': {'HIRED', 'WITHDRAWN'},
  'HIRED':          <String>{},
  'REJECTED':       {'NEW'},
  'WITHDRAWN':      {'NEW'},
};

bool canTransition({required String from, required String to}) =>
    (kApplicantTransitions[from] ?? const <String>{}).contains(to);

/// Column name (matching the DB schema) that MUST be populated when
/// transitioning to [target]. Returns null when no reason is required.
String? requiresReason({required String target}) {
  switch (target) {
    case 'REJECTED':   return 'rejection_reason';
    case 'WITHDRAWN':  return 'withdrawal_reason';
    default:           return null;
  }
}

class IllegalTransition implements Exception {
  final String from;
  final String to;
  IllegalTransition(this.from, this.to);
  @override
  String toString() => 'Illegal applicant status transition: $from → $to';
}

class MissingReason implements Exception {
  final String reasonField;
  MissingReason(this.reasonField);
  @override
  String toString() => 'Status change requires $reasonField.';
}

/// Throws on disallowed transition or missing reason. Use BEFORE writing to DB.
void validateTransition({
  required String from,
  required String to,
  required String? reason,
}) {
  if (from == to) return;
  if (!canTransition(from: from, to: to)) {
    throw IllegalTransition(from, to);
  }
  final reasonField = requiresReason(target: to);
  if (reasonField != null && (reason == null || reason.trim().isEmpty)) {
    throw MissingReason(reasonField);
  }
}
