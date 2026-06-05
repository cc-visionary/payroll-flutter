import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/applicant_repository.dart';

void main() {
  test('listingId: null defaults (no scoping)', () {
    const q = ApplicantListQuery();
    expect(q.listingId, isNull);
    expect(q.listingIsExplicitlyNull, isFalse);
  });

  test('listingId: "uuid" scopes to one listing', () {
    const q = ApplicantListQuery(listingId: 'abc');
    expect(q.listingId, 'abc');
    expect(q.listingIsExplicitlyNull, isFalse);
  });

  test('Talent Pool (listingIsExplicitlyNull: true) ≠ no-scope', () {
    const a = ApplicantListQuery();
    const b = ApplicantListQuery(listingIsExplicitlyNull: true);
    expect(a, isNot(equals(b)));
  });

  test('equality includes listingId', () {
    const a = ApplicantListQuery(listingId: 'x');
    const b = ApplicantListQuery(listingId: 'x');
    const c = ApplicantListQuery(listingId: 'y');
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
