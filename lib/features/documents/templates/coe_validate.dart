import 'document_template.dart';
import 'coe_inputs.dart';

List<ValidationError> validateCoe(CoeInputs i) {
  final errs = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errs.add(const ValidationError('employee', 'Select an employee.'));
  }
  if (i.companyId.isEmpty) {
    errs.add(const ValidationError('company', 'Select a hiring entity.'));
  }
  if (i.position.isEmpty) {
    errs.add(const ValidationError('position', 'Position is required.'));
  }
  if (i.dateStart == null) {
    errs.add(
        const ValidationError('dateStart', 'Hire date is required.'));
  }
  if (i.dateEnd == null) {
    errs.add(const ValidationError(
        'dateEnd', 'Separation date is required.'));
  }
  if (i.dateStart != null &&
      i.dateEnd != null &&
      i.dateEnd!.isBefore(i.dateStart!)) {
    errs.add(const ValidationError(
        'dateEnd', 'Separation date must be on or after hire date.'));
  }
  if (i.hrManagerName == null || i.hrManagerName!.isEmpty) {
    errs.add(const ValidationError(
        'hrManagerName', 'HR manager name is required.'));
  }
  if (i.place.trim().isEmpty) {
    errs.add(const ValidationError('place', 'Place of issuance is required.'));
  }
  return errs;
}
