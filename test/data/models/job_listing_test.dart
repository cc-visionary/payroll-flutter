import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/job_listing.dart';

void main() {
  test('fromRow → toUpsertPayload round-trips required fields', () {
    final row = {
      'id': '11111111-1111-1111-1111-111111111111',
      'company_id': '22222222-2222-2222-2222-222222222222',
      'hiring_entity_id': '33333333-3333-3333-3333-333333333333',
      'role_scorecard_id': '44444444-4444-4444-4444-444444444444',
      'title': 'Cashier',
      'target_headcount': 3,
      'status': 'OPEN',
      'notes': 'Need 3 by EOQ',
      'created_at': '2026-06-05T10:00:00Z',
      'created_by_id': '55555555-5555-5555-5555-555555555555',
      'closed_at': null,
      'deleted_at': null,
      'updated_at': '2026-06-05T10:00:00Z',
    };
    final j = JobListing.fromRow(row);
    expect(j.id, row['id']);
    expect(j.companyId, row['company_id']);
    expect(j.hiringEntityId, row['hiring_entity_id']);
    expect(j.roleScorecardId, row['role_scorecard_id']);
    expect(j.title, 'Cashier');
    expect(j.targetHeadcount, 3);
    expect(j.status, 'OPEN');
    expect(j.notes, 'Need 3 by EOQ');
    expect(j.closedAt, isNull);
    expect(j.deletedAt, isNull);

    final payload = j.toUpsertPayload();
    expect(payload['company_id'], row['company_id']);
    expect(payload['hiring_entity_id'], row['hiring_entity_id']);
    expect(payload['role_scorecard_id'], row['role_scorecard_id']);
    expect(payload['title'], 'Cashier');
    expect(payload['target_headcount'], 3);
    expect(payload['status'], 'OPEN');
    expect(payload['notes'], 'Need 3 by EOQ');
  });

  test('copyWith preserves untouched fields', () {
    final j = JobListing(
      id: 'a',
      companyId: 'co',
      hiringEntityId: 'he',
      roleScorecardId: 'rs',
      title: 'Cashier',
      targetHeadcount: 1,
      status: 'OPEN',
      createdAt: DateTime(2026, 6, 5),
    );
    final j2 = j.copyWith(title: 'Senior Cashier', targetHeadcount: 2);
    expect(j2.title, 'Senior Cashier');
    expect(j2.targetHeadcount, 2);
    expect(j2.status, 'OPEN');
    expect(j2.id, 'a');
  });
}
