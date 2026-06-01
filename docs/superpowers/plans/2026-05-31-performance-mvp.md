# Performance MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the dormant performance schema with quarterly check-ins for REGULAR employees + per-employee 1M/3M/5M probationary milestones, auto-seeded with `skill_ratings` from each employee's RoleScorecard KPIs.

**Architecture:** Standard 3-layer Flutter (model → repo+providers → screens) over a small schema extension (probationary enum values + `target_employee_id` on `check_in_periods`). Auto-generation is lazy: runs once when `/performance` mounts, ensuring the current quarter's period + check-ins exist and that any passed probationary milestones have their own employee-specific periods + check-ins. `skill_ratings.skill_name` is intentionally snapshotted from `RoleScorecard.kpis[i].metric` at check-in creation so historical reviews don't drift when KPIs are later edited.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase (Postgres). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-31-performance-mvp-design.md`

**Parallelization:** Phase 1 sequential. Phase 2 (4 model tasks) can fan out. Phases 3-8 (repo) sequential. UI phases (9-15) sequential per file. Phase 16 (profile tab) independent.

---

## Phase 1 — Schema migration

### Task 1: Probationary enum values + `target_employee_id` on `check_in_periods`

**Files:**
- Create: `supabase/migrations/20260531000001_performance_per_employee_periods.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260531000001_performance_per_employee_periods.sql`:

```sql
-- Support per-employee probationary review periods. The existing
-- check_in_periods table is company-scoped (one period per Q1/Q2/Q3/Q4
-- for the whole company). Probationary reviews are individual milestones
-- tied to each employee's hire_date (month 1, 3, 5 from hire), so we
-- need employee-specific periods alongside the company-wide quarterly ones.

-- Add the three probationary period types to the existing check_in_type enum.
alter type check_in_type add value if not exists 'PROBATION_1M';
alter type check_in_type add value if not exists 'PROBATION_3M';
alter type check_in_type add value if not exists 'PROBATION_5M';

-- Nullable employee FK on the period. Null = company-wide (existing
-- behavior, used for quarterly cycles). Non-null = scoped to that one
-- employee (used for the 3 probationary milestones).
alter table check_in_periods
  add column target_employee_id uuid references employees(id) on delete cascade;

-- Replace the company+name unique with a 3-column unique so company-wide
-- periods (target_employee_id = null) still get a single row per name,
-- AND per-employee periods can reuse names like "Probation 1M" across
-- different employees.
alter table check_in_periods drop constraint check_in_periods_company_id_name_key;
alter table check_in_periods
  add constraint check_in_periods_company_name_target_unique
  unique (company_id, name, target_employee_id);
create index on check_in_periods (target_employee_id);
```

- [ ] **Step 2: Apply locally**

Run: `supabase db reset` (resets local DB and re-applies all migrations).
Expected: completes without errors.

If `supabase db reset` is unavailable in this environment, skip this step. The migration applies remotely on `supabase db push` post-merge.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260531000001_performance_per_employee_periods.sql
git commit -m "feat(performance): migration — probationary enum + target_employee_id"
```

---

## Phase 2 — Models

### Task 2: `CheckInPeriod` model

