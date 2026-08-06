import 'package:flutter_quill/quill_delta.dart';

import 'document_template.dart';
import 'nte_inputs.dart';

bool _deltaIsEmpty(Delta delta) {
  // Treat a delta with only whitespace + newline ops as empty.
  for (final op in delta.toList()) {
    final data = op.data;
    if (data is String && data.trim().isNotEmpty) return false;
  }
  return true;
}

List<ValidationError> validateNte(NteInputs i) {
  final errs = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errs.add(const ValidationError('employee', 'Select an employee.'));
  }
  if (i.companyId.isEmpty) {
    errs.add(const ValidationError('company', 'Select a hiring entity.'));
  }
  if (i.hrManagerName == null || i.hrManagerName!.isEmpty) {
    errs.add(
      const ValidationError('hrManagerName', 'HR manager name is required.'),
    );
  }
  if (i.charges.isEmpty) {
    errs.add(const ValidationError('charges', 'Add at least one charge.'));
  }
  for (var idx = 0; idx < i.charges.length; idx++) {
    final c = i.charges[idx];
    if (c.title.trim().isEmpty) {
      errs.add(
        ValidationError('charges[$idx].title', 'Charge title is required.'),
      );
    }
    if (_deltaIsEmpty(c.body)) {
      errs.add(
        ValidationError('charges[$idx].body', 'Charge body cannot be empty.'),
      );
    }
  }
  if (i.applicableViolations.isEmpty) {
    errs.add(
      const ValidationError(
        'applicableViolations',
        'Add at least one applicable violation.',
      ),
    );
  }
  for (var idx = 0; idx < i.applicableViolations.length; idx++) {
    if (i.applicableViolations[idx].trim().isEmpty) {
      errs.add(
        ValidationError(
          'applicableViolations[$idx]',
          'Violation text cannot be empty.',
        ),
      );
    }
  }
  if (!i.responseDeadline.isAfter(i.dateIssued)) {
    errs.add(
      const ValidationError(
        'responseDeadline',
        'Response deadline must be after the date issued.',
      ),
    );
  }
  return errs;
}
