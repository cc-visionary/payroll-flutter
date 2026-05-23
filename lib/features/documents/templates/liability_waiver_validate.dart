import 'document_template.dart';
import 'liability_waiver_inputs.dart';

List<ValidationError> validateLiabilityWaiver(LiabilityWaiverInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errors.add(const ValidationError('employee', 'Select an employee.'));
  }
  if (i.companyId.isEmpty) {
    errors.add(const ValidationError('company', 'Select a hiring entity.'));
  }
  if (i.employeeFullName.trim().isEmpty) {
    errors.add(const ValidationError(
        'employeeFullName', 'Employee full name is required.'));
  }
  if (i.employeeAddress.trim().isEmpty) {
    errors.add(const ValidationError(
        'employeeAddress', 'Employee address is required.'));
  }
  if (i.companyName.trim().isEmpty) {
    errors.add(
        const ValidationError('companyName', 'Company name is required.'));
  }
  if (i.dateOfEmployment == null) {
    errors.add(const ValidationError(
        'dateOfEmployment', 'Date of employment is required.'));
  }
  if (i.outingDate == null) {
    errors.add(
        const ValidationError('outingDate', 'Outing date is required.'));
  }
  if (i.outingLocation.trim().isEmpty) {
    errors.add(const ValidationError(
        'outingLocation', 'Outing location is required.'));
  }
  if (i.signingPlace.trim().isEmpty) {
    errors.add(const ValidationError(
        'signingPlace', 'Place of signing is required.'));
  }
  return errors;
}
