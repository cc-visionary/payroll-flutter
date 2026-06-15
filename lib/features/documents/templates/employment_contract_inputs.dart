import 'dart:typed_data';

import 'document_template.dart';

class ContractResponsibility {
  final String area;
  final List<String> tasks;
  const ContractResponsibility({required this.area, required this.tasks});

  Map<String, dynamic> toJson() => {'area': area, 'tasks': tasks};
}

class ContractKpi {
  final String metric;
  final String frequency;
  const ContractKpi({required this.metric, required this.frequency});

  Map<String, dynamic> toJson() => {'metric': metric, 'frequency': frequency};
}

/// Optional graduated "training wage" terms for §5 COMPENSATION. When
/// present, the contract states a reduced daily training allowance for the
/// first [trainingDays] days, with the full salary applying upon passing the
/// evaluation (end of training, or end of the 1st month on a second pass).
class TrainingWage {
  final String dailyRate; // formatted like monthlySalary, e.g. "350"
  final int trainingDays; // e.g. 7
  const TrainingWage({required this.dailyRate, required this.trainingDays});

  Map<String, dynamic> toJson() =>
      {'dailyRate': dailyRate, 'trainingDays': trainingDays};
}

/// Sentinel for `copyWith` so nullable fields can be explicitly cleared
/// (passing `null`) vs. left unchanged (omitted).
const Object _unset = Object();

class EmploymentContractInputs extends TemplateInputs {
  // Parties
  // Exactly one of these must be populated. Applicant-mode generates an
  // offer letter; Employee-mode generates the regularization contract.
  final String? employeeId;
  final String? applicantId;
  final String employeeFullName;
  final String employeeAddress;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String representativeName;
  final String representativeRole;
  // Recitals / clauses
  final String place;
  final DateTime dateEntered;
  final String industry;
  final String position;
  final DateTime? probationStart;
  final DateTime? probationEnd;
  final String monthlySalary;
  final String salaryPeriod;
  final int workHoursPerDay;
  final String workDaysPerWeek;
  final int nonCompeteMonths;
  // Optional graduated training wage (null ⇒ clause omitted).
  final TrainingWage? trainingWage;
  // Signatories
  final String employerSignatoryName;
  final String employerSignatoryRole;
  final String witness1Name;
  final String witness1Role;
  final String witness2Name;
  final String witness2Role;
  // Annex A
  final String missionStatement;
  final List<ContractResponsibility> responsibilities;
  final List<ContractKpi> kpis;
  // Branding
  final Uint8List? logoBytes;

  EmploymentContractInputs({
    this.employeeId,
    this.applicantId,
    required this.employeeFullName,
    required this.employeeAddress,
    required this.companyId,
    required this.companyName,
    required this.companyAddress,
    required this.representativeName,
    required this.representativeRole,
    required this.place,
    required this.dateEntered,
    required this.industry,
    required this.position,
    this.probationStart,
    this.probationEnd,
    required this.monthlySalary,
    this.salaryPeriod = 'month',
    required this.workHoursPerDay,
    required this.workDaysPerWeek,
    required this.nonCompeteMonths,
    this.trainingWage,
    required this.employerSignatoryName,
    required this.employerSignatoryRole,
    this.witness1Name = '',
    this.witness1Role = '',
    this.witness2Name = '',
    this.witness2Role = '',
    this.missionStatement = '',
    this.responsibilities = const [],
    this.kpis = const [],
    this.logoBytes,
  }) : assert(
          (employeeId == null) != (applicantId == null),
          'Exactly one of employeeId or applicantId must be set',
        );

