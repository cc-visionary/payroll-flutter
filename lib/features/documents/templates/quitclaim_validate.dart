import 'package:decimal/decimal.dart';
import 'document_template.dart';
import 'quitclaim_inputs.dart';

List<ValidationError> validateQuitclaim(QuitclaimInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errors.add(const ValidationError('employee', 'Select an employee.'));
  }
  if (i.companyId.isEmpty) {
    errors.add(const ValidationError('company', 'Select a hiring entity.'));
  }
  if (i.employeeAddress.trim().isEmpty) {
    errors.add(
      const ValidationError('employeeAddress', 'Employee address is required.'),
    );
  }
  if (i.civilStatus.trim().isEmpty) {
    errors.add(
      const ValidationError('civilStatus', 'Civil status is required.'),
    );
  }
  if (i.placeSigned.trim().isEmpty) {
    errors.add(
      const ValidationError('placeSigned', 'Place of signing is required.'),
    );
  }
  if (i.finalPayAmount <= Decimal.zero) {
    errors.add(
      const ValidationError(
        'finalPayAmount',
        'Final pay must be greater than zero.',
      ),
    );
  }
  if (i.dateTerminated != null && i.dateSigned.isBefore(i.dateTerminated!)) {
    errors.add(
      const ValidationError(
        'dateSigned',
        'Date signed must be on or after date terminated.',
      ),
    );
  }
  return errors;
}
