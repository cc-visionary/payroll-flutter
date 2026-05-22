import 'document_template.dart';
import 'employment_contract_inputs.dart';

List<ValidationError> validateEmploymentContract(
    EmploymentContractInputs i) {
  final errs = <ValidationError>[];
  void req(bool empty, String field, String msg) {
    if (empty) errs.add(ValidationError(field, msg));
  }

  req(i.employeeId.isEmpty, 'employee', 'Select an employee.');
  req(i.companyId.isEmpty, 'company', 'Select a hiring entity.');
  req(i.employeeFullName.trim().isEmpty, 'employeeFullName',
      'Employee name is required.');
  req(i.employeeAddress.trim().isEmpty, 'employeeAddress',
      'Employee address is required.');
  req(i.companyName.trim().isEmpty, 'companyName',
      'Company name is required.');
  req(i.companyAddress.trim().isEmpty, 'companyAddress',
      'Company address is required.');
  req(i.representativeName.trim().isEmpty, 'representativeName',
      'Company representative name is required.');
  req(i.representativeRole.trim().isEmpty, 'representativeRole',
      'Company representative role is required.');
  req(i.place.trim().isEmpty, 'place', 'Place of execution is required.');
  req(i.industry.trim().isEmpty, 'industry', 'Industry is required.');
  req(i.position.trim().isEmpty, 'position', 'Position is required.');
  req(i.monthlySalary.trim().isEmpty, 'monthlySalary',
      'Monthly salary is required.');
  req(i.employerSignatoryName.trim().isEmpty, 'employerSignatoryName',
      'Employer signatory name is required.');
  req(i.employerSignatoryRole.trim().isEmpty, 'employerSignatoryRole',
      'Employer signatory role is required.');
  req(i.workDaysPerWeek.trim().isEmpty, 'workDaysPerWeek',
      'Work days per week is required.');

  if (i.probationStart == null) {
    errs.add(const ValidationError(
        'probationStart', 'Probationary start date is required.'));
  }
  if (i.probationEnd == null) {
    errs.add(const ValidationError(
        'probationEnd', 'Probationary end date is required.'));
  }
  final ps = i.probationStart;
  final pe = i.probationEnd;
  if (ps != null && pe != null && pe.isBefore(ps)) {
    errs.add(const ValidationError('probationEnd',
        'Probationary end must be on or after the start.'));
  }

  if (i.workHoursPerDay <= 0) {
    errs.add(const ValidationError(
        'workHoursPerDay', 'Work hours per day must be greater than 0.'));
  }
  if (i.nonCompeteMonths <= 0) {
    errs.add(const ValidationError(
        'nonCompeteMonths', 'Non-compete period must be greater than 0.'));
  }

  if (i.responsibilities.isEmpty) {
    errs.add(const ValidationError(
        'responsibilities', 'Add at least one responsibility area (Annex A).'));
  }
  for (var ri = 0; ri < i.responsibilities.length; ri++) {
    final r = i.responsibilities[ri];
    if (r.area.trim().isEmpty) {
      errs.add(ValidationError(
          'responsibilities[$ri].area', 'Responsibility area is required.'));
    }
    if (r.tasks.where((t) => t.trim().isNotEmpty).isEmpty) {
      errs.add(ValidationError('responsibilities[$ri].tasks',
          'Add at least one task for this area.'));
    }
  }

  return errs;
}
