import 'package:decimal/decimal.dart';

import 'document_template.dart';
import 'regularization_inputs.dart';

List<ValidationError> validateRegularization(RegularizationInputs i) {
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
  if (i.baseSalary <= Decimal.zero) {
    errors.add(
      const ValidationError('baseSalary', 'Base salary must be positive'),
    );
  }
  if (i.hireDate != null && i.regularizationDate.isBefore(i.hireDate!)) {
    errors.add(
      const ValidationError(
        'regularizationDate',
        'Regularization date must be on or after hire date',
      ),
    );
  }
  return errors;
}
