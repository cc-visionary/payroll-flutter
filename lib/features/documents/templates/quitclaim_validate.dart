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
  if (i.companySignatoryName == null || i.companySignatoryName!.isEmpty) {
    errors.add(const ValidationError(
        'signatoryName', 'Signatory name is required.'));
  }
  if (i.companySignatoryRole == null || i.companySignatoryRole!.isEmpty) {
    errors.add(const ValidationError(
        'signatoryRole', 'Signatory role is required.'));
  }
  if (i.dateTerminated == null) {
    errors.add(const ValidationError(
        'dateTerminated', 'Date terminated is required.'));
  }
  if (i.finalPayAmount <= Decimal.zero) {
    errors.add(const ValidationError(
        'finalPayAmount', 'Final pay must be greater than zero.'));
  }
  if (i.dateTerminated != null &&
      i.dateSigned.isBefore(i.dateTerminated!)) {
    errors.add(const ValidationError(
        'dateSigned', 'Date signed must be on or after date terminated.'));
  }
  return errors;
}
