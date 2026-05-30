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
