import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/applicant.dart';
import '../../data/repositories/applicant_repository.dart';
import '../employees/employee_form_screen.dart';

/// Push the EmployeeFormScreen in prefilled mode. On successful create,
/// atomically stamp converted_to_employee_id + flip status to HIRED on the
/// applicant via `markConverted`, then return to the applicant detail
/// (which will now show the HIRED state + a View Employee link).
Future<void> convertApplicantToEmployee(
  BuildContext context,
  WidgetRef ref,
  Applicant a,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EmployeeFormScreen(
        applicantSeed: ApplicantSeed(
          firstName: a.firstName,
          middleName: a.middleName,
          lastName: a.lastName,
          suffix: a.suffix,
          email: a.email,
          phoneNumber: a.phoneNumber,
          mobileNumber: a.mobileNumber,
          roleScorecardId: a.roleScorecardId,
          hiringEntityId: a.hiringEntityId,
          departmentId: a.departmentId,
          referredById: a.referredById,
          expectedStartDate: a.expectedStartDate,
          offerSalary: a.expectedSalaryMax?.toString(),
        ),
        onCreatedFromApplicant: (employeeId) async {
          try {
            await ref
                .read(applicantRepositoryProvider)
                .markConverted(applicantId: a.id, employeeId: employeeId);
            ref.invalidate(applicantByIdProvider(a.id));
            ref.invalidate(applicantListProvider);
            ref.invalidate(applicantsCountByStatusProvider);
            if (context.mounted) {
              messenger.showSnackBar(SnackBar(
                content: Text('Hired — ${a.fullName} converted to employee.'),
              ));
            }
          } catch (e) {
            if (context.mounted) {
              messenger.showSnackBar(SnackBar(
                content: Text('Conversion stamp failed: $e'),
              ));
            }
          }
        },
      ),
    ),
  );
}
