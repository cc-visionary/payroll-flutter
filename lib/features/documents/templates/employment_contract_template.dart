import 'package:flutter/material.dart' show Icons, IconData;

import '../blocks/block.dart';
import 'document_template.dart';
import 'employment_contract_inputs.dart';
import 'employment_contract_validate.dart';

class EmploymentContractTemplate
    extends DocumentTemplate<EmploymentContractInputs> {
  const EmploymentContractTemplate();

  @override
  String get id => 'employment_contract';
  @override
  String get name => 'Employment Contract';
  @override
  String get description =>
      'Probationary employment agreement with Annex A duties.';
  @override
  IconData get icon => Icons.assignment_outlined;
  @override
  int get version => 1;

  @override
  EmploymentContractInputs emptyInputs() {
    final today = DateTime.now();
    return EmploymentContractInputs(
      employeeId: '',
      employeeFullName: '',
      employeeAddress: '',
      companyId: '',
      companyName: '',
      companyAddress: '',
      representativeName: '',
      representativeRole: 'People Manager',
      place: '',
      dateEntered: today,
      industry: 'Retail Industry',
      position: '',
      monthlySalary: '',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Saturday',
      nonCompeteMonths: 24,
      employerSignatoryName: '',
      employerSignatoryRole: '',
      responsibilities: const [],
      kpis: const [],
    );
  }

  @override
  Future<EmploymentContractInputs> autofill(AutofillContext ctx) async =>
      emptyInputs();

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(EmploymentContractInputs inputs) =>
      validateEmploymentContract(inputs);

  @override
  List<Block> build(EmploymentContractInputs i) => const [];
}
