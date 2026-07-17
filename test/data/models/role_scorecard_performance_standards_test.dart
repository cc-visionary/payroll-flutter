import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';

Map<String, dynamic> row() => {
  'id': 's1',
  'company_id': 'c1',
  'job_title': 'Store Associate',
  'mission_statement': 'Serve customers well.',
  'key_responsibilities': [],
  'kpis': [],
  'required_skills': [
    {
      'name': 'Cash handling',
      'description': 'Processes payments accurately and follows cash controls.',
    },
  ],
  'behavioral_expectations': [
    {
      'name': 'Accountability',
      'description': 'Owns results and escalates early.',
    },
  ],
  'version': 2,
  'wage_type': 'MONTHLY',
  'work_hours_per_day': 8,
  'work_days_per_week': 'Monday to Saturday',
  'is_active': true,
  'effective_date': '2026-01-01',
};

void main() {
  test('fromRow parses versioned performance standards', () {
    final card = RoleScorecard.fromRow(row());

    expect(card.version, 2);
    expect(card.requiredSkills.single.name, 'Cash handling');
    expect(
      card.requiredSkills.single.description,
      'Processes payments accurately and follows cash controls.',
    );
    expect(card.behavioralExpectations.single.name, 'Accountability');
  });

  test('toUpsertPayload preserves performance standards', () {
    final payload = RoleScorecard.fromRow(row()).toUpsertPayload();

    expect(payload['version'], 2);
    expect((payload['required_skills'] as List).single, {
      'name': 'Cash handling',
      'description': 'Processes payments accurately and follows cash controls.',
    });
    expect((payload['behavioral_expectations'] as List).single, {
      'name': 'Accountability',
      'description': 'Owns results and escalates early.',
    });
  });

  test('legacy rows default to empty standards and version one', () {
    final legacy = row()
      ..remove('required_skills')
      ..remove('behavioral_expectations')
      ..remove('version');

    final card = RoleScorecard.fromRow(legacy);
    expect(card.requiredSkills, isEmpty);
    expect(card.behavioralExpectations, isEmpty);
    expect(card.version, 1);
  });
}