  EmploymentContractInputs copyWith({
    Object? employeeId = _unset,
    Object? applicantId = _unset,
    String? employeeFullName,
    String? employeeAddress,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? representativeName,
    String? representativeRole,
    String? place,
    DateTime? dateEntered,
    String? industry,
    String? position,
    Object? probationStart = _unset,
    Object? probationEnd = _unset,
    String? monthlySalary,
    String? salaryPeriod,
    int? workHoursPerDay,
    String? workDaysPerWeek,
    int? nonCompeteMonths,
    Object? trainingWage = _unset,
    String? employerSignatoryName,
    String? employerSignatoryRole,
    String? witness1Name,
    String? witness1Role,
    String? witness2Name,
    String? witness2Role,
    String? missionStatement,
    List<ContractResponsibility>? responsibilities,
    List<ContractKpi>? kpis,
    Uint8List? logoBytes,
  }) =>
      EmploymentContractInputs(
        employeeId: identical(employeeId, _unset)
            ? this.employeeId
            : employeeId as String?,
        applicantId: identical(applicantId, _unset)
            ? this.applicantId
            : applicantId as String?,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeeAddress: employeeAddress ?? this.employeeAddress,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        representativeName: representativeName ?? this.representativeName,
        representativeRole: representativeRole ?? this.representativeRole,
        place: place ?? this.place,
        dateEntered: dateEntered ?? this.dateEntered,
        industry: industry ?? this.industry,
        position: position ?? this.position,
        probationStart: identical(probationStart, _unset)
            ? this.probationStart
            : probationStart as DateTime?,
        probationEnd: identical(probationEnd, _unset)
            ? this.probationEnd
            : probationEnd as DateTime?,
        monthlySalary: monthlySalary ?? this.monthlySalary,
        salaryPeriod: salaryPeriod ?? this.salaryPeriod,
        workHoursPerDay: workHoursPerDay ?? this.workHoursPerDay,
        workDaysPerWeek: workDaysPerWeek ?? this.workDaysPerWeek,
        nonCompeteMonths: nonCompeteMonths ?? this.nonCompeteMonths,
        trainingWage: identical(trainingWage, _unset)
            ? this.trainingWage
            : trainingWage as TrainingWage?,
        employerSignatoryName:
            employerSignatoryName ?? this.employerSignatoryName,
        employerSignatoryRole:
            employerSignatoryRole ?? this.employerSignatoryRole,
        witness1Name: witness1Name ?? this.witness1Name,
        witness1Role: witness1Role ?? this.witness1Role,
        witness2Name: witness2Name ?? this.witness2Name,
        witness2Role: witness2Role ?? this.witness2Role,
        missionStatement: missionStatement ?? this.missionStatement,
        responsibilities: responsibilities ?? this.responsibilities,
        kpis: kpis ?? this.kpis,
        logoBytes: logoBytes ?? this.logoBytes,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'applicantId': applicantId,
        'companyId': companyId,
        'position': position,
        'responsibilityCount': responsibilities.length,
        'kpiCount': kpis.length,
        'trainingWage': trainingWage == null
            ? null
            : '${trainingWage!.dailyRate}/${trainingWage!.trainingDays}d',
      };

  @override
  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'applicantId': applicantId,
        'employeeFullName': employeeFullName,
        'employeeAddress': employeeAddress,
        'companyId': companyId,
        'companyName': companyName,
        'companyAddress': companyAddress,
        'representativeName': representativeName,
        'representativeRole': representativeRole,
        'place': place,
        'dateEntered': dateEntered.toIso8601String(),
        'industry': industry,
        'position': position,
        'probationStart': probationStart?.toIso8601String(),
        'probationEnd': probationEnd?.toIso8601String(),
        'monthlySalary': monthlySalary,
        'salaryPeriod': salaryPeriod,
        'workHoursPerDay': workHoursPerDay,
        'workDaysPerWeek': workDaysPerWeek,
        'nonCompeteMonths': nonCompeteMonths,
        'trainingWage': trainingWage?.toJson(),
        'employerSignatoryName': employerSignatoryName,
        'employerSignatoryRole': employerSignatoryRole,
        'witness1Name': witness1Name,
        'witness1Role': witness1Role,
        'witness2Name': witness2Name,
        'witness2Role': witness2Role,
        'missionStatement': missionStatement,
        'responsibilities': responsibilities.map((r) => r.toJson()).toList(),
        'kpis': kpis.map((k) => k.toJson()).toList(),
      };
}
