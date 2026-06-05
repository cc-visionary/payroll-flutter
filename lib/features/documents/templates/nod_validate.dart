import 'document_template.dart';
import 'nod_inputs.dart';

List<ValidationError> validateNod(NodInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errors.add(const ValidationError('employee', 'Select an employee'));
  }
  if (i.companyId.isEmpty) {
    errors.add(const ValidationError('company', 'Select a company'));
  }
  if (i.hrManagerName.trim().isEmpty) {
    errors.add(
      const ValidationError('hrManager', 'HR manager name is required'),
    );
  }
  if (i.charges.trim().isEmpty) {
    errors.add(const ValidationError('charges', 'Describe the charges'));
  }
  if (i.employeeResponseSummary.trim().isEmpty) {
    errors.add(
      const ValidationError(
        'employeeResponseSummary',
        "Summarize the employee's response",
      ),
    );
  }
  if (i.findings.trim().isEmpty) {
    errors.add(
      const ValidationError('findings', 'Management findings are required'),
    );
  }
  if (i.decision == NodDecision.suspension && i.suspensionDays <= 0) {
    errors.add(
      const ValidationError(
        'suspensionDays',
        'Suspension requires at least 1 day',
      ),
    );
  }
  if (i.effectiveDate.isBefore(i.issueDate)) {
    errors.add(
      const ValidationError(
        'effectiveDate',
        'Effective date must be on or after issue date',
      ),
    );
  }
  return errors;
}
