import 'document_template.dart';
import 'resignation_acceptance_inputs.dart';

List<ValidationError> validateResignationAcceptance(
  ResignationAcceptanceInputs i,
) {
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
  if (i.lastDayOfWork.isBefore(i.resignationDate)) {
    errors.add(
      const ValidationError(
        'lastDayOfWork',
        'Last day of work must be on or after resignation date',
      ),
    );
  }
  if (i.turnoverInstructions.trim().isEmpty) {
    errors.add(
      const ValidationError(
        'turnoverInstructions',
        'Turnover instructions are required',
      ),
    );
  }
  return errors;
}
