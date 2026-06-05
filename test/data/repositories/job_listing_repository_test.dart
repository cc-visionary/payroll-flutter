import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/job_listing_repository.dart';

void main() {
  test('JobListingListQuery equality + hashCode', () {
    const a = JobListingListQuery(
      statuses: ['OPEN'],
      hiringEntityId: 'h1',
      roleScorecardId: 'r1',
      search: 'cashier',
    );
    const b = JobListingListQuery(
      statuses: ['OPEN'],
      hiringEntityId: 'h1',
      roleScorecardId: 'r1',
      search: 'cashier',
    );
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('JobListingListQuery distinguishes status sets', () {
    const a = JobListingListQuery(statuses: ['OPEN']);
    const b = JobListingListQuery(statuses: ['OPEN', 'PAUSED']);
    expect(a, isNot(equals(b)));
  });
}
