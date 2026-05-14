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
  for (var fi = 0; fi < i.findings.length; fi++) {
    final f = i.findings[fi];
    if (f.title.trim().isEmpty) {
      errs.add(ValidationError(
          'findings[$fi].title', 'Finding title is required.'));
    }
    if (f.standard.trim().isEmpty) {
      errs.add(ValidationError(
          'findings[$fi].standard', 'Standard body is required.'));
    }
    if (f.finding.trim().isEmpty) {
      errs.add(ValidationError(
          'findings[$fi].finding', 'Finding body is required.'));
    }
    for (var si = 0; si < f.subFindings.length; si++) {
      final s = f.subFindings[si];
      if (s.title.trim().isEmpty) {
        errs.add(ValidationError(
          'findings[$fi].subFindings[$si].title',
          'Sub-finding title is required.',
        ));
      }
      if (s.body.trim().isEmpty) {
        errs.add(ValidationError(
          'findings[$fi].subFindings[$si].body',
          'Sub-finding body is required.',
        ));
      }
    }
  }
  final ps = i.probationaryStart;
  final pe = i.probationaryEnd;
  final ee = i.effectiveEndDate;
  if (ps != null && pe != null && pe.isBefore(ps)) {
    errs.add(const ValidationError(
        'probationaryEnd',
        'Probationary end must be on or after the probationary start.'));
  }
  if (ps != null && ee != null && ee.isBefore(ps)) {
    errs.add(const ValidationError(
        'effectiveEndDate',
        'Effective end date must be on or after the probationary start.'));
  }
  if (pe != null && ee != null) {
    final limit = pe.add(const Duration(days: 7));
    if (ee.isAfter(limit)) {
      errs.add(const ValidationError(
          'effectiveEndDate',
          'Effective end date must be on or before probationary end + 7 days.'));
    }
  }
  return errs;
}
