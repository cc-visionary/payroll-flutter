import 'document_template.dart';

/// Pure function so it's easy to test against every (hasEvent, status)
/// combination. Called by [CoeTemplate.gates] which loads the inputs
/// from the AutofillContext.
List<Gate> computeCoeGates({
  required bool hasSeparationEvent,
  required String employmentStatus,
}) {
  final separated =
      hasSeparationEvent || employmentStatus.toUpperCase() == 'SEPARATED';
  if (separated) return const [];
  return const [Gate('Available only after separation.')];
}
