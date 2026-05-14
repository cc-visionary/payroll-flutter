import 'document_template.dart';

/// Pure function so it's easy to test against every (hasEvent, status)
/// combination. Called by [CoeTemplate.gates] which loads the inputs
/// from the AutofillContext.
///
/// An employee is considered separated for COE-issuance purposes if any
/// of the following is true:
///   * `hasSeparationEvent` is true (a SEPARATION row exists), OR
///   * `employmentStatus` is anything other than 'ACTIVE'. The
///     `employment_status` enum exposes 6 non-active states (RESIGNED,
///     TERMINATED, AWOL, DECEASED, END_OF_CONTRACT, RETIRED), every one
///     of which represents a separation scenario where COE is valid.
List<Gate> computeCoeGates({
  required bool hasSeparationEvent,
  required String employmentStatus,
}) {
  final status = employmentStatus.toUpperCase();
  final separated = hasSeparationEvent || status != 'ACTIVE';
  if (separated) return const [];
  return const [Gate('Available only after separation.')];
}