**Files:**
- Create: `lib/data/models/check_in_period.dart`
- Create: `test/data/models/check_in_period_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/models/check_in_period_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/check_in_period.dart';

void main() {
  test('CheckInPeriod constructs with required fields', () {
    final p = CheckInPeriod(
      id: 'p1',
      companyId: 'c1',
      name: '2026 Q2',
      periodType: 'QUARTERLY',
      startDate: DateTime.utc(2026, 4, 1),
      endDate: DateTime.utc(2026, 6, 30),
      dueDate: DateTime.utc(2026, 7, 15),
      isActive: true,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    expect(p.id, 'p1');
    expect(p.periodType, 'QUARTERLY');
    expect(p.targetEmployeeId, isNull);
  });

  test('CheckInPeriod.fromRow parses all columns including target_employee_id', () {
    final r = <String, dynamic>{
      'id': 'p2',
      'company_id': 'c1',
      'name': 'Probation 1M — Maria Santos',
      'period_type': 'PROBATION_1M',
      'start_date': '2026-04-15',
      'end_date': '2026-05-01',
      'due_date': '2026-05-08',
      'is_active': true,
      'target_employee_id': 'e1',
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-01T00:00:00Z',
    };
    final p = CheckInPeriodFromRow.fromRow(r);
    expect(p.id, 'p2');
    expect(p.periodType, 'PROBATION_1M');
    expect(p.targetEmployeeId, 'e1');
    expect(p.startDate, DateTime.parse('2026-04-15'));
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/data/models/check_in_period_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement the model**

Create `lib/data/models/check_in_period.dart`:

```dart
/// Plain-Dart model mirroring the `check_in_periods` table.
/// Periods are either company-wide (target_employee_id = null) for the
/// quarterly cycle, or employee-specific (target_employee_id set) for
/// probationary 1M/3M/5M milestones.
class CheckInPeriod {
  final String id;
  final String companyId;
  final String name;
  final String periodType;       // enum: MONTHLY|QUARTERLY|ANNUAL|PROBATION_1M|PROBATION_3M|PROBATION_5M
  final DateTime startDate;
  final DateTime endDate;
  final DateTime dueDate;
  final bool isActive;
  final String? targetEmployeeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CheckInPeriod({
    required this.id,
    required this.companyId,
    required this.name,
    required this.periodType,
    required this.startDate,
    required this.endDate,
    required this.dueDate,
    required this.isActive,
    this.targetEmployeeId,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension CheckInPeriodFromRow on CheckInPeriod {
  static CheckInPeriod fromRow(Map<String, dynamic> r) {
    DateTime dt(Object v) => DateTime.parse(v as String);
    return CheckInPeriod(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      name: r['name'] as String,
      periodType: r['period_type'] as String,
      startDate: dt(r['start_date']),
      endDate: dt(r['end_date']),
      dueDate: dt(r['due_date']),
      isActive: r['is_active'] as bool,
      targetEmployeeId: r['target_employee_id'] as String?,
      createdAt: dt(r['created_at']),
      updatedAt: dt(r['updated_at']),
    );
  }
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/data/models/check_in_period_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/check_in_period.dart test/data/models/check_in_period_test.dart
git commit -m "feat(performance): CheckInPeriod model + fromRow factory"
```

---

### Task 3: `PerformanceCheckIn` model

**Files:**
- Create: `lib/data/models/performance_check_in.dart`
- Create: `test/data/models/performance_check_in_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/models/performance_check_in_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/performance_check_in.dart';

void main() {
  test('PerformanceCheckIn constructs with required fields', () {
    final c = PerformanceCheckIn(
      id: 'c1',
      periodId: 'p1',
      employeeId: 'e1',
      status: 'DRAFT',
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    expect(c.id, 'c1');
    expect(c.status, 'DRAFT');
    expect(c.reviewerId, isNull);
    expect(c.overallRating, isNull);
  });

  test('PerformanceCheckIn.fromRow parses all columns', () {
    final r = <String, dynamic>{
      'id': 'c1',
      'period_id': 'p1',
      'employee_id': 'e1',
      'reviewer_id': 'u2',
      'status': 'SUBMITTED',
      'overall_rating': 4,
      'overall_comments': 'Strong quarter.',
      'accomplishments': 'Shipped X.',
      'challenges': 'Y was hard.',
      'learnings': 'Z',
      'support_needed': null,
      'manager_feedback': null,
      'strengths': null,
      'areas_for_improvement': null,
      'submitted_at': '2026-04-15T08:00:00Z',
      'reviewed_at': null,
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-15T08:00:00Z',
    };
    final c = PerformanceCheckInFromRow.fromRow(r);
    expect(c.id, 'c1');
    expect(c.reviewerId, 'u2');
    expect(c.overallRating, 4);
    expect(c.accomplishments, 'Shipped X.');
    expect(c.submittedAt?.toUtc(), DateTime.utc(2026, 4, 15, 8));
    expect(c.reviewedAt, isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/data/models/performance_check_in_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

Create `lib/data/models/performance_check_in.dart`:

```dart
/// Plain-Dart model mirroring the `performance_check_ins` table.
/// One row per employee per period. Constraint: unique (period_id, employee_id).
class PerformanceCheckIn {
  final String id;
  final String periodId;
  final String employeeId;
  final String? reviewerId;
  final String status;       // enum: DRAFT|SUBMITTED|UNDER_REVIEW|COMPLETED|SKIPPED
  final int? overallRating;  // 1-5
  final String? overallComments;
  final String? accomplishments;
  final String? challenges;
  final String? learnings;
  final String? supportNeeded;
  final String? managerFeedback;
  final String? strengths;
  final String? areasForImprovement;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PerformanceCheckIn({
    required this.id,
    required this.periodId,
    required this.employeeId,
    this.reviewerId,
    required this.status,
    this.overallRating,
    this.overallComments,
    this.accomplishments,
    this.challenges,
    this.learnings,
    this.supportNeeded,
    this.managerFeedback,
    this.strengths,
    this.areasForImprovement,
    this.submittedAt,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension PerformanceCheckInFromRow on PerformanceCheckIn {
  static PerformanceCheckIn fromRow(Map<String, dynamic> r) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return PerformanceCheckIn(
      id: r['id'] as String,
      periodId: r['period_id'] as String,
      employeeId: r['employee_id'] as String,
      reviewerId: r['reviewer_id'] as String?,
      status: r['status'] as String,
      overallRating: (r['overall_rating'] as num?)?.toInt(),
      overallComments: r['overall_comments'] as String?,
      accomplishments: r['accomplishments'] as String?,
      challenges: r['challenges'] as String?,
      learnings: r['learnings'] as String?,
      supportNeeded: r['support_needed'] as String?,
      managerFeedback: r['manager_feedback'] as String?,
      strengths: r['strengths'] as String?,
      areasForImprovement: r['areas_for_improvement'] as String?,
      submittedAt: dt(r['submitted_at']),
      reviewedAt: dt(r['reviewed_at']),
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
    );
  }
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/data/models/performance_check_in_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/performance_check_in.dart test/data/models/performance_check_in_test.dart
git commit -m "feat(performance): PerformanceCheckIn model + fromRow factory"
```

---

### Task 4: `CheckInGoal` model

**Files:**
- Create: `lib/data/models/check_in_goal.dart`
- Create: `test/data/models/check_in_goal_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/models/check_in_goal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/check_in_goal.dart';

void main() {
  test('CheckInGoal constructs with required fields', () {
    final g = CheckInGoal(
      id: 'g1',
      checkInId: 'c1',
      goalType: 'PERFORMANCE',
      title: 'Ship feature X',
      progress: 0,
      status: 'IN_PROGRESS',
      carryForward: false,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    expect(g.id, 'g1');
    expect(g.goalType, 'PERFORMANCE');
    expect(g.progress, 0);
    expect(g.targetDate, isNull);
  });

  test('CheckInGoal.fromRow parses all columns', () {
    final r = <String, dynamic>{
      'id': 'g1',
      'check_in_id': 'c1',
      'goal_type': 'LEARNING',
      'title': 'Read X book',
      'description': 'Notes in Notion.',
      'target_date': '2026-06-30',
      'progress': 50,
      'status': 'IN_PROGRESS',
      'self_assessment': null,
      'manager_assessment': null,
      'rating': null,
      'carry_forward': false,
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-15T00:00:00Z',
    };
    final g = CheckInGoalFromRow.fromRow(r);
    expect(g.goalType, 'LEARNING');
    expect(g.progress, 50);
    expect(g.targetDate, DateTime.parse('2026-06-30'));
    expect(g.carryForward, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/data/models/check_in_goal_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

Create `lib/data/models/check_in_goal.dart`:

```dart
/// Plain-Dart model mirroring the `check_in_goals` table.
/// One goal row per check-in (cascade-delete with parent check-in).
class CheckInGoal {
  final String id;
  final String checkInId;
  final String goalType;     // enum: PERFORMANCE|LEARNING|PROJECT|BEHAVIORAL
  final String title;
  final String? description;
  final DateTime? targetDate;
  final int progress;        // 0-100
  final String status;       // enum: NOT_STARTED|IN_PROGRESS|COMPLETED|PARTIALLY_MET|NOT_MET|DEFERRED
  final String? selfAssessment;
  final String? managerAssessment;
  final int? rating;         // 1-5
  final bool carryForward;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CheckInGoal({
    required this.id,
    required this.checkInId,
    required this.goalType,
    required this.title,
    this.description,
    this.targetDate,
    required this.progress,
    required this.status,
    this.selfAssessment,
    this.managerAssessment,
    this.rating,
    required this.carryForward,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension CheckInGoalFromRow on CheckInGoal {
  static CheckInGoal fromRow(Map<String, dynamic> r) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return CheckInGoal(
      id: r['id'] as String,
      checkInId: r['check_in_id'] as String,
      goalType: r['goal_type'] as String,
      title: r['title'] as String,
      description: r['description'] as String?,
      targetDate: dt(r['target_date']),
      progress: (r['progress'] as num).toInt(),
      status: r['status'] as String,
      selfAssessment: r['self_assessment'] as String?,
      managerAssessment: r['manager_assessment'] as String?,
      rating: (r['rating'] as num?)?.toInt(),
      carryForward: r['carry_forward'] as bool,
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
    );
  }
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/data/models/check_in_goal_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/check_in_goal.dart test/data/models/check_in_goal_test.dart
git commit -m "feat(performance): CheckInGoal model + fromRow factory"
```

---

### Task 5: `SkillRating` model

**Files:**
- Create: `lib/data/models/skill_rating.dart`
- Create: `test/data/models/skill_rating_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/models/skill_rating_test.dart`:

```dart
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
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/data/models/skill_rating_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

Create `lib/data/models/skill_rating.dart`:

```dart
/// Plain-Dart model mirroring the `skill_ratings` table.
///
/// `skill_name` is a snapshot of the employee's `RoleScorecard.kpis[i].metric`
/// at check-in creation time. This is intentional — historical reviews must
/// not drift when KPIs are later edited on the scorecard.
class SkillRating {
  final String id;
  final String checkInId;
  final String skillCategory;
  final String skillName;
  final int? selfRating;     // 1-5
  final int? managerRating;  // 1-5
  final String? comments;
  final String? developmentPlan;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SkillRating({
    required this.id,
    required this.checkInId,
    required this.skillCategory,
    required this.skillName,
    this.selfRating,
    this.managerRating,
    this.comments,
    this.developmentPlan,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension SkillRatingFromRow on SkillRating {
  static SkillRating fromRow(Map<String, dynamic> r) {
    DateTime dt(Object v) => DateTime.parse(v as String);
    return SkillRating(
      id: r['id'] as String,
      checkInId: r['check_in_id'] as String,
      skillCategory: r['skill_category'] as String,
      skillName: r['skill_name'] as String,
      selfRating: (r['self_rating'] as num?)?.toInt(),
      managerRating: (r['manager_rating'] as num?)?.toInt(),
      comments: r['comments'] as String?,
      developmentPlan: r['development_plan'] as String?,
      createdAt: dt(r['created_at']),
      updatedAt: dt(r['updated_at']),
    );
  }
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/data/models/skill_rating_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/skill_rating.dart test/data/models/skill_rating_test.dart
git commit -m "feat(performance): SkillRating model + fromRow factory"
```

---

## Phase 3 — Repository scaffold

### Task 6: `PerformanceRepository` scaffold + `PerformanceListQuery` + provider

**Files:**
- Create: `lib/data/repositories/performance_repository.dart`

- [ ] **Step 1: Implement the scaffold**

Create `lib/data/repositories/performance_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/check_in_period.dart';
import '../models/check_in_goal.dart';
import '../models/performance_check_in.dart';
import '../models/skill_rating.dart';

/// Filter parameters for the performance list. Mirrors WorkflowListQuery shape.
class PerformanceListQuery {
  final String? periodId;
  final String? employeeId;
  final List<String>? statuses;
  const PerformanceListQuery({this.periodId, this.employeeId, this.statuses});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerformanceListQuery &&
          periodId == other.periodId &&
          employeeId == other.employeeId &&
          _eq(statuses, other.statuses);

  @override
  int get hashCode => Object.hash(
        periodId,
        employeeId,
        Object.hashAll(statuses ?? const []),
      );

  static bool _eq(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class PerformanceRepository {
  final SupabaseClient _client;
  PerformanceRepository(this._client);
}

final performanceRepositoryProvider = Provider<PerformanceRepository>(
    (ref) => PerformanceRepository(Supabase.instance.client));
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/data/repositories/performance_repository.dart`
Expected: analyzer warns about unused imports (CheckInPeriod, CheckInGoal, PerformanceCheckIn, SkillRating) + unused `_client` field. All resolved in Task 7. Acceptable.

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/performance_repository.dart
git commit -m "feat(performance): PerformanceRepository scaffold + PerformanceListQuery"
```

---

## Phase 4 — Read methods

### Task 7: list / byId / goalsFor / skillRatingsFor + providers

**Files:**
- Modify: `lib/data/repositories/performance_repository.dart` (append methods + providers)

- [ ] **Step 1: Append methods + providers**

Inside the `PerformanceRepository` class, append:

```dart
  Future<List<PerformanceCheckIn>> list(PerformanceListQuery q) async {
    var builder = _client.from('performance_check_ins').select('*');
    if (q.periodId != null) {
      builder = builder.eq('period_id', q.periodId!);
    }
    if (q.employeeId != null) {
      builder = builder.eq('employee_id', q.employeeId!);
    }
    if (q.statuses != null && q.statuses!.isNotEmpty) {
      builder = builder.inFilter('status', q.statuses!);
    }
    final rows = await builder.order('created_at', ascending: false);
    return (rows as List)
        .map((r) => PerformanceCheckInFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<PerformanceCheckIn?> byId(String id) async {
    final row = await _client
        .from('performance_check_ins')
        .select('*')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return PerformanceCheckInFromRow.fromRow(row);
  }

  Future<CheckInPeriod?> periodById(String periodId) async {
    final row = await _client
        .from('check_in_periods')
        .select('*')
        .eq('id', periodId)
        .maybeSingle();
    if (row == null) return null;
    return CheckInPeriodFromRow.fromRow(row);
  }

  Future<List<CheckInGoal>> goalsFor(String checkInId) async {
    final rows = await _client
        .from('check_in_goals')
        .select('*')
        .eq('check_in_id', checkInId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => CheckInGoalFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<SkillRating>> skillRatingsFor(String checkInId) async {
    final rows = await _client
        .from('skill_ratings')
        .select('*')
        .eq('check_in_id', checkInId)
        .order('skill_category', ascending: true);
    return (rows as List)
        .map((r) => SkillRatingFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }
```

Then OUTSIDE the class, append providers:

```dart
final performanceCheckInListProvider =
    FutureProvider.family<List<PerformanceCheckIn>, PerformanceListQuery>(
        (ref, q) => ref.read(performanceRepositoryProvider).list(q));

final performanceCheckInByIdProvider =
    FutureProvider.family<PerformanceCheckIn?, String>(
        (ref, id) => ref.read(performanceRepositoryProvider).byId(id));

final checkInPeriodByIdProvider =
    FutureProvider.family<CheckInPeriod?, String>(
        (ref, id) => ref.read(performanceRepositoryProvider).periodById(id));

final checkInGoalsProvider = FutureProvider.family<List<CheckInGoal>, String>(
    (ref, checkInId) => ref.read(performanceRepositoryProvider).goalsFor(checkInId));

final skillRatingsProvider = FutureProvider.family<List<SkillRating>, String>(
    (ref, checkInId) => ref.read(performanceRepositoryProvider).skillRatingsFor(checkInId));
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/data/repositories/performance_repository.dart`
Expected: No issues (all previous warnings now resolved).

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/performance_repository.dart
git commit -m "feat(performance): list / byId / goalsFor / skillRatingsFor providers"
```

---

## Phase 5 — Period auto-gen

### Task 8: Quarter math + `ensureQuarterlyPeriodForCurrentQuarter`

**Files:**
- Create: `lib/features/performance/quarter_math.dart`
- Create: `test/features/performance/quarter_math_test.dart`
- Modify: `lib/data/repositories/performance_repository.dart` (append method)

- [ ] **Step 1: Write the failing test for the pure-Dart quarter math**

Create `test/features/performance/quarter_math_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/performance/quarter_math.dart';

void main() {
  test('quarterOf returns 1-4 based on month', () {
    expect(quarterOf(DateTime.utc(2026, 1, 15)), 1);
    expect(quarterOf(DateTime.utc(2026, 3, 31)), 1);
    expect(quarterOf(DateTime.utc(2026, 4, 1)), 2);
    expect(quarterOf(DateTime.utc(2026, 6, 30)), 2);
    expect(quarterOf(DateTime.utc(2026, 7, 1)), 3);
    expect(quarterOf(DateTime.utc(2026, 9, 30)), 3);
    expect(quarterOf(DateTime.utc(2026, 10, 1)), 4);
    expect(quarterOf(DateTime.utc(2026, 12, 31)), 4);
  });

  test('quarterBoundsFor returns (start, end, due) dates', () {
    final b = quarterBoundsFor(year: 2026, quarter: 2);
    expect(b.start, DateTime.utc(2026, 4, 1));
    expect(b.end, DateTime.utc(2026, 6, 30));
    expect(b.due, DateTime.utc(2026, 7, 15));
  });

  test('quarterNameFor produces the canonical period name', () {
    expect(quarterNameFor(year: 2026, quarter: 2), '2026 Q2');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/performance/quarter_math_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement quarter math**

Create `lib/features/performance/quarter_math.dart`:

```dart
/// Pure date math for quarterly + probationary review periods. No I/O.

class QuarterBounds {
  final DateTime start;
  final DateTime end;
  final DateTime due;
  const QuarterBounds({required this.start, required this.end, required this.due});
}

int quarterOf(DateTime d) => ((d.month - 1) ~/ 3) + 1;

/// Q1 = Jan 1 → Mar 31, due Apr 15.
/// Q2 = Apr 1 → Jun 30, due Jul 15.
/// Q3 = Jul 1 → Sep 30, due Oct 15.
/// Q4 = Oct 1 → Dec 31, due Jan 15 of next year.
QuarterBounds quarterBoundsFor({required int year, required int quarter}) {
  assert(quarter >= 1 && quarter <= 4, 'quarter must be 1..4');
  final startMonth = (quarter - 1) * 3 + 1;
  final start = DateTime.utc(year, startMonth, 1);
  // End-of-quarter month is startMonth + 2; last day = day before next month's 1st.
  final endMonthStart = DateTime.utc(year, startMonth + 3, 1);
  final end = endMonthStart.subtract(const Duration(days: 1));
  // Due 15 days after quarter end. Need to handle Q4 → Jan of next year.
  final dueRaw = DateTime.utc(end.year, end.month, end.day).add(const Duration(days: 15));
  return QuarterBounds(start: start, end: end, due: dueRaw);
}

String quarterNameFor({required int year, required int quarter}) =>
    '$year Q$quarter';

/// Add `months` calendar months to `d`, clamping the day to the target
/// month's last day if necessary. Used for probationary milestone dates.
DateTime addMonths(DateTime d, int months) {
  var year = d.year;
  var month = d.month + months;
  while (month > 12) {
    month -= 12;
    year += 1;
  }
  while (month < 1) {
    month += 12;
    year -= 1;
  }
  // Clamp day to last day of target month.
  final lastDayOfTarget = DateTime.utc(year, month + 1, 1).subtract(const Duration(days: 1)).day;
  final day = d.day > lastDayOfTarget ? lastDayOfTarget : d.day;
  return DateTime.utc(year, month, day);
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/features/performance/quarter_math_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Append `ensureQuarterlyPeriodForCurrentQuarter` to repo**

Inside the `PerformanceRepository` class (in `lib/data/repositories/performance_repository.dart`), append:

```dart
  /// Idempotent. Returns the period id for the current calendar quarter.
  /// If a row with the same (company_id, name, target_employee_id=null)
  /// already exists, returns its id without creating a duplicate.
  Future<String> ensureQuarterlyPeriodForCurrentQuarter({
    required String companyId,
    required DateTime now,
  }) async {
    final quarter = ((now.month - 1) ~/ 3) + 1;
    final startMonth = (quarter - 1) * 3 + 1;
    final start = DateTime.utc(now.year, startMonth, 1);
    final endMonthStart = DateTime.utc(now.year, startMonth + 3, 1);
    final end = endMonthStart.subtract(const Duration(days: 1));
    final due = end.add(const Duration(days: 15));
    final name = '${now.year} Q$quarter';

    final existing = await _client
        .from('check_in_periods')
        .select('id')
        .eq('company_id', companyId)
        .eq('name', name)
        .isFilter('target_employee_id', null)
        .maybeSingle();
    if (existing != null) {
      return (existing as Map<String, dynamic>)['id'] as String;
    }

    final iso = (DateTime d) => d.toIso8601String().substring(0, 10);
    final inserted = await _client
        .from('check_in_periods')
        .insert({
          'company_id': companyId,
          'name': name,
          'period_type': 'QUARTERLY',
          'start_date': iso(start),
          'end_date': iso(end),
          'due_date': iso(due),
          'is_active': true,
        })
        .select('id')
        .single();
    return (inserted as Map<String, dynamic>)['id'] as String;
  }
```

- [ ] **Step 6: Verify**

Run: `flutter analyze lib/data/repositories/performance_repository.dart lib/features/performance/quarter_math.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/performance/quarter_math.dart \
        test/features/performance/quarter_math_test.dart \
        lib/data/repositories/performance_repository.dart
git commit -m "feat(performance): quarter math + ensureQuarterlyPeriodForCurrentQuarter"
```

---

### Task 9: Probationary milestone math + `ensureProbationaryPeriodsForEmployee`

**Files:**
- Modify: `lib/features/performance/quarter_math.dart` (already has `addMonths`; verify present)
- Create: `test/features/performance/probation_milestones_test.dart`
- Modify: `lib/data/repositories/performance_repository.dart` (append method)

- [ ] **Step 1: Write the failing test for milestone calculation**

Create `test/features/performance/probation_milestones_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/performance/quarter_math.dart';

void main() {
  test('addMonths handles common cases', () {
    expect(addMonths(DateTime.utc(2026, 1, 1), 1), DateTime.utc(2026, 2, 1));
    expect(addMonths(DateTime.utc(2026, 1, 1), 3), DateTime.utc(2026, 4, 1));
    expect(addMonths(DateTime.utc(2026, 1, 1), 5), DateTime.utc(2026, 6, 1));
  });

  test('addMonths clamps day for end-of-month dates', () {
    // 2026-01-31 + 1 month = 2026-02-28 (clamped — Feb has 28 days).
    expect(addMonths(DateTime.utc(2026, 1, 31), 1), DateTime.utc(2026, 2, 28));
    // 2024 is a leap year — 2024-01-31 + 1 month = 2024-02-29.
    expect(addMonths(DateTime.utc(2024, 1, 31), 1), DateTime.utc(2024, 2, 29));
  });

  test('addMonths handles year rollover', () {
    expect(addMonths(DateTime.utc(2026, 11, 15), 3), DateTime.utc(2027, 2, 15));
  });
}
```

- [ ] **Step 2: Run to verify the existing `addMonths` is correct**

Run: `flutter test test/features/performance/probation_milestones_test.dart`
Expected: PASS (3 tests — `addMonths` already exists from Task 8).

- [ ] **Step 3: Append `ensureProbationaryPeriodsForEmployee` to repo**

Inside the `PerformanceRepository` class (in `lib/data/repositories/performance_repository.dart`), append:

```dart
  /// For each probationary milestone (1M / 3M / 5M from hire_date) that has
  /// passed (milestone date ≤ now), ensure a per-employee period exists.
  /// Returns the list of period ids (one per applicable milestone).
  ///
  /// Idempotent — uses the (company_id, name, target_employee_id) unique
  /// constraint to avoid duplicates.
  Future<List<String>> ensureProbationaryPeriodsForEmployee({
    required String companyId,
    required String employeeId,
    required String employeeFullName,
    required DateTime hireDate,
    required DateTime now,
  }) async {
    final ids = <String>[];
    const milestones = <(int months, String type, String label)>[
      (1, 'PROBATION_1M', '1M'),
      (3, 'PROBATION_3M', '3M'),
      (5, 'PROBATION_5M', '5M'),
    ];

    String iso(DateTime d) => d.toIso8601String().substring(0, 10);

    for (final (months, type, label) in milestones) {
      final milestoneDate = _addMonths(hireDate, months);
      if (milestoneDate.isAfter(now)) continue; // milestone not yet reached

      final name = 'Probation $label — $employeeFullName';

      final existing = await _client
          .from('check_in_periods')
          .select('id')
          .eq('company_id', companyId)
          .eq('name', name)
          .eq('target_employee_id', employeeId)
          .maybeSingle();
      if (existing != null) {
        ids.add((existing as Map<String, dynamic>)['id'] as String);
        continue;
      }

      // Window: opens 14 days before milestone, ends at milestone,
      // due 7 days after.
      final start = milestoneDate.subtract(const Duration(days: 14));
      final end = milestoneDate;
      final due = milestoneDate.add(const Duration(days: 7));

      final inserted = await _client
          .from('check_in_periods')
          .insert({
            'company_id': companyId,
            'name': name,
            'period_type': type,
            'start_date': iso(start),
            'end_date': iso(end),
            'due_date': iso(due),
            'is_active': true,
            'target_employee_id': employeeId,
          })
          .select('id')
          .single();
      ids.add((inserted as Map<String, dynamic>)['id'] as String);
    }
    return ids;
  }

  /// Private clone of the pure helper so this file doesn't depend on the
  /// features layer (model files are in lib/data/, repositories should not
  /// depend on lib/features/). Inlined intentionally.
  DateTime _addMonths(DateTime d, int months) {
    var year = d.year;
    var month = d.month + months;
    while (month > 12) {
      month -= 12;
      year += 1;
    }
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    final lastDayOfTarget =
        DateTime.utc(year, month + 1, 1).subtract(const Duration(days: 1)).day;
    final day = d.day > lastDayOfTarget ? lastDayOfTarget : d.day;
    return DateTime.utc(year, month, day);
  }
```

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/data/repositories/performance_repository.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/performance_repository.dart \
        test/features/performance/probation_milestones_test.dart
git commit -m "feat(performance): ensureProbationaryPeriodsForEmployee (1M/3M/5M)"
```

---

## Phase 6 — Check-in auto-gen + skill seeding

### Task 10: `ensureCheckInForEmployeeInPeriod` (idempotent insert)

**Files:**
- Modify: `lib/data/repositories/performance_repository.dart` (append method)

- [ ] **Step 1: Append method**

Inside the `PerformanceRepository` class, append:

```dart
  /// Idempotent. Returns the check-in id for (period, employee). Inserts a
  /// new DRAFT row if none exists, defaulting `reviewer_id` to the employee's
  /// manager (if provided). Does NOT seed skill_ratings — call
  /// `seedSkillRatingsForCheckIn` separately.
  Future<String> ensureCheckInForEmployeeInPeriod({
    required String periodId,
    required String employeeId,
    String? reviewerId,
  }) async {
    final existing = await _client
        .from('performance_check_ins')
        .select('id')
        .eq('period_id', periodId)
        .eq('employee_id', employeeId)
        .maybeSingle();
    if (existing != null) {
      return (existing as Map<String, dynamic>)['id'] as String;
    }
    final inserted = await _client
        .from('performance_check_ins')
        .insert({
          'period_id': periodId,
          'employee_id': employeeId,
          'reviewer_id': reviewerId,
          'status': 'DRAFT',
        })
        .select('id')
        .single();
    return (inserted as Map<String, dynamic>)['id'] as String;
  }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/data/repositories/performance_repository.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/performance_repository.dart
git commit -m "feat(performance): ensureCheckInForEmployeeInPeriod (idempotent)"
```

---

### Task 11: `seedSkillRatingsForCheckIn` (from RoleScorecard.kpis)

**Files:**
- Modify: `lib/data/repositories/performance_repository.dart` (append method)

- [ ] **Step 1: Append method**

Inside the `PerformanceRepository` class, append:

```dart
  /// Auto-seed skill_ratings from the employee's RoleScorecard KPIs. Reads
  /// the scorecard's `kpis` jsonb array; each KPI.metric becomes a skill_name
  /// row with skill_category='KPI'. Idempotent via the (check_in_id,
  /// skill_category, skill_name) unique constraint — already-seeded rows
  /// stay untouched.
  ///
  /// Snapshotted at this moment: subsequent KPI edits do NOT propagate to
  /// existing check-ins. This is intentional (historical record stability).
  Future<void> seedSkillRatingsForCheckIn({
    required String checkInId,
    required String? roleScorecardId,
  }) async {
    if (roleScorecardId == null) return;
    final scorecard = await _client
        .from('role_scorecards')
        .select('kpis')
        .eq('id', roleScorecardId)
        .maybeSingle();
    if (scorecard == null) return;
    final rawKpis = (scorecard as Map<String, dynamic>)['kpis'];
    if (rawKpis is! List) return;

    // Read existing skill_names to avoid PK violations on the unique constraint.
    final existing = await _client
        .from('skill_ratings')
        .select('skill_name')
        .eq('check_in_id', checkInId)
        .eq('skill_category', 'KPI');
    final existingNames = <String>{
      for (final r in (existing as List))
        ((r as Map<String, dynamic>)['skill_name'] as String?) ?? '',
    };

    final toInsert = <Map<String, dynamic>>[];
    for (final k in rawKpis) {
      if (k is! Map) continue;
      final metric = k['metric'] as String?;
      if (metric == null || metric.isEmpty) continue;
      if (existingNames.contains(metric)) continue;
      toInsert.add({
        'check_in_id': checkInId,
        'skill_category': 'KPI',
        'skill_name': metric,
      });
    }
    if (toInsert.isNotEmpty) {
      await _client.from('skill_ratings').insert(toInsert);
    }
  }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/data/repositories/performance_repository.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/performance_repository.dart
git commit -m "feat(performance): seedSkillRatingsForCheckIn from RoleScorecard.kpis"
```

---

## Phase 7 — Status transitions

### Task 12: Status transition matrix (pure function)

**Files:**
- Create: `lib/features/performance/check_in_status.dart`
- Create: `test/features/performance/check_in_status_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/performance/check_in_status_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/performance/check_in_status.dart';

void main() {
  test('legal transitions are accepted', () {
    expect(canCheckInTransition(from: 'DRAFT', to: 'SUBMITTED'), isTrue);
    expect(canCheckInTransition(from: 'SUBMITTED', to: 'UNDER_REVIEW'), isTrue);
    expect(canCheckInTransition(from: 'UNDER_REVIEW', to: 'COMPLETED'), isTrue);
  });
  test('SKIPPED is reachable from any non-terminal state', () {
    expect(canCheckInTransition(from: 'DRAFT', to: 'SKIPPED'), isTrue);
    expect(canCheckInTransition(from: 'SUBMITTED', to: 'SKIPPED'), isTrue);
    expect(canCheckInTransition(from: 'UNDER_REVIEW', to: 'SKIPPED'), isTrue);
  });
  test('terminal states cannot transition', () {
    expect(canCheckInTransition(from: 'COMPLETED', to: 'DRAFT'), isFalse);
    expect(canCheckInTransition(from: 'SKIPPED', to: 'DRAFT'), isFalse);
  });
  test('illegal jumps are blocked', () {
    expect(canCheckInTransition(from: 'DRAFT', to: 'COMPLETED'), isFalse);
    expect(canCheckInTransition(from: 'DRAFT', to: 'UNDER_REVIEW'), isFalse);
  });
  test('validateCheckInTransition throws on illegal jump', () {
    expect(
      () => validateCheckInTransition(from: 'DRAFT', to: 'COMPLETED'),
      throwsA(isA<IllegalCheckInTransition>()),
    );
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/performance/check_in_status_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

Create `lib/features/performance/check_in_status.dart`:

```dart
/// Allowed status transitions for performance check-ins.
const Map<String, Set<String>> kCheckInTransitions = {
  'DRAFT':        {'SUBMITTED', 'SKIPPED'},
  'SUBMITTED':    {'UNDER_REVIEW', 'SKIPPED'},
  'UNDER_REVIEW': {'COMPLETED', 'SKIPPED'},
  'COMPLETED':    <String>{},
  'SKIPPED':      <String>{},
};

bool canCheckInTransition({required String from, required String to}) =>
    (kCheckInTransitions[from] ?? const <String>{}).contains(to);

class IllegalCheckInTransition implements Exception {
  final String from;
  final String to;
  IllegalCheckInTransition(this.from, this.to);
  @override
  String toString() => 'Illegal check-in status transition: $from → $to';
}

void validateCheckInTransition({required String from, required String to}) {
  if (from == to) return;
  if (!canCheckInTransition(from: from, to: to)) {
    throw IllegalCheckInTransition(from, to);
  }
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/features/performance/check_in_status_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/performance/check_in_status.dart \
        test/features/performance/check_in_status_test.dart
git commit -m "feat(performance): pure-Dart check-in status transition matrix"
```

---

## Phase 8 — Mutation methods

### Task 13: `updateCheckIn` + goal/skill CRUD

**Files:**
- Modify: `lib/data/repositories/performance_repository.dart` (append methods)

- [ ] **Step 1: Append mutation methods**

Inside the `PerformanceRepository` class, append:

```dart
  /// Partial update of check-in fields. When `status` is set and differs from
  /// the prior value, validates the transition and stamps submitted_at /
  /// reviewed_at as appropriate.
  Future<void> updateCheckIn({
    required String checkInId,
    String? status,
    String? accomplishments,
    String? challenges,
    String? learnings,
    String? supportNeeded,
    String? managerFeedback,
    String? strengths,
    String? areasForImprovement,
    int? overallRating,
    String? overallComments,
  }) async {
    final payload = <String, dynamic>{
      if (accomplishments != null) 'accomplishments': accomplishments,
      if (challenges != null) 'challenges': challenges,
      if (learnings != null) 'learnings': learnings,
      if (supportNeeded != null) 'support_needed': supportNeeded,
      if (managerFeedback != null) 'manager_feedback': managerFeedback,
      if (strengths != null) 'strengths': strengths,
      if (areasForImprovement != null) 'areas_for_improvement': areasForImprovement,
      if (overallRating != null) 'overall_rating': overallRating,
      if (overallComments != null) 'overall_comments': overallComments,
    };

    if (status != null) {
      final prior = await _client
          .from('performance_check_ins')
          .select('status')
          .eq('id', checkInId)
          .maybeSingle();
      final priorStatus = (prior as Map<String, dynamic>?)?['status'] as String?;
      if (priorStatus != null && priorStatus != status) {
        // imports validation from features/performance/check_in_status.dart
        validateCheckInTransition(from: priorStatus, to: status);
      }
      payload['status'] = status;
      final now = DateTime.now().toIso8601String();
      if (status == 'SUBMITTED') payload['submitted_at'] = now;
      if (status == 'COMPLETED') payload['reviewed_at'] = now;
    }

    if (payload.isEmpty) return;
    await _client.from('performance_check_ins').update(payload).eq('id', checkInId);
  }

  Future<String> addGoal({
    required String checkInId,
    required String goalType,
    required String title,
    String? description,
    DateTime? targetDate,
  }) async {
    final iso = targetDate?.toIso8601String().substring(0, 10);
    final row = await _client
        .from('check_in_goals')
        .insert({
          'check_in_id': checkInId,
          'goal_type': goalType,
          'title': title,
          'description': description,
          'target_date': iso,
          'progress': 0,
          'status': 'IN_PROGRESS',
          'carry_forward': false,
        })
        .select('id')
        .single();
    return (row as Map<String, dynamic>)['id'] as String;
  }

  Future<void> updateGoal({
    required String goalId,
    String? title,
    String? description,
    DateTime? targetDate,
    int? progress,
    String? status,
    String? selfAssessment,
    String? managerAssessment,
    int? rating,
    bool? carryForward,
  }) async {
    final payload = <String, dynamic>{
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (targetDate != null) 'target_date': targetDate.toIso8601String().substring(0, 10),
      if (progress != null) 'progress': progress,
      if (status != null) 'status': status,
      if (selfAssessment != null) 'self_assessment': selfAssessment,
      if (managerAssessment != null) 'manager_assessment': managerAssessment,
      if (rating != null) 'rating': rating,
      if (carryForward != null) 'carry_forward': carryForward,
    };
    if (payload.isEmpty) return;
    await _client.from('check_in_goals').update(payload).eq('id', goalId);
  }

  Future<void> deleteGoal(String goalId) async {
    await _client.from('check_in_goals').delete().eq('id', goalId);
  }

  Future<String> addSkill({
    required String checkInId,
    required String skillCategory,
    required String skillName,
  }) async {
    final row = await _client
        .from('skill_ratings')
        .insert({
          'check_in_id': checkInId,
          'skill_category': skillCategory,
          'skill_name': skillName,
        })
        .select('id')
        .single();
    return (row as Map<String, dynamic>)['id'] as String;
  }

  Future<void> updateSkill({
    required String skillId,
    int? selfRating,
    int? managerRating,
    String? comments,
    String? developmentPlan,
  }) async {
    final payload = <String, dynamic>{
      if (selfRating != null) 'self_rating': selfRating,
      if (managerRating != null) 'manager_rating': managerRating,
      if (comments != null) 'comments': comments,
      if (developmentPlan != null) 'development_plan': developmentPlan,
    };
    if (payload.isEmpty) return;
    await _client.from('skill_ratings').update(payload).eq('id', skillId);
  }

  Future<void> deleteSkill(String skillId) async {
    await _client.from('skill_ratings').delete().eq('id', skillId);
  }
```

Add the import at the TOP of `performance_repository.dart`:

```dart
import '../../features/performance/check_in_status.dart';
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/data/repositories/performance_repository.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/performance_repository.dart
git commit -m "feat(performance): updateCheckIn + goal/skill CRUD methods"
```

---

## Phase 9 — List screen

### Task 14: Replace stub + unhide nav + permission gate + scaffold

**Files:**
- Modify: `lib/features/performance/performance_screen.dart` (full rewrite — currently a ComingSoonScreen stub)
- Modify: `lib/app/shell.dart` (remove `comingSoon: true` from Performance nav line around line 105)

- [ ] **Step 1: Replace the screen**

Overwrite `lib/features/performance/performance_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../auth/profile_provider.dart';

class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (profile == null) {
      return Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(title: const Text('Performance')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // HR/Admin see all; employees see their own (via RLS + a query filter we'll add in Task 15).
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Performance')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Performance list lands in Task 15.')),
      ),
    );
  }
}
```

- [ ] **Step 2: Unhide nav**

In `lib/app/shell.dart`, find the Performance nav line (around line 105). It reads:

```dart
    _NavItem('Performance', Icons.stacked_line_chart_outlined, '/performance',
        _always,
        comingSoon: true),
```

Replace with:

```dart
    _NavItem('Performance', Icons.stacked_line_chart_outlined, '/performance', _always),
```

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/performance/ lib/app/shell.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/performance/performance_screen.dart lib/app/shell.dart
git commit -m "feat(performance): unhide nav + permission-gated scaffold (list placeholder)"
```

---

### Task 15: List card + filter bar + auto-gen on mount

**Files:**
- Modify: `lib/features/performance/performance_screen.dart`
- Create: `lib/features/performance/auto_generate.dart`

- [ ] **Step 1: Create the auto-gen orchestrator**

Create `lib/features/performance/auto_generate.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';

/// Lazy auto-generation: ensures the current quarter's company-wide period
/// exists, then for each active employee ensures the right check-ins exist
/// (quarterly for REGULAR, 1M/3M/5M for PROBATIONARY), with skill_ratings
/// auto-seeded from the employee's RoleScorecard KPIs.
///
/// Called once when /performance is opened. Idempotent at every step.
Future<void> autoGeneratePerformanceForCurrentQuarter(WidgetRef ref) async {
  final profile = await ref.read(userProfileProvider.future);
  if (profile == null || profile.companyId == null) return;
  final repo = ref.read(performanceRepositoryProvider);
  final now = DateTime.now().toUtc();

  // 1. Quarterly company-wide period (for REGULAR employees).
  final quarterlyPeriodId = await repo.ensureQuarterlyPeriodForCurrentQuarter(
    companyId: profile.companyId!,
    now: now,
  );

  // 2. For each active employee, ensure the right check-ins exist.
  final employees = await ref.read(
      employeeListProvider(const EmployeeListQuery()).future);
  for (final emp in employees) {
    if (emp.employmentStatus != 'ACTIVE') continue;
    final reviewerId = emp.reportsToId;

    if (emp.employmentType == 'REGULAR') {
      final checkInId = await repo.ensureCheckInForEmployeeInPeriod(
        periodId: quarterlyPeriodId,
        employeeId: emp.id,
        reviewerId: reviewerId,
      );
      await repo.seedSkillRatingsForCheckIn(
        checkInId: checkInId,
        roleScorecardId: emp.roleScorecardId,
      );
    } else if (emp.employmentType == 'PROBATIONARY') {
      final periodIds = await repo.ensureProbationaryPeriodsForEmployee(
        companyId: profile.companyId!,
        employeeId: emp.id,
        employeeFullName: emp.fullName,
        hireDate: emp.hireDate,
        now: now,
      );
      for (final pid in periodIds) {
        final checkInId = await repo.ensureCheckInForEmployeeInPeriod(
          periodId: pid,
          employeeId: emp.id,
          reviewerId: reviewerId,
        );
        await repo.seedSkillRatingsForCheckIn(
          checkInId: checkInId,
          roleScorecardId: emp.roleScorecardId,
        );
      }
    }
    // Other employmentTypes (CONTRACTUAL/CONSULTANT/INTERN/SEASONAL/CASUAL)
    // are out of scope in v1.
  }
}
```

- [ ] **Step 2: Replace `PerformanceScreen` with the real list**

Overwrite `lib/features/performance/performance_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/models/performance_check_in.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';
import 'auto_generate.dart';

class PerformanceScreen extends ConsumerStatefulWidget {
  const PerformanceScreen({super.key});
  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  // Default: hide COMPLETED to keep the inbox focused on actionable check-ins.
  List<String> _statuses = const ['DRAFT', 'SUBMITTED', 'UNDER_REVIEW'];
  bool _autoGenStarted = false;

  @override
  void initState() {
    super.initState();
    // Kick off auto-gen once on first build. Errors land in the snackbar.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_autoGenStarted) return;
      _autoGenStarted = true;
      try {
        await autoGeneratePerformanceForCurrentQuarter(ref);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Performance auto-gen failed: $e')),
        );
      }
      if (mounted) {
        ref.invalidate(performanceCheckInListProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (profile == null) {
      return Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(title: const Text('Performance')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Performance')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(
            statuses: _statuses,
            onStatusesChanged: (s) => setState(() => _statuses = s),
          ),
          Expanded(
            child: _CheckInsTable(
              statuses: _statuses,
              // Non-HR users see only their own check-ins.
              employeeId: profile.isHrOrAdmin ? null : profile.employeeId,
            ),
          ),
        ],
      ),
    );
  }
}

const _kAllStatuses = <String>[
  'DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'COMPLETED', 'SKIPPED',
];

class _FilterBar extends StatelessWidget {
  final List<String> statuses;
  final ValueChanged<List<String>> onStatusesChanged;
  const _FilterBar({required this.statuses, required this.onStatusesChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in _kAllStatuses)
            FilterChip(
              label: Text(s),
              selected: statuses.contains(s),
              onSelected: (v) {
                final next = [...statuses];
                if (v) {
                  next.add(s);
                } else {
                  next.remove(s);
                }
                onStatusesChanged(next);
              },
            ),
        ],
      ),
    );
  }
}

class _CheckInsTable extends ConsumerWidget {
  final List<String> statuses;
  final String? employeeId;
  const _CheckInsTable({required this.statuses, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = PerformanceListQuery(
      statuses: statuses.isEmpty ? null : statuses,
      employeeId: employeeId,
    );
    final async = ref.watch(performanceCheckInListProvider(q));
    final employees = ref.watch(
            employeeListProvider(const EmployeeListQuery(includeArchived: true)))
        .asData
        ?.value ?? const [];
    final empNameById = {for (final e in employees) e.id: e.fullName};
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No check-ins match the current filters.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final c = rows[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(empNameById[c.employeeId] ?? '(unknown employee)'),
                subtitle: Text(
                  c.status,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                trailing: Text(
                  c.createdAt.toIso8601String().substring(0, 10),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => context.go('/performance/${c.id}'),
              ),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/performance/`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/performance/performance_screen.dart lib/features/performance/auto_generate.dart
git commit -m "feat(performance): list table + filter bar + auto-gen on mount"
```

---

## Phase 10 — Detail screen scaffold

### Task 16: `PerformanceCheckInScreen` scaffold + route + header

**Files:**
- Create: `lib/features/performance/performance_check_in_screen.dart`
- Modify: `lib/app/router.dart` (add `/performance/:id` route + import)

- [ ] **Step 1: Create the detail screen**

Create `lib/features/performance/performance_check_in_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/performance_check_in.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/performance_repository.dart';
import '../auth/profile_provider.dart';

class PerformanceCheckInScreen extends ConsumerWidget {
  final String checkInId;
  const PerformanceCheckInScreen({super.key, required this.checkInId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final async = ref.watch(performanceCheckInByIdProvider(checkInId));
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check-in')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Check-in')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Check-in')),
        body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      ),
      data: (c) {
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Check-in')),
            body: const Center(child: Text('Check-in not found.')),
          );
        }
        // Permission check: HR/Admin sees all; otherwise only own check-in.
        final isSelf = profile.employeeId == c.employeeId;
        if (!profile.isHrOrAdmin && !isSelf) {
          return Scaffold(
            appBar: AppBar(title: const Text('Check-in')),
            body: const Center(child: Text('You do not have permission to view this check-in.')),
          );
        }
        return _Body(c: c);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final PerformanceCheckIn c;
  const _Body({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeByIdProvider(c.employeeId)).asData?.value;
    final period = ref.watch(checkInPeriodByIdProvider(c.periodId)).asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(employee?.fullName ?? 'Check-in'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/performance'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (period != null) Chip(label: Text(period.periodType)),
              const SizedBox(width: 8),
              Chip(label: Text(c.status)),
              const SizedBox(width: 12),
              if (period != null)
                Text(period.name, style: const TextStyle(fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            Text(
              'Created ${c.createdAt.toIso8601String().substring(0, 10)}'
              '${c.submittedAt != null ? '  ·  Submitted ${c.submittedAt!.toIso8601String().substring(0, 10)}' : ''}'
              '${c.reviewedAt != null ? '  ·  Reviewed ${c.reviewedAt!.toIso8601String().substring(0, 10)}' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Sections land in Tasks 17–21.
            const Text('Self-review, Goals, Skill Ratings, Manager Review, and Status Actions land in Tasks 17–21.'),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Add the route**

In `lib/app/router.dart`, find the existing `/performance` route (around line 157). After it, add:

```dart
          GoRoute(
            path: '/performance/:id',
            builder: (c, s) => PerformanceCheckInScreen(checkInId: s.pathParameters['id']!),
          ),
```

Add the import at the top:

```dart
import '../features/performance/performance_check_in_screen.dart';
```

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/performance/ lib/app/router.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/performance/performance_check_in_screen.dart lib/app/router.dart
git commit -m "feat(performance): check-in detail scaffold + /performance/:id route"
```

---

## Phase 11 — Self-review section

### Task 17: Self-review fields (accomplishments / challenges / learnings / support_needed)

**Files:**
- Modify: `lib/features/performance/performance_check_in_screen.dart`

- [ ] **Step 1: Add self-review section**

In `_Body.build`, find the placeholder `const Text('Self-review, Goals, ...')` line and REPLACE with:

```dart
            _SelfReviewSection(c: c),
            const SizedBox(height: 24),
            // Goals + Skill Ratings + Manager Review + Status Actions land in Tasks 18–21.
            const Text('Goals, Skill Ratings, Manager Review, and Status Actions land in Tasks 18–21.'),
```

Add the `_SelfReviewSection` widget at the BOTTOM of the file:

```dart
class _SelfReviewSection extends ConsumerStatefulWidget {
  final PerformanceCheckIn c;
  const _SelfReviewSection({required this.c});
  @override
  ConsumerState<_SelfReviewSection> createState() => _SelfReviewSectionState();
}

class _SelfReviewSectionState extends ConsumerState<_SelfReviewSection> {
  late final TextEditingController _accomplishments;
  late final TextEditingController _challenges;
  late final TextEditingController _learnings;
  late final TextEditingController _supportNeeded;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accomplishments = TextEditingController(text: widget.c.accomplishments ?? '');
    _challenges = TextEditingController(text: widget.c.challenges ?? '');
    _learnings = TextEditingController(text: widget.c.learnings ?? '');
    _supportNeeded = TextEditingController(text: widget.c.supportNeeded ?? '');
  }

  @override
  void dispose() {
    _accomplishments.dispose();
    _challenges.dispose();
    _learnings.dispose();
    _supportNeeded.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(performanceRepositoryProvider).updateCheckIn(
            checkInId: widget.c.id,
            accomplishments: _accomplishments.text,
            challenges: _challenges.text,
            learnings: _learnings.text,
            supportNeeded: _supportNeeded.text,
          );
      ref.invalidate(performanceCheckInByIdProvider(widget.c.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Self-review saved.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Self-review fields are read-only once the check-in is past DRAFT.
    final readOnly = widget.c.status != 'DRAFT';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Self-review',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 12),
            TextField(
              controller: _accomplishments,
              readOnly: readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Accomplishments',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _challenges,
              readOnly: readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Challenges',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _learnings,
              readOnly: readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Learnings',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supportNeeded,
              readOnly: readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Support needed',
                border: OutlineInputBorder(),
              ),
            ),
            if (!readOnly) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save self-review'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/performance/performance_check_in_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/performance/performance_check_in_screen.dart
git commit -m "feat(performance): self-review section (accomplishments/challenges/learnings/support)"
```

---

## Phase 12 — Goals section

### Task 18: Goals editor (list + inline form + add/delete)

**Files:**
- Modify: `lib/features/performance/performance_check_in_screen.dart`

- [ ] **Step 1: Add goals section**

In `_Body.build`, find the placeholder text "Goals, Skill Ratings, Manager Review, and Status Actions land in Tasks 18–21." and REPLACE with:

```dart
            _GoalsSection(c: c),
            const SizedBox(height: 24),
            // Skill Ratings + Manager Review + Status Actions land in Tasks 19–21.
            const Text('Skill Ratings, Manager Review, and Status Actions land in Tasks 19–21.'),
```

Append `_GoalsSection` at the BOTTOM of the file:

```dart
class _GoalsSection extends ConsumerWidget {
  final PerformanceCheckIn c;
  const _GoalsSection({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(checkInGoalsProvider(c.id));
    final profile = ref.watch(userProfileProvider).asData!.value!;
    final canEditAll = profile.isHrOrAdmin || profile.userId == c.reviewerId;
    final canEditSelf = profile.employeeId == c.employeeId && c.status == 'DRAFT';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Goals',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const Spacer(),
              if (canEditAll || canEditSelf)
                TextButton.icon(
                  onPressed: () => _addGoal(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add goal'),
                ),
            ]),
            const SizedBox(height: 12),
            goals.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Text('No goals set yet.');
                }
                return Column(
                  children: [
                    for (final g in rows)
                      _GoalRow(
                        goal: g,
                        canEditAll: canEditAll,
                        canEditSelf: canEditSelf,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addGoal(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add goal'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Goal title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (ctl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(ctl.text.trim());
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (title == null) return;
      await ref.read(performanceRepositoryProvider).addGoal(
            checkInId: c.id,
            goalType: 'PERFORMANCE',
            title: title,
          );
      ref.invalidate(checkInGoalsProvider(c.id));
    } finally {
      ctl.dispose();
    }
  }
}

class _GoalRow extends ConsumerStatefulWidget {
  final dynamic goal;  // CheckInGoal — kept dynamic to avoid a top-level import; cast in build
  final bool canEditAll;
  final bool canEditSelf;
  const _GoalRow({required this.goal, required this.canEditAll, required this.canEditSelf});
  @override
  ConsumerState<_GoalRow> createState() => _GoalRowState();
}

class _GoalRowState extends ConsumerState<_GoalRow> {
  @override
  Widget build(BuildContext context) {
    final g = widget.goal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(g.title as String,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                Chip(label: Text(g.goalType as String)),
                const SizedBox(width: 8),
                Chip(label: Text(g.status as String)),
                if (widget.canEditAll)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete goal',
                    onPressed: () => _delete(context),
                  ),
              ]),
              const SizedBox(height: 8),
              Text('Progress: ${g.progress}%',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (g.description != null && (g.description as String).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(g.description as String,
                    style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this goal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(performanceRepositoryProvider).deleteGoal(widget.goal.id as String);
    ref.invalidate(checkInGoalsProvider(widget.goal.checkInId as String));
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/performance/performance_check_in_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/performance/performance_check_in_screen.dart
git commit -m "feat(performance): goals section (list + add + delete)"
```

---

## Phase 13 — Skill ratings section

### Task 19: Skill ratings editor

**Files:**
- Modify: `lib/features/performance/performance_check_in_screen.dart`

- [ ] **Step 1: Add skills section**

In `_Body.build`, find "Skill Ratings, Manager Review, and Status Actions land in Tasks 19–21." and REPLACE with:

```dart
            _SkillsSection(c: c),
            const SizedBox(height: 24),
            // Manager Review + Status Actions land in Tasks 20–21.
            const Text('Manager Review and Status Actions land in Tasks 20–21.'),
```

Append `_SkillsSection` at the BOTTOM of the file:

```dart
class _SkillsSection extends ConsumerWidget {
  final PerformanceCheckIn c;
  const _SkillsSection({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(skillRatingsProvider(c.id));
    final profile = ref.watch(userProfileProvider).asData!.value!;
    final isSelf = profile.employeeId == c.employeeId;
    final isReviewer = profile.userId == c.reviewerId;
    final canManage = profile.isHrOrAdmin || isReviewer;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Skill Ratings',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const Spacer(),
              if (canManage)
                TextButton.icon(
                  onPressed: () => _addSkill(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add skill'),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              'KPI skills auto-seeded from the role scorecard at check-in creation. '
              'HR can add ad-hoc competencies (behavioral, technical, etc.).',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            skills.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red))
              ,
              data: (rows) {
                if (rows.isEmpty) {
                  return const Text('No skills tracked yet.');
                }
                return Column(
                  children: [
                    for (final s in rows)
                      _SkillRow(
                        skill: s,
                        canEditSelf: isSelf && c.status == 'DRAFT',
                        canEditManager: canManage && c.status != 'COMPLETED' && c.status != 'SKIPPED',
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSkill(BuildContext context, WidgetRef ref) async {
    final nameCtl = TextEditingController();
    final categoryCtl = TextEditingController(text: 'BEHAVIORAL');
    try {
      final result = await showDialog<({String category, String name})>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add skill'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: categoryCtl,
                decoration: const InputDecoration(labelText: 'Category (e.g. BEHAVIORAL, TECHNICAL)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Skill name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtl.text.trim();
                final cat = categoryCtl.text.trim();
                if (name.isEmpty || cat.isEmpty) return;
                Navigator.of(ctx).pop((category: cat, name: name));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (result == null) return;
      await ref.read(performanceRepositoryProvider).addSkill(
            checkInId: c.id,
            skillCategory: result.category,
            skillName: result.name,
          );
      ref.invalidate(skillRatingsProvider(c.id));
    } finally {
      nameCtl.dispose();
      categoryCtl.dispose();
    }
  }
}

class _SkillRow extends ConsumerStatefulWidget {
  final dynamic skill;  // SkillRating
  final bool canEditSelf;
  final bool canEditManager;
  const _SkillRow({
    required this.skill,
    required this.canEditSelf,
    required this.canEditManager,
  });
  @override
  ConsumerState<_SkillRow> createState() => _SkillRowState();
}

class _SkillRowState extends ConsumerState<_SkillRow> {
  @override
  Widget build(BuildContext context) {
    final s = widget.skill;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Chip(label: Text(s.skillCategory as String)),
                const SizedBox(width: 8),
                Expanded(child: Text(s.skillName as String,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                if (widget.canEditManager && (s.skillCategory as String) != 'KPI')
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Remove skill',
                    onPressed: () => _delete(context),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _RatingPicker(
                    label: 'Self',
                    value: s.selfRating as int?,
                    enabled: widget.canEditSelf,
                    onChanged: (v) => _update(selfRating: v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RatingPicker(
                    label: 'Manager',
                    value: s.managerRating as int?,
                    enabled: widget.canEditManager,
                    onChanged: (v) => _update(managerRating: v),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _update({int? selfRating, int? managerRating}) async {
    await ref.read(performanceRepositoryProvider).updateSkill(
          skillId: widget.skill.id as String,
          selfRating: selfRating,
          managerRating: managerRating,
        );
    ref.invalidate(skillRatingsProvider(widget.skill.checkInId as String));
  }

  Future<void> _delete(BuildContext context) async {
    await ref.read(performanceRepositoryProvider).deleteSkill(widget.skill.id as String);
    ref.invalidate(skillRatingsProvider(widget.skill.checkInId as String));
  }
}

class _RatingPicker extends StatelessWidget {
  final String label;
  final int? value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const _RatingPicker({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Row(children: [
          for (var i = 1; i <= 5; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text('$i'),
                selected: value == i,
                onSelected: enabled ? (_) => onChanged(i) : null,
              ),
            ),
        ]),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/performance/performance_check_in_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/performance/performance_check_in_screen.dart
git commit -m "feat(performance): skill ratings section (auto-seeded + add + 1-5 rating chips)"
```

---

## Phase 14 — Manager review section

### Task 20: Manager review fields

**Files:**
- Modify: `lib/features/performance/performance_check_in_screen.dart`

- [ ] **Step 1: Add manager review section**

In `_Body.build`, find "Manager Review and Status Actions land in Tasks 20–21." and REPLACE with:

```dart
            _ManagerReviewSection(c: c),
            const SizedBox(height: 24),
            // Status Actions land in Task 21.
            const Text('Status Actions land in Task 21.'),
```

Append `_ManagerReviewSection` at the BOTTOM of the file:

```dart
class _ManagerReviewSection extends ConsumerStatefulWidget {
  final PerformanceCheckIn c;
  const _ManagerReviewSection({required this.c});
  @override
  ConsumerState<_ManagerReviewSection> createState() => _ManagerReviewSectionState();
}

class _ManagerReviewSectionState extends ConsumerState<_ManagerReviewSection> {
  late final TextEditingController _feedback;
  late final TextEditingController _strengths;
  late final TextEditingController _areas;
  late final TextEditingController _overallComments;
  int? _overallRating;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _feedback = TextEditingController(text: widget.c.managerFeedback ?? '');
    _strengths = TextEditingController(text: widget.c.strengths ?? '');
    _areas = TextEditingController(text: widget.c.areasForImprovement ?? '');
    _overallComments = TextEditingController(text: widget.c.overallComments ?? '');
    _overallRating = widget.c.overallRating;
  }

  @override
  void dispose() {
    _feedback.dispose();
    _strengths.dispose();
    _areas.dispose();
    _overallComments.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(performanceRepositoryProvider).updateCheckIn(
            checkInId: widget.c.id,
            managerFeedback: _feedback.text,
            strengths: _strengths.text,
            areasForImprovement: _areas.text,
            overallRating: _overallRating,
            overallComments: _overallComments.text,
          );
      ref.invalidate(performanceCheckInByIdProvider(widget.c.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manager review saved.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData!.value!;
    final isReviewer = profile.userId == widget.c.reviewerId;
    final canEdit = (profile.isHrOrAdmin || isReviewer) &&
        widget.c.status != 'COMPLETED' && widget.c.status != 'SKIPPED' &&
        widget.c.status != 'DRAFT';  // self-review must complete first
    final isCompleted = widget.c.status == 'COMPLETED';
    // Hide manager review entirely from the employee until COMPLETED.
    final isSelf = profile.employeeId == widget.c.employeeId;
    if (isSelf && !isCompleted) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Manager Review',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 12),
            TextField(
              controller: _feedback,
              readOnly: !canEdit,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Manager feedback',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _strengths,
              readOnly: !canEdit,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Strengths',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _areas,
              readOnly: !canEdit,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Areas for improvement',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Overall rating',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Row(children: [
              for (var i = 1; i <= 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text('$i'),
                    selected: _overallRating == i,
                    onSelected: canEdit ? (_) => setState(() => _overallRating = i) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _overallComments,
              readOnly: !canEdit,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Overall comments',
                border: OutlineInputBorder(),
              ),
            ),
            if (canEdit) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save manager review'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/performance/performance_check_in_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/performance/performance_check_in_screen.dart
git commit -m "feat(performance): manager review section (feedback/strengths/areas/overall)"
```

---

## Phase 15 — Status actions

### Task 21: Status actions footer (Submit / Start review / Complete / Skip)

**Files:**
- Modify: `lib/features/performance/performance_check_in_screen.dart`

- [ ] **Step 1: Add status actions**

In `_Body.build`, find "Status Actions land in Task 21." and REPLACE with:

```dart
            _StatusActions(c: c),
```

Append `_StatusActions` at the BOTTOM of the file:

```dart
class _StatusActions extends ConsumerWidget {
  final PerformanceCheckIn c;
  const _StatusActions({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData!.value!;
    final isSelf = profile.employeeId == c.employeeId;
    final isReviewer = profile.userId == c.reviewerId;
    final canManage = profile.isHrOrAdmin || isReviewer;

    final buttons = <Widget>[];
    if (c.status == 'DRAFT' && (isSelf || profile.isHrOrAdmin)) {
      buttons.add(FilledButton(
        onPressed: () => _transition(context, ref, 'SUBMITTED'),
        child: const Text('Submit for review'),
      ));
    }
    if (c.status == 'SUBMITTED' && canManage) {
      buttons.add(FilledButton.tonal(
        onPressed: () => _transition(context, ref, 'UNDER_REVIEW'),
        child: const Text('Start review'),
      ));
    }
    if (c.status == 'UNDER_REVIEW' && canManage) {
      buttons.add(FilledButton(
        onPressed: () => _transition(context, ref, 'COMPLETED'),
        child: const Text('Mark complete'),
      ));
    }
    if (profile.isHrOrAdmin && c.status != 'COMPLETED' && c.status != 'SKIPPED') {
      buttons.add(OutlinedButton(
        onPressed: () => _transition(context, ref, 'SKIPPED'),
        child: const Text('Skip cycle'),
      ));
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: buttons);
  }

  Future<void> _transition(BuildContext context, WidgetRef ref, String target) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(performanceRepositoryProvider).updateCheckIn(
            checkInId: c.id,
            status: target,
          );
      ref.invalidate(performanceCheckInByIdProvider(c.id));
      ref.invalidate(performanceCheckInListProvider);
      messenger.showSnackBar(SnackBar(content: Text('Status → $target')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Transition failed: $e')));
    }
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/performance/performance_check_in_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/performance/performance_check_in_screen.dart
git commit -m "feat(performance): status actions (Submit / Start review / Complete / Skip)"
```

---

## Phase 16 — Employee profile Performance tab

### Task 22: Read-only Performance tab on employee profile

**Files:**
- Create: `lib/features/employees/profile/tabs/performance_tab.dart`
- Modify: `lib/features/employees/profile/employee_profile_screen.dart` (or wherever profile tabs are registered — read first)

- [ ] **Step 1: Find where profile tabs are wired**

Run:
```bash
grep -rln "documents_tab.dart\|role_tab.dart\|payslips_tab.dart" lib/features/employees/profile/
```

The output points at the file that lists the tabs (likely an employee_profile_screen.dart or a tabs registry). Read it briefly and identify the pattern used (TabBar with a list of Tab widgets, paired with a corresponding list of view widgets).

- [ ] **Step 2: Create the read-only tab widget**

Create `lib/features/employees/profile/tabs/performance_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/performance_repository.dart';

class PerformanceTab extends ConsumerWidget {
  final String employeeId;
  const PerformanceTab({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(performanceCheckInListProvider(
      PerformanceListQuery(employeeId: employeeId),
    ));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No performance check-ins yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final c = rows[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('Status: ${c.status}'),
                subtitle: Text(
                  'Created ${c.createdAt.toIso8601String().substring(0, 10)}'
                  '${c.overallRating != null ? '  ·  Overall: ${c.overallRating}/5' : ''}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                onTap: () => context.go('/performance/${c.id}'),
              ),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 3: Register the tab in the profile screen**

In whichever file you found in Step 1 (likely `lib/features/employees/profile/employee_profile_screen.dart`), find the existing tab list. Add a new entry following the same pattern:

- A new `Tab(text: 'Performance')` in the TabBar tabs list.
- A new `PerformanceTab(employeeId: employee.id)` in the TabBarView children list.

Add the import:

```dart
import 'tabs/performance_tab.dart';
```

If the tab pattern uses a different conventional structure (e.g. a registered list of `(label, builder)` pairs), follow it.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/features/employees/profile/`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/employees/profile/tabs/performance_tab.dart \
        lib/features/employees/profile/employee_profile_screen.dart
git commit -m "feat(performance): read-only Performance tab on employee profile"
```

---

## Phase 17 — Final green-bar verification

### Task 23: Full test suite + analyzer

- [ ] **Step 1: Run full analyzer**

Run: `flutter analyze lib/ test/`
Expected: No new issues. Pre-existing issues are unchanged.

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Expected: All tests pass. Baseline was 257 from Workflows MVP; expect 257 + 12 new (CheckInPeriod 2 + PerformanceCheckIn 2 + CheckInGoal 2 + SkillRating 2 + quarter math 3 + check_in_status 5 = 16 — actually 257 + 16 ≈ 273. Counting may vary by ±1; the key is no failures.

- [ ] **Step 3: Compare branch state**

Run: `git log --oneline main..HEAD`
Expected: ~22-24 commits, all performance-related.

Run: `git status --short`
Expected: clean working tree.

- [ ] **Step 4: No commit — checkpoint only.**

---

## Self-review checklist (planner — run before handing this plan off)

- [x] **Spec coverage:** every Scope (in) item maps to a task:
  - Migration → Task 1
  - 4 models → Tasks 2-5
  - Repository + read methods → Tasks 6-7
  - Auto-gen (quarterly + probationary) → Tasks 8-9
  - Check-in auto-gen + skill seeding → Tasks 10-11
  - Status transitions → Tasks 12-13
  - List screen + filter + auto-gen-on-mount → Tasks 14-15
  - Detail screen + 5 sections + status actions → Tasks 16-21
  - Profile tab → Task 22
  - Nav unhide → Task 14
  - Final verification → Task 23
- [x] **No placeholders:** every step has actual code or commands.
- [x] **Type consistency:** `validateCheckInTransition` defined in Task 12, used in Task 13's `updateCheckIn`. `PerformanceListQuery`, `performanceRepositoryProvider`, the 5 providers (`performanceCheckInListProvider`, `performanceCheckInByIdProvider`, `checkInPeriodByIdProvider`, `checkInGoalsProvider`, `skillRatingsProvider`) defined in Tasks 6-7, consumed in Tasks 15+. Repository method signatures match call sites.
- [x] **Integration rule:** `skill_ratings.skill_name` is documented as a deliberate snapshot of `RoleScorecard.kpis[i].metric` — the one allowed copy, called out explicitly. All other entities (employee, period, reviewer) flow through as FKs.

## Open items to verify at execution time

1. **`profile_provider.dart`'s `UserProfile` fields**: confirms `userId`, `companyId`, `employeeId`, `isHrOrAdmin` (used throughout). If any name differs, adapt.
2. **`employeeByIdProvider`** must exist (used in Hiring/Workflows). If missing, add a small provider in the employee repository.
3. **Where profile tabs are registered** (Task 22 Step 1): the existing structure may use a `tabs/` directory + a registry, or inline `Tab`/`TabBarView` pairs. Adapt to whichever pattern is in place.
4. **`employeeListProvider` signature** (Task 15 Step 1): assumed to take an `EmployeeListQuery` (matches Hiring usage). If it accepts no args, drop the parameter.
5. **`Employee.companyId`** (Task 15 Step 1): the model has `companyId` (confirmed earlier). The profile's `companyId` is the user's company; the employee's is the employee's. Auto-gen iterates employees in the profile's company — assume RLS filters appropriately.
