import 'package:decimal/decimal.dart';

import 'document_template.dart';
import 'final_pay_inputs.dart';

List<ValidationError> validateFinalPay(FinalPayInputs i) {
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
  if (i.lastNetPay < Decimal.zero) {
    errors.add(
      const ValidationError('lastNetPay', 'Last net pay cannot be negative'),
    );
  }
  if (i.thirteenthMonth < Decimal.zero) {
    errors.add(
      const ValidationError(
        'thirteenthMonth',
        '13th-month pay cannot be negative',
      ),
    );
  }
  if (i.unusedLeaveConversion < Decimal.zero) {
    errors.add(
      const ValidationError(
        'unusedLeaveConversion',
        'Leave conversion cannot be negative',
      ),
    );
  }
  if (i.outstandingCashAdvance < Decimal.zero) {
    errors.add(
      const ValidationError(
        'outstandingCashAdvance',
        'Cash advance cannot be negative',
      ),
    );
  }
  if (i.otherDeductions < Decimal.zero) {
    errors.add(
      const ValidationError(
        'otherDeductions',
        'Other deductions cannot be negative',
      ),
    );
  }
  if (i.releaseDate.isBefore(i.computedAsOf)) {
    errors.add(
      const ValidationError(
        'releaseDate',
        'Release date must be on or after the computation date',
      ),
    );
  }
  return errors;
}
