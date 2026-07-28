import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
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

  group(
    'ANNEX A GATE (Risk #2) — a shared accountability APPENDS, it never '
    'reorders, renames, or interleaves the authored responsibilities that '
    'feed the role-card PDF and the employment contract\'s Annex A',
    () {
      // Same deliberately anti-alphabetical authored fixture as the top test
      // in this file — authored (sort) order is the reverse of name order,
      // proving order comes from area_sort/task_sort, never from anything
      // added afterward.
      Map<String, dynamic> authoredRow() => baseRow(wpTasks: [
            {'id': 't3', 'name': 'Beta task', 'responsibility_area': 'Zulu Area', 'area_sort': 0, 'task_sort': 1},
            {'id': 't4', 'name': 'Bravo task', 'responsibility_area': 'Alpha Area', 'area_sort': 1, 'task_sort': 1},
            {'id': 't1', 'name': 'Zeta task', 'responsibility_area': 'Zulu Area', 'area_sort': 0, 'task_sort': 0},
            {'id': 't2', 'name': 'Yankee task', 'responsibility_area': 'Alpha Area', 'area_sort': 1, 'task_sort': 0},
          ]);

      List<ContractResponsibility> asContractRows(RoleScorecard card) => card
          .responsibilities
          .map((r) => ContractResponsibility(area: r.area, tasks: r.tasks))
          .toList();

      test(
        'authored responsibilities are byte-identical before and after an '
        'assigned-but-not-authored accountability is unioned in — the shared '
        'row is appended as a trailing area, never interleaved',
        () {
          final before = RoleScorecard.fromRow(authoredRow());

          // A task authored on a DIFFERENT card ('other-card'), shared to
          // THIS card ('card-1', see baseRow) via a wp_task_assignments row —
          // exactly what assignedTasksByCard() returns for this card.
          final sharedTask = const WpTask(
            id: 'shared-1',
            companyId: 'co-1',
            name: 'Reconcile shared ledger',
            roleScorecardId: 'other-card',
            responsibilityArea: 'Finance Ops',
            areaSort: 99,
            taskSort: 0,
          );

          final after = before.withExtraResponsibilities(
            responsibilitiesFromAssignedTasks('card-1', [sharedTask]),
          );

          // 1. The authored prefix is untouched: same length, same area
          // names in the same order, same task lists in the same order.
          expect(
            after.responsibilities.sublist(0, before.responsibilities.length),
            before.responsibilities,
            reason: 'authored areas/tasks must be byte-identical after union',
          );
          expect(
            after.responsibilities.map((a) => a.area).take(2).toList(),
            ['Zulu Area', 'Alpha Area'],
            reason: 'authored area order (area_sort) is unchanged',
          );
          expect(after.responsibilities[0].tasks, ['Zeta task', 'Beta task']);
          expect(after.responsibilities[1].tasks, ['Yankee task', 'Bravo task']);

          // 2. The shared row is appended as its own trailing area — not
          // merged into an authored area, not inserted between them.
          expect(after.responsibilities.length, before.responsibilities.length + 1);
          expect(after.responsibilities.last.area, 'Finance Ops');
          expect(after.responsibilities.last.tasks, ['Reconcile shared ledger']);

          // 3. The exact same guarantee holds through the employment-contract
          // prefill mapping (what _onPositionChanged does with a matched
          // role). ContractResponsibility has no value == override, so
          // compare its .area/.tasks fields (Strings/List<String> compare by
          // value) rather than the objects themselves — same pattern as the
          // file's top test.
          final beforeContract = asContractRows(before);
          final afterContract = asContractRows(after);
          expect(
            afterContract.take(beforeContract.length).map((c) => c.area).toList(),
            beforeContract.map((c) => c.area).toList(),
            reason: 'Annex A prefill: authored area order/wording unchanged by the union',
          );
          for (var i = 0; i < beforeContract.length; i++) {
            expect(afterContract[i].tasks, beforeContract[i].tasks,
                reason: 'Annex A prefill: authored task order/wording unchanged at area $i');
          }
          expect(afterContract.last.area, 'Finance Ops');
          expect(afterContract.last.tasks, ['Reconcile shared ledger']);
        },
      );

      test(
        'a task with no responsibility_area lands in a trailing "Shared" '
        'bucket rather than altering any authored area',
        () {
          final before = RoleScorecard.fromRow(authoredRow());
          final sharedTask = const WpTask(
            id: 'shared-2',
            companyId: 'co-1',
            name: 'Cover overflow tickets',
            roleScorecardId: 'other-card',
          );

          final after = before.withExtraResponsibilities(
            responsibilitiesFromAssignedTasks('card-1', [sharedTask]),
          );

          expect(
            after.responsibilities.sublist(0, before.responsibilities.length),
            before.responsibilities,
          );
          expect(after.responsibilities.last.area, 'Shared');
          expect(after.responsibilities.last.tasks, ['Cover overflow tickets']);
        },
      );

      test(
        'a task both authored AND assigned to the SAME card (e.g. its PRIMARY '
        'self-assignment) is not duplicated — dedupe by task id via the '
        'author (role_scorecard_id), matching what assignedTasksByCard() '
        'would hand back for a self-owned task',
        () {
          final before = RoleScorecard.fromRow(authoredRow());
          // roleScorecardId == 'card-1' — authored BY this same card, so it
          // is already present via the wp_tasks embed and must be skipped.
          final selfAssigned = const WpTask(
            id: 't1',
            companyId: 'co-1',
            name: 'Zeta task',
            roleScorecardId: 'card-1',
            responsibilityArea: 'Zulu Area',
          );

          final extra = responsibilitiesFromAssignedTasks('card-1', [selfAssigned]);
          expect(extra, isEmpty, reason: 'self-authored task must not become a "shared" row');

          final after = before.withExtraResponsibilities(extra);
          expect(after.responsibilities, before.responsibilities);
          expect(identical(after, before), isTrue,
              reason: 'withExtraResponsibilities is a no-op copy when extra is empty');
        },
      );

      test(
        'multiple shared tasks are grouped/ordered by area_sort/task_sort '
        'among themselves, same tie-break rules as authored rows, and still '
        'trail every authored area',
        () {
          final before = RoleScorecard.fromRow(authoredRow());
          final sharedTasks = const [
            WpTask(
              id: 's-2', companyId: 'co-1', name: 'Second shared task',
              roleScorecardId: 'other-card', responsibilityArea: 'Onboarding',
              areaSort: 1, taskSort: 0,
            ),
            WpTask(
              id: 's-1', companyId: 'co-1', name: 'First shared task',
              roleScorecardId: 'other-card', responsibilityArea: 'Compliance',
              areaSort: 0, taskSort: 0,
            ),
          ];

          final after = before.withExtraResponsibilities(
            responsibilitiesFromAssignedTasks('card-1', sharedTasks),
          );

          expect(
            after.responsibilities.sublist(0, before.responsibilities.length),
            before.responsibilities,
          );
          final trailing = after.responsibilities.skip(before.responsibilities.length);
          expect(trailing.map((a) => a.area).toList(), ['Compliance', 'Onboarding']);
        },
      );
    },
  );
}
