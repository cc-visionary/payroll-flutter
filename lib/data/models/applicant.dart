import 'package:decimal/decimal.dart';

/// Plain-Dart model mirroring the `applicants` table from
/// supabase/migrations/20260414000006_applicants.sql.
///
/// All FK columns (role_scorecard_id, hiring_entity_id, department_id,
/// referred_by_id, converted_to_employee_id) reference existing tables —
/// we never duplicate the referenced record into this model.
class Applicant {
  final String id;
  final String companyId;
  // Identity
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? suffix;
  final String email;
  final String? phoneNumber;
  final String? mobileNumber;
  // Role (FK reuse — same entities used by Employee)
  final String? roleScorecardId;
  final String? customJobTitle; // ignored by v1 (hard-gate scorecard)
  final String? departmentId;
  final String? hiringEntityId;
  // Sourcing
  final String? source;
  final String? referredById;
  final String? listingId;
  final String? linkedinUrl;
  final String? portfolioUrl;
  // Files (deferred to v2)
  final String? resumePath;
  final String? resumeFileName;
  final String? coverLetterPath;
  final String? offerLetterPath;
  // Offer
  final Decimal? expectedSalaryMin;
  final Decimal? expectedSalaryMax;
  final DateTime? expectedStartDate;
  // Status
  final String status;
  final DateTime statusChangedAt;
  final String? statusChangedById;
  final String? notes;
  final String? rejectionReason;
  final String? withdrawalReason;
  // Conversion
  final String? convertedToEmployeeId;
  final DateTime? convertedAt;
  // Audit
  final DateTime appliedAt;
  final String? createdById;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Applicant({
    required this.id,
    required this.companyId,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.suffix,
    required this.email,
    this.phoneNumber,
    this.mobileNumber,
    this.roleScorecardId,
    this.customJobTitle,
    this.departmentId,
    this.hiringEntityId,
    this.source,
    this.referredById,
    this.listingId,
    this.linkedinUrl,
    this.portfolioUrl,
    this.resumePath,
    this.resumeFileName,
    this.coverLetterPath,
    this.offerLetterPath,
    this.expectedSalaryMin,
    this.expectedSalaryMax,
    this.expectedStartDate,
    required this.status,
    required this.statusChangedAt,
    this.statusChangedById,
    this.notes,
    this.rejectionReason,
    this.withdrawalReason,
    this.convertedToEmployeeId,
    this.convertedAt,
    required this.appliedAt,
    this.createdById,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  String get fullName => [
    firstName,
    middleName,
    lastName,
    suffix,
  ].where((s) => s != null && s.isNotEmpty).cast<String>().join(' ');
}

extension ApplicantFromRow on Applicant {
  static Applicant fromRow(Map<String, dynamic> r) {
    Decimal? dec(Object? v) => v == null ? null : Decimal.parse(v.toString());
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return Applicant(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      firstName: r['first_name'] as String,
      middleName: r['middle_name'] as String?,
      lastName: r['last_name'] as String,
      suffix: r['suffix'] as String?,
      email: r['email'] as String,
      phoneNumber: r['phone_number'] as String?,
      mobileNumber: r['mobile_number'] as String?,
      roleScorecardId: r['role_scorecard_id'] as String?,
      customJobTitle: r['custom_job_title'] as String?,
      departmentId: r['department_id'] as String?,
      hiringEntityId: r['hiring_entity_id'] as String?,
      source: r['source'] as String?,
      referredById: r['referred_by_id'] as String?,
      listingId: r['listing_id'] as String?,
      linkedinUrl: r['linkedin_url'] as String?,
      portfolioUrl: r['portfolio_url'] as String?,
      resumePath: r['resume_path'] as String?,
      resumeFileName: r['resume_file_name'] as String?,
      coverLetterPath: r['cover_letter_path'] as String?,
      offerLetterPath: r['offer_letter_path'] as String?,
      expectedSalaryMin: dec(r['expected_salary_min']),
      expectedSalaryMax: dec(r['expected_salary_max']),
      expectedStartDate: dt(r['expected_start_date']),
      status: r['status'] as String,
      statusChangedAt: dt(r['status_changed_at'])!,
      statusChangedById: r['status_changed_by_id'] as String?,
      notes: r['notes'] as String?,
      rejectionReason: r['rejection_reason'] as String?,
      withdrawalReason: r['withdrawal_reason'] as String?,
      convertedToEmployeeId: r['converted_to_employee_id'] as String?,
      convertedAt: dt(r['converted_at']),
      appliedAt: dt(r['applied_at'])!,
      createdById: r['created_by_id'] as String?,
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
      deletedAt: dt(r['deleted_at']),
    );
  }
}
