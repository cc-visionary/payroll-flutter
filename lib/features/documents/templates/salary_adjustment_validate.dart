import 'package:decimal/decimal.dart';

import 'document_template.dart';
import 'salary_adjustment_inputs.dart';

List<ValidationError> validateSalaryAdjustment(SalaryAdjustmentInputs i) {
  final errors = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errors.add(const ValidationError('employee', 'Select an employee'));
  }
  if (i.employeeFullName.trim().isEmpty) {
    errors.add(
      const ValidationError('employeeFullName', 'Employee name is required'),
    );
  }
  if (i.companyId.isEmpty) {
    errors.add(const ValidationError('company', 'Select a company'));
  }
  if (i.hrManagerName.trim().isEmpty) {
    errors.add(
      const ValidationError('hrManager', 'HR manager name is required'),
    );
  }
  if (i.signatoryRole.trim().isEmpty) {
    errors.add(
      const ValidationError('signatoryRole', 'Signatory title is required'),
    );
  }
  final sigName = i.hrManagerName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final empName = i.employeeFullName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (sigName.isNotEmpty && sigName == empName) {
    errors.add(const ValidationError(
      'hrManager',
      'The signatory cannot be the employee being adjusted — choose another approver.',
    ));
  }
  if (i.oldSalary <= Decimal.zero) {
    errors.add(
      const ValidationError('oldSalary', 'Current salary must be positive'),
    );
  }
  if (i.newSalary <= Decimal.zero) {
    errors.add(
      const ValidationError('newSalary', 'New salary must be positive'),
    );
  }
  if (i.type == SalaryAdjustmentType.lateral) {
    if (i.oldSalary != i.newSalary) {
      errors.add(
        const ValidationError(
          'newSalary',
          'A lateral transfer keeps salary unchanged',
        ),
      );
    }
  } else if (i.oldSalary == i.newSalary) {
    errors.add(
      const ValidationError('newSalary', 'New salary must differ from current'),
    );
  }
  if (i.reason.trim().isEmpty) {
    errors.add(const ValidationError('reason', 'Reason is required'));
  }
  if (i.type.isRoleChange) {
    final newId = i.newRoleScorecardId ?? '';
    if (newId.isEmpty) {
      errors.add(
        const ValidationError(
          'newRoleScorecardId',
          'Select the target role scorecard',
        ),
      );
    } else if (newId == (i.oldRoleScorecardId ?? '')) {
      errors.add(
        const ValidationError(
          'newRoleScorecardId',
          'Target role must differ from current',
        ),
      );
    }
  }
  return errors;
}
