import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';

Map<String, dynamic> baseRow({
  Object? wpTasks,
  Object? keyResponsibilities,
  bool isActive = true,
}) => {
  'id': 'card-1',
  'company_id': 'co-1',
  'job_title': 'Brand Associate',
  'mission_statement': 'Own the storefront.',
  'key_responsibilities': keyResponsibilities ?? [],
  'kpis': [],
  'wage_type': 'MONTHLY',
  'work_hours_per_day': 8,
  'work_days_per_week': 'Monday to Saturday',
  'is_active': isActive,
  'effective_date': '2026-01-01',
  'wp_tasks': wpTasks,
};

void main() {
  test(
    'responsibilities come from the wp_tasks embed, ordered by area_sort/task_sort '
    '(not alphabetically) — and the employment-contract prefill preserves that order',
    () {
      // Deliberately anti-alphabetical: authored (sort) order is the reverse of
      // name order, for both areas and tasks, and rows are listed out of order
      // in the embed itself — the only thing that should determine output order
      // is area_sort/task_sort.
      final card = RoleScorecard.fromRow(baseRow(
        // Also feed conflicting legacy JSON to prove the embed wins when present.
        keyResponsibilities: [
          {'area': 'Legacy area', 'tasks': ['Legacy task']},
        ],
        wpTasks: [
          {'id': 't3', 'name': 'Beta task', 'responsibility_area': 'Zulu Area', 'area_sort': 0, 'task_sort': 1},
          {'id': 't4', 'name': 'Bravo task', 'responsibility_area': 'Alpha Area', 'area_sort': 1, 'task_sort': 1},
          {'id': 't1', 'name': 'Zeta task', 'responsibility_area': 'Zulu Area', 'area_sort': 0, 'task_sort': 0},
          {'id': 't2', 'name': 'Yankee task', 'responsibility_area': 'Alpha Area', 'area_sort': 1, 'task_sort': 0},
        ],
      ));

      expect(
        card.responsibilities.map((a) => a.area).toList(),
        ['Zulu Area', 'Alpha Area'],
        reason: 'area order follows area_sort (0, 1), not alphabetical order',
      );
      expect(
        card.responsibilities[0].tasks,
        ['Zeta task', 'Beta task'],
        reason: 'task order within Zulu Area follows task_sort (0, 1)',
      );
      expect(
        card.responsibilities[1].tasks,
        ['Yankee task', 'Bravo task'],
        reason: 'task order within Alpha Area follows task_sort (0, 1)',
      );

      // Exactly what employment_contract_form.dart's _onPositionChanged does with
      // match.responsibilities when prefilling a contract from the matched role.
      final contractResponsibilities = card.responsibilities
          .map((r) => ContractResponsibility(area: r.area, tasks: r.tasks))
          .toList();

      expect(contractResponsibilities.map((c) => c.area).toList(), ['Zulu Area', 'Alpha Area']);
      expect(contractResponsibilities[0].tasks, ['Zeta task', 'Beta task']);
      expect(contractResponsibilities[1].tasks, ['Yankee task', 'Bravo task']);
    },
  );

  test('falls back to the legacy key_responsibilities JSON when wp_tasks is absent', () {
    final card = RoleScorecard.fromRow(baseRow(
      keyResponsibilities: [
        {'area': 'Sales', 'tasks': ['Greet customers', 'Process returns']},
      ],
    ));
    expect(card.responsibilities.single.area, 'Sales');
    expect(card.responsibilities.single.tasks, ['Greet customers', 'Process returns']);
  });

  test(
    'an empty wp_tasks embed is authoritative — does NOT fall back to stale '
    'legacy JSON (PostgREST returns [] for a requested-but-empty embed, not a '
    'missing key; a card whose responsibilities were all deleted must show [], '
    'not resurrect the old JSON)',
    () {
      final card = RoleScorecard.fromRow(baseRow(
        wpTasks: const [],
        keyResponsibilities: [
          {'area': 'Sales', 'tasks': ['Greet customers']},
        ],
      ));
      expect(card.responsibilities, isEmpty);
    },
  );

  test(
    'an empty wp_tasks embed on an INACTIVE card falls back to legacy JSON — a '
    'superseded/deactivated card must still resolve its duties, because payslip '
    'PDFs, dashboards and the employment contract read inactive cards via '
    'list(onlyActive: false)/byId(); treating [] as authoritative there would '
    'render an EMPTY Annex A duties clause with no error',
    () {
      final card = RoleScorecard.fromRow(baseRow(
        isActive: false,
        wpTasks: const [],
        keyResponsibilities: [
          {'area': 'Sales', 'tasks': ['Greet customers', 'Process returns']},
        ],
      ));
      expect(card.responsibilities.single.area, 'Sales');
      expect(card.responsibilities.single.tasks,
          ['Greet customers', 'Process returns']);
    },
  );

  test(
    'an ARCHIVED row is dropped from the derived responsibilities — only the '
    'ACTIVE row in the area survives; a row with no status key at all is '
    'legacy-safe and treated as active',
    () {
      final card = RoleScorecard.fromRow(baseRow(
        wpTasks: [
          {
            'id': 't1', 'name': 'Kept task', 'responsibility_area': 'Sales',
            'area_sort': 0, 'task_sort': 0, 'status': 'ACTIVE',
          },
          {
            'id': 't2', 'name': 'Archived task', 'responsibility_area': 'Sales',
            'area_sort': 0, 'task_sort': 1, 'status': 'ARCHIVED',
          },
          {
            // No 'status' key at all — a pre-status row must still be kept.
            'id': 't3', 'name': 'Legacy task', 'responsibility_area': 'Sales',
            'area_sort': 0, 'task_sort': 2,
          },
        ],
      ));
      expect(card.responsibilities.single.tasks, ['Kept task', 'Legacy task']);
    },
  );

  test('toUpsertPayload writes key_responsibilities as an empty array (NOT NULL, read-only)', () {
    final card = RoleScorecard.fromRow(baseRow(
      keyResponsibilities: [
        {'area': 'Sales', 'tasks': ['Greet customers']},
      ],
    ));
    expect(card.toUpsertPayload()['key_responsibilities'], isEmpty);
  });
}
