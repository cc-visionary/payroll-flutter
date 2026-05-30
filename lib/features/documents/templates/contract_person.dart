import 'package:decimal/decimal.dart';

import '../../../data/models/applicant.dart';
import '../../../data/models/employee.dart';

/// Person-identity shape used by EmploymentContractTemplate. Lets the same
/// template render against an Applicant (offer letter) or an Employee
/// (employment contract) without forking the template. The role/entity
/// data is NOT carried here — those are resolved via FKs in the template's
/// autofill step, since they're identical entities for both sides.
class ContractPerson {
  final String fullName;
  final String? gender;
  final String? homeAddress;
  final Decimal? salaryHint; // expected_salary_max for applicants; null for employees (engine handles)
  final String? roleScorecardId;
  final String? hiringEntityId;
  final bool isApplicant;
  const ContractPerson({
    required this.fullName,
    this.gender,
    this.homeAddress,
    this.salaryHint,
    this.roleScorecardId,
    this.hiringEntityId,
    required this.isApplicant,
  });

  factory ContractPerson.fromApplicant(Applicant a) => ContractPerson(
        fullName: a.fullName,
        gender: null, // applicants schema has no gender column today
        homeAddress: null, // and no home address — captured at conversion time
        salaryHint: a.expectedSalaryMax,
        roleScorecardId: a.roleScorecardId,
        hiringEntityId: a.hiringEntityId,
        isApplicant: true,
      );

  factory ContractPerson.fromEmployee(Employee e) => ContractPerson(
        fullName: [e.firstName, e.middleName, e.lastName]
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .join(' '),
        gender: e.gender,
        homeAddress: null,
        salaryHint: null,
        roleScorecardId: e.roleScorecardId,
        hiringEntityId: e.hiringEntityId,
        isApplicant: false,
      );
}
