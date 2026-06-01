import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/skill_rating.dart';

void main() {
  test('SkillRating constructs with required fields', () {
    final s = SkillRating(
      id: 's1',
      checkInId: 'c1',
      skillCategory: 'KPI',
      skillName: 'Ship on time',
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    expect(s.skillCategory, 'KPI');
    expect(s.skillName, 'Ship on time');
    expect(s.selfRating, isNull);
    expect(s.managerRating, isNull);
  });

  test('SkillRating.fromRow parses all columns', () {
    final r = <String, dynamic>{
      'id': 's1',
      'check_in_id': 'c1',
      'skill_category': 'KPI',
      'skill_name': 'Lines reviewed per week',
      'self_rating': 4,
      'manager_rating': 5,
      'comments': 'Consistently strong.',
      'development_plan': 'Lead 1 critical review.',
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-15T00:00:00Z',
    };
    final s = SkillRatingFromRow.fromRow(r);
    expect(s.skillName, 'Lines reviewed per week');
    expect(s.selfRating, 4);
    expect(s.managerRating, 5);
    expect(s.developmentPlan, 'Lead 1 critical review.');
  });
}
