import 'package:decimal/decimal.dart';

/// The `base_salary` a role-scorecard save should persist.
///
/// Settable only when CREATING a scorecard; **immutable on edit**.
///
/// Payroll falls back to this value for every employee on the role who has no
/// `compensation_changes` record (`compute_service.dart`: `effective?.newBaseSalary
/// ?? roleCard['base_salary']`). Editing it would therefore silently reprice
/// those employees — retroactively for the whole pay period, with no effective
/// date, no notice, no timeline event, and no audit trail.
///
/// Pay changes belong to the employee-level "Adjust Compensation / Change Role"
/// flow, which writes a `compensation_changes` row, drafts the notice, and
/// pro-rates from the effective date.
///
/// Returning the existing value (rather than the typed text) makes the rule
/// hold even if a caller bypasses the read-only form field.
Decimal? resolveScorecardBaseSalaryOnSave({
  required bool isEdit,
  required Decimal? existingBaseSalary,
  required String typedText,
}) {
  if (isEdit) return existingBaseSalary;
  final trimmed = typedText.trim();
  if (trimmed.isEmpty) return null;
  return Decimal.tryParse(trimmed);
}
