import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/applicant.dart';
import 'package:decimal/decimal.dart';

void main() {
  test('Applicant constructs with required fields and exposes fullName', () {
    final a = Applicant(
      id: 'a1',
      companyId: 'c1',
      firstName: 'Maria',
      lastName: 'Santos',
      email: 'maria@example.com',
      status: 'NEW',
      statusChangedAt: DateTime.utc(2026, 5, 30),
      appliedAt: DateTime.utc(2026, 5, 30),
      createdAt: DateTime.utc(2026, 5, 30),
      updatedAt: DateTime.utc(2026, 5, 30),
    );
    expect(a.fullName, 'Maria Santos');
    expect(a.expectedSalaryMax, isNull);
  });

  test('Applicant fullName composes middle name and suffix when present', () {
    final a = Applicant(
      id: 'a2',
      companyId: 'c1',
      firstName: 'Juan',
      middleName: 'Dela',
      lastName: 'Cruz',
      suffix: 'Jr.',
      email: 'juan@example.com',
      status: 'NEW',
      statusChangedAt: DateTime.utc(2026, 5, 30),
      appliedAt: DateTime.utc(2026, 5, 30),
      createdAt: DateTime.utc(2026, 5, 30),
      updatedAt: DateTime.utc(2026, 5, 30),
    );
    expect(a.fullName, 'Juan Dela Cruz Jr.');
  });

  test(
    'Applicant.fromRow parses every column including nullable salary range',
    () {
      final r = <String, dynamic>{
        'id': 'a1',
        'company_id': 'c1',
        'first_name': 'Maria',
        'middle_name': null,
        'last_name': 'Santos',
        'suffix': null,
        'email': 'maria@example.com',
        'phone_number': '0917-000-0000',
        'mobile_number': null,
        'role_scorecard_id': 'sc1',
        'custom_job_title': null,
        'department_id': null,
        'hiring_entity_id': 'he1',
        'source': 'Referral',
        'referred_by_id': 'emp1',
        'resume_path': null,
        'resume_file_name': null,
        'cover_letter_path': null,
        'portfolio_url': null,
        'linkedin_url': null,
        'offer_letter_path': null,
        'expected_salary_min': '40000.00',
        'expected_salary_max': '45000.00',
        'expected_start_date': '2026-06-15',
        'status': 'OFFER',
        'status_changed_at': '2026-05-30T10:00:00Z',
        'status_changed_by_id': 'u1',
        'notes': null,
        'rejection_reason': null,
        'withdrawal_reason': null,
        'converted_to_employee_id': null,
        'converted_at': null,
        'applied_at': '2026-05-25T08:00:00Z',
        'created_by_id': 'u1',
        'created_at': '2026-05-25T08:00:00Z',
        'updated_at': '2026-05-30T10:00:00Z',
        'deleted_at': null,
      };
      final a = ApplicantFromRow.fromRow(r);
      expect(a.id, 'a1');
      expect(a.firstName, 'Maria');
      expect(a.lastName, 'Santos');
      expect(a.email, 'maria@example.com');
      expect(a.roleScorecardId, 'sc1');
      expect(a.hiringEntityId, 'he1');
      expect(a.source, 'Referral');
      expect(a.referredById, 'emp1');
      expect(a.expectedSalaryMin, Decimal.parse('40000.00'));
      expect(a.expectedSalaryMax, Decimal.parse('45000.00'));
      expect(a.expectedStartDate, DateTime.parse('2026-06-15'));
      expect(a.status, 'OFFER');
      expect(a.statusChangedAt.toUtc(), DateTime.utc(2026, 5, 30, 10));
      expect(a.appliedAt.toUtc(), DateTime.utc(2026, 5, 25, 8));
      expect(a.convertedToEmployeeId, isNull);
      expect(a.deletedAt, isNull);
    },
  );
}
