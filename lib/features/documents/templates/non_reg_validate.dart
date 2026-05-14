import 'document_template.dart';
import 'non_reg_inputs.dart';

List<ValidationError> validateNonReg(NonRegInputs i) {
  final errs = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errs.add(const ValidationError('employee', 'Select an employee.'));
  }
  if (i.companyId.isEmpty) {
    errs.add(const ValidationError('company', 'Select a hiring entity.'));
  }
  if (i.hrManagerName == null || i.hrManagerName!.trim().isEmpty) {
    errs.add(const ValidationError(
        'hrManagerName', 'HR manager name is required.'));
  }
  if (i.salutationName.trim().isEmpty) {
    errs.add(const ValidationError(
        'salutationName', 'Salutation cannot be empty.'));
  }
  if (i.probationaryStart == null) {
    errs.add(const ValidationError(
        'probationaryStart', 'Probationary start date is required.'));
  }
  if (i.probationaryEnd == null) {
    errs.add(const ValidationError(
        'probationaryEnd', 'Probationary end date is required.'));
  }
  if (i.effectiveEndDate == null) {
    errs.add(const ValidationError(
        'effectiveEndDate', 'Effective end date is required.'));
  }
  if (i.findings.isEmpty) {
    errs.add(const ValidationError(
        'findings', 'Add at least one finding section.'));
  }
  return errs;
}
