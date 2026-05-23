import 'package:decimal/decimal.dart';

/// Plain-Dart model mirroring the `employees` table.
/// Only fields used by the UI so far — extend as needed.
class Employee {
  final String id;
  final String companyId;
  final String employeeNumber;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? jobTitle;
  final String? departmentId;
  final String? roleScorecardId;
  final String? reportsToId;
  final String? hiringEntityId;
  /// Override of `hiringEntityId` for statutory remittance grouping only
  /// (SSS / PhilHealth / Pag-IBIG / BIR / employee loans). When `null` the
  /// statutory views inherit from `hiringEntityId`. Brand allocation,
  /// payroll grouping, and disbursement export always use `hiringEntityId`
  /// regardless of this column.
  final String? statutoryEntityId;
  final String employmentType;
  final String employmentStatus;
  final DateTime hireDate;
  final DateTime? regularizationDate;
  final DateTime? separationDate;
  final String? workEmail;
  final String? mobileNumber;
  final DateTime? birthDate;
  final String? gender;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? province;
  final String? zipCode;
  final bool isRankAndFile;
  final bool isOtEligible;
  final bool isNdEligible;
  final bool isHolidayPayEligible;
  final Decimal? declaredWageOverride;
  final String? declaredWageType;
  final DateTime? declaredWageEffectiveAt;
  final String? declaredWageSetById;
  final DateTime? declaredWageSetAt;
  final String? declaredWageReason;
  final bool taxOnFullEarnings;
  final String? paymentMethod;
  final String? paymentSourceAccount;
  final String? larkUserId;
  /// Running sum of BASIC_PAY earned since this employee's last 13th-month
  /// distribution. Ticks up on every payroll release; resets to 0 when a
  /// distribution pays them out.
  final Decimal accruedThirteenthMonthBasis;
  final DateTime? deletedAt;

  Employee({
    required this.id,
    required this.companyId,
    required this.employeeNumber,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.jobTitle,
    this.departmentId,
    this.roleScorecardId,
    this.reportsToId,
    this.hiringEntityId,
    this.statutoryEntityId,
    required this.employmentType,
    required this.employmentStatus,
    required this.hireDate,
    this.regularizationDate,
    this.separationDate,
    this.workEmail,
    this.mobileNumber,
    this.birthDate,
    this.gender,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.province,
    this.zipCode,
    required this.isRankAndFile,
    required this.isOtEligible,
    required this.isNdEligible,
    required this.isHolidayPayEligible,
    this.declaredWageOverride,
    this.declaredWageType,
    this.declaredWageEffectiveAt,
    this.declaredWageSetById,
    this.declaredWageSetAt,
    this.declaredWageReason,
    required this.taxOnFullEarnings,
    this.paymentMethod,
    this.paymentSourceAccount,
    this.larkUserId,
    Decimal? accruedThirteenthMonthBasis,
    this.deletedAt,
  }) : accruedThirteenthMonthBasis = accruedThirteenthMonthBasis ?? Decimal.zero;

  String get fullName => [firstName, middleName, lastName]
      .where((s) => s != null && s.isNotEmpty)
      .join(' ');

  /// 'Mr.' for male, 'Ms.' for female, or '' when unknown. Tolerant of
  /// free-text gender values ('Male'/'M'/'MALE' → Mr.; 'Female'/'F' → Ms.).
  String get honorific {
    final g = (gender ?? '').trim().toLowerCase();
    if (g.isEmpty) return '';
    if (g.startsWith('f')) return 'Ms.'; // female / f
    if (g.startsWith('m')) return 'Mr.'; // male / m
    return '';
  }

  factory Employee.fromRow(Map<String, dynamic> r) => Employee(
        id: r['id'] as String,
        companyId: r['company_id'] as String,
        employeeNumber: r['employee_number'] as String,
        firstName: r['first_name'] as String,
        middleName: r['middle_name'] as String?,
        lastName: r['last_name'] as String,
        jobTitle: r['job_title'] as String?,
        departmentId: r['department_id'] as String?,
        roleScorecardId: r['role_scorecard_id'] as String?,
        reportsToId: r['reports_to_id'] as String?,
        hiringEntityId: r['hiring_entity_id'] as String?,
        statutoryEntityId: r['statutory_entity_id'] as String?,
        employmentType: r['employment_type'] as String,
        employmentStatus: r['employment_status'] as String,
        hireDate: DateTime.parse(r['hire_date'] as String),
        regularizationDate: r['regularization_date'] == null
            ? null
            : DateTime.parse(r['regularization_date'] as String),
        separationDate: r['separation_date'] == null
            ? null
            : DateTime.parse(r['separation_date'] as String),
        workEmail: r['work_email'] as String?,
        mobileNumber: r['mobile_number'] as String?,
        birthDate: r['birth_date'] == null
            ? null
            : DateTime.parse(r['birth_date'] as String),
        gender: r['gender'] as String?,
        addressLine1: r['present_address_line1'] as String?,
        addressLine2: r['present_address_line2'] as String?,
        city: r['present_city'] as String?,
        province: r['present_province'] as String?,
        zipCode: r['present_zip_code'] as String?,
        isRankAndFile: r['is_rank_and_file'] as bool? ?? true,
        isOtEligible: r['is_ot_eligible'] as bool? ?? true,
        isNdEligible: r['is_nd_eligible'] as bool? ?? true,
        isHolidayPayEligible: r['is_holiday_pay_eligible'] as bool? ?? true,
        declaredWageOverride: r['declared_wage_override'] == null
            ? null
            : Decimal.parse(r['declared_wage_override'].toString()),
        declaredWageType: r['declared_wage_type'] as String?,
        declaredWageEffectiveAt: r['declared_wage_effective_at'] == null
            ? null
            : DateTime.parse(r['declared_wage_effective_at'] as String),
        declaredWageSetById: r['declared_wage_set_by_id'] as String?,
        declaredWageSetAt: r['declared_wage_set_at'] == null
            ? null
            : DateTime.parse(r['declared_wage_set_at'] as String),
        declaredWageReason: r['declared_wage_reason'] as String?,
        taxOnFullEarnings: r['tax_on_full_earnings'] as bool? ?? false,
        paymentMethod: r['payment_method'] as String?,
        paymentSourceAccount: r['payment_source_account'] as String?,
        larkUserId: r['lark_user_id'] as String?,
        accruedThirteenthMonthBasis:
            r['accrued_thirteenth_month_basis'] == null
                ? Decimal.zero
                : Decimal.parse(
                    r['accrued_thirteenth_month_basis'].toString()),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at'] as String),
      );
}
