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
}
