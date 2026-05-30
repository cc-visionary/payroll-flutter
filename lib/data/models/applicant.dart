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

  String get fullName => [firstName, middleName, lastName, suffix]
      .where((s) => s != null && s.isNotEmpty)
      .cast<String>()
      .join(' ');
}
