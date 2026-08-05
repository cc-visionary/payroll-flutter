import 'package:decimal/decimal.dart';

import 'document_template.dart';
import 'penalty_agreement_inputs.dart';

List<ValidationError> validatePenaltyAgreement(PenaltyAgreementInputs i) {
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
  if (i.description.trim().isEmpty) {
    errors.add(
      const ValidationError(
        'description',
        'Describe the incident this penalty covers',
      ),
    );
  }
  if (i.totalAmount <= Decimal.zero) {
    errors.add(
      const ValidationError(
        'totalAmount',
        'Total amount must be greater than zero',
      ),
    );
  }
  if (i.installments.isEmpty) {
    errors.add(
      const ValidationError(
        'installments',
        'The repayment schedule needs at least one installment',
      ),
    );
  } else if (i.scheduledTotal != i.totalAmount) {
    // Exact Decimal compare — a schedule that does not add up to the amount
    // being deducted is not a lawful authorization to deduct it.
    errors.add(
      ValidationError(
        'installments',
        'Installments add up to ${i.scheduledTotal} but the penalty total is '
            '${i.totalAmount}',
      ),
    );
  }
  return errors;
}
