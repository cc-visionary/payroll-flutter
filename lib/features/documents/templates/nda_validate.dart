import 'document_template.dart';
import 'nda_inputs.dart';

List<ValidationError> validateNda(NdaInputs i) {
  final errs = <ValidationError>[];
  void req(bool empty, String f, String m) {
    if (empty) errs.add(ValidationError(f, m));
  }

  req(i.employeeId.isEmpty, 'employee', 'Select an employee.');
  req(i.companyId.isEmpty, 'company', 'Select a hiring entity.');
  req(
    i.employeeFullName.trim().isEmpty,
    'employeeFullName',
    'Employee name is required.',
  );
  req(
    i.employeePosition.trim().isEmpty,
    'employeePosition',
    'Position is required.',
  );
  req(
    i.employeeHomeAddress.trim().isEmpty,
    'employeeHomeAddress',
    'Home address is required.',
  );
  req(i.companyName.trim().isEmpty, 'companyName', 'Company name is required.');
  req(
    i.companyAddress.trim().isEmpty,
    'companyAddress',
    'Company address is required.',
  );
  req(
    i.authorizedSignatoryName.trim().isEmpty,
    'authorizedSignatoryName',
    'Authorized signatory name is required.',
  );
  if (i.effectiveDate == null) {
    errs.add(
      const ValidationError('effectiveDate', 'Effective date is required.'),
    );
  }
  return errs;
}
