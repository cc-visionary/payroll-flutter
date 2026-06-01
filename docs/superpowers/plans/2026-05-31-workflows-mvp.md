# Workflows MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the dormant `workflow_instances` + `workflow_steps` schema as a case-management surface for SEPARATION and HIRING processes, with kickoff hooks on existing trigger points and a `/workflows` list + detail UI.

**Architecture:** Standard 3-layer Flutter (model → repo+providers → screens) over an existing Supabase schema. "Generate now" on DOCUMENT_GENERATION steps deep-links to the existing `/documents/generate/<template>` flow (no new PDF storage plumbing). Step completion is manual; workflow_instance auto-completes when all steps are COMPLETED or SKIPPED.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase (Postgres). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-31-workflows-mvp-design.md`

**Parallelization:** Phase 1 (models + repo) is one sequential chain. Phases 3 (list) and 4 (detail) build on phase 2's seeders independently. Phases 7 (separation kickoff), 8 (hiring kickoff), 9 (stub cleanup) are independent of each other.

---

## Phase 1 — Models + Repository

### Task 1: `WorkflowInstance` model

**Files:**
- Create: `lib/data/models/workflow_instance.dart`
- Create: `test/data/models/workflow_instance_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/models/workflow_instance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workflow_instance.dart';

void main() {
  test('WorkflowInstance constructs with required fields', () {
    final w = WorkflowInstance(
      id: 'w1',
      companyId: 'c1',
      employeeId: 'e1',
      workflowType: 'SEPARATION',
      status: 'IN_PROGRESS',
      title: 'Separation — Maria Santos',
      context: const {},
      initiatedById: 'u1',
      createdAt: DateTime.utc(2026, 5, 31),
      updatedAt: DateTime.utc(2026, 5, 31),
    );
    expect(w.id, 'w1');
    expect(w.workflowType, 'SEPARATION');
    expect(w.status, 'IN_PROGRESS');
    expect(w.completedAt, isNull);
  });

  test('WorkflowInstance.fromRow parses all columns', () {
    final r = <String, dynamic>{
      'id': 'w1',
      'company_id': 'c1',
      'employee_id': 'e1',
      'workflow_type': 'HIRING',
      'status': 'DRAFT',
      'title': 'Hiring — Juan Cruz',
      'context': {'applicant_id': 'a1'},
      'result': null,
      'initiated_by_id': 'u1',
      'completed_at': null,
      'cancelled_at': null,
      'cancel_reason': null,
      'created_at': '2026-05-31T08:00:00Z',
      'updated_at': '2026-05-31T08:00:00Z',
    };
    final w = WorkflowInstanceFromRow.fromRow(r);
    expect(w.id, 'w1');
    expect(w.workflowType, 'HIRING');
    expect(w.status, 'DRAFT');
    expect(w.title, 'Hiring — Juan Cruz');
    expect(w.context['applicant_id'], 'a1');
    expect(w.completedAt, isNull);
    expect(w.cancelledAt, isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/data/models/workflow_instance_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement the model**

Create `lib/data/models/workflow_instance.dart`:

```dart
/// Plain-Dart model mirroring the `workflow_instances` table from
/// supabase/migrations/20260414000013_workflows.sql.
///
/// One row = one HR process per employee (a SEPARATION case, a HIRING case,
/// etc.). FK to `employees`; the workflow never duplicates employee data.
class WorkflowInstance {
  final String id;
  final String companyId;
  final String employeeId;
  final String workflowType;   // enum: HIRING|REGULARIZATION|SALARY_CHANGE|ROLE_CHANGE|DISCIPLINARY|SEPARATION|REPAYMENT_AGREEMENT
  final String status;         // enum: DRAFT|IN_PROGRESS|COMPLETED|CANCELLED
  final String title;
  final Map<String, dynamic> context;
  final Map<String, dynamic>? result;
  final String initiatedById;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkflowInstance({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.workflowType,
    required this.status,
    required this.title,
    required this.context,
    this.result,
    required this.initiatedById,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension WorkflowInstanceFromRow on WorkflowInstance {
  static WorkflowInstance fromRow(Map<String, dynamic> r) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return WorkflowInstance(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      employeeId: r['employee_id'] as String,
      workflowType: r['workflow_type'] as String,
      status: r['status'] as String,
      title: r['title'] as String,
      context: (r['context'] as Map<String, dynamic>?) ?? const {},
      result: r['result'] as Map<String, dynamic>?,
      initiatedById: r['initiated_by_id'] as String,
      completedAt: dt(r['completed_at']),
      cancelledAt: dt(r['cancelled_at']),
      cancelReason: r['cancel_reason'] as String?,
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
    );
  }
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/data/models/workflow_instance_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/workflow_instance.dart test/data/models/workflow_instance_test.dart
git commit -m "feat(workflows): WorkflowInstance model + fromRow factory"
```

---

### Task 2: `WorkflowStep` model

**Files:**
- Create: `lib/data/models/workflow_step.dart`
- Create: `test/data/models/workflow_step_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/models/workflow_step_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workflow_step.dart';

void main() {
  test('WorkflowStep constructs with required fields', () {
    final s = WorkflowStep(
      id: 's1',
      workflowInstanceId: 'w1',
      stepIndex: 0,
      stepType: 'DOCUMENT_GENERATION',
      name: 'Generate Quitclaim',
      status: 'PENDING',
      createdAt: DateTime.utc(2026, 5, 31),
      updatedAt: DateTime.utc(2026, 5, 31),
    );
    expect(s.stepIndex, 0);
    expect(s.stepType, 'DOCUMENT_GENERATION');
    expect(s.completedAt, isNull);
    expect(s.generatedDocumentId, isNull);
  });

  test('WorkflowStep.fromRow parses all columns including jsonb fields', () {
    final r = <String, dynamic>{
      'id': 's1',
      'workflow_instance_id': 'w1',
      'step_index': 1,
      'step_type': 'STATUS_UPDATE',
      'name': 'IT account setup',
      'description': 'Provision email + Lark + GitHub access.',
      'status': 'COMPLETED',
      'assigned_to_id': 'u2',
      'input_data': {'template_id': 'quitclaim'},
      'output_data': {'document_id': 'd1'},
      'completed_by_id': 'u2',
      'completed_at': '2026-05-31T09:00:00Z',
      'remarks': 'Done.',
      'generated_document_id': 'd1',
      'created_at': '2026-05-31T08:00:00Z',
      'updated_at': '2026-05-31T09:00:00Z',
    };
    final s = WorkflowStepFromRow.fromRow(r);
    expect(s.id, 's1');
    expect(s.stepIndex, 1);
    expect(s.stepType, 'STATUS_UPDATE');
    expect(s.name, 'IT account setup');
    expect(s.inputData?['template_id'], 'quitclaim');
    expect(s.outputData?['document_id'], 'd1');
    expect(s.generatedDocumentId, 'd1');
    expect(s.completedAt?.toUtc(), DateTime.utc(2026, 5, 31, 9));
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/data/models/workflow_step_test.dart`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement the model**

Create `lib/data/models/workflow_step.dart`:

```dart
/// Plain-Dart model mirroring the `workflow_steps` table from
/// supabase/migrations/20260414000013_workflows.sql.
class WorkflowStep {
  final String id;
  final String workflowInstanceId;
  final int stepIndex;
  final String stepType;        // enum: DATA_ENTRY|APPROVAL|DOCUMENT_GENERATION|STATUS_UPDATE|REVIEW
  final String name;
  final String? description;
  final String status;          // enum: PENDING|IN_PROGRESS|COMPLETED|SKIPPED|REJECTED
  final String? assignedToId;
  final Map<String, dynamic>? inputData;
  final Map<String, dynamic>? outputData;
  final String? completedById;
  final DateTime? completedAt;
  final String? remarks;
  final String? generatedDocumentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkflowStep({
    required this.id,
    required this.workflowInstanceId,
    required this.stepIndex,
    required this.stepType,
    required this.name,
    this.description,
    required this.status,
    this.assignedToId,
    this.inputData,
    this.outputData,
    this.completedById,
    this.completedAt,
    this.remarks,
    this.generatedDocumentId,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension WorkflowStepFromRow on WorkflowStep {
  static WorkflowStep fromRow(Map<String, dynamic> r) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return WorkflowStep(
      id: r['id'] as String,
      workflowInstanceId: r['workflow_instance_id'] as String,
      stepIndex: (r['step_index'] as num).toInt(),
      stepType: r['step_type'] as String,
      name: r['name'] as String,
      description: r['description'] as String?,
      status: r['status'] as String,
      assignedToId: r['assigned_to_id'] as String?,
      inputData: r['input_data'] as Map<String, dynamic>?,
      outputData: r['output_data'] as Map<String, dynamic>?,
      completedById: r['completed_by_id'] as String?,
      completedAt: dt(r['completed_at']),
      remarks: r['remarks'] as String?,
      generatedDocumentId: r['generated_document_id'] as String?,
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
    );
  }
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/data/models/workflow_step_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/workflow_step.dart test/data/models/workflow_step_test.dart
git commit -m "feat(workflows): WorkflowStep model + fromRow factory"
```

---

### Task 3: `WorkflowRepository` scaffold + `WorkflowListQuery`

**Files:**
- Create: `lib/data/repositories/workflow_repository.dart`

- [ ] **Step 1: Implement scaffold + query value object**

Create `lib/data/repositories/workflow_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workflow_instance.dart';
import '../models/workflow_step.dart';

/// Filter parameters for the workflows list. Mirrors ApplicantListQuery shape.
class WorkflowListQuery {
  final List<String>? statuses;   // null = all; default in UI = exclude CANCELLED
  final List<String>? types;       // null = all workflow_types
  final String? employeeId;
  const WorkflowListQuery({this.statuses, this.types, this.employeeId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkflowListQuery &&
          _eq(statuses, other.statuses) &&
          _eq(types, other.types) &&
          employeeId == other.employeeId;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(statuses ?? const []),
        Object.hashAll(types ?? const []),
        employeeId,
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

class WorkflowRepository {
  final SupabaseClient _client;
  WorkflowRepository(this._client);
}

final workflowRepositoryProvider =
    Provider<WorkflowRepository>((ref) => WorkflowRepository(Supabase.instance.client));
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/data/repositories/workflow_repository.dart`
Expected: No issues. (Models import + _client unused will warn — those are consumed in Task 4.)

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/workflow_repository.dart
git commit -m "feat(workflows): WorkflowRepository scaffold + WorkflowListQuery"
```

---

### Task 4: List / byId / stepsForInstance providers

**Files:**
- Modify: `lib/data/repositories/workflow_repository.dart` (append methods + providers)

- [ ] **Step 1: Append read methods to the class**

Inside the `WorkflowRepository` class:

```dart
  Future<List<WorkflowInstance>> list(WorkflowListQuery q) async {
    var builder = _client.from('workflow_instances').select('*');
    if (q.statuses != null && q.statuses!.isNotEmpty) {
      builder = builder.inFilter('status', q.statuses!);
    }
    if (q.types != null && q.types!.isNotEmpty) {
      builder = builder.inFilter('workflow_type', q.types!);
    }
    if (q.employeeId != null) {
      builder = builder.eq('employee_id', q.employeeId!);
    }
    final rows = await builder.order('created_at', ascending: false);
    return (rows as List)
        .map((r) => WorkflowInstanceFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<WorkflowInstance?> byId(String id) async {
    final row = await _client.from('workflow_instances').select('*').eq('id', id).maybeSingle();
    if (row == null) return null;
    return WorkflowInstanceFromRow.fromRow(row);
  }

  Future<List<WorkflowStep>> stepsForInstance(String workflowInstanceId) async {
    final rows = await _client
        .from('workflow_steps')
        .select('*')
        .eq('workflow_instance_id', workflowInstanceId)
        .order('step_index', ascending: true);
    return (rows as List)
        .map((r) => WorkflowStepFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }
```

Then OUTSIDE the class, append providers:

```dart
final workflowListProvider =
    FutureProvider.family<List<WorkflowInstance>, WorkflowListQuery>((ref, q) =>
        ref.read(workflowRepositoryProvider).list(q));

final workflowByIdProvider =
    FutureProvider.family<WorkflowInstance?, String>((ref, id) =>
        ref.read(workflowRepositoryProvider).byId(id));

final workflowStepsProvider =
    FutureProvider.family<List<WorkflowStep>, String>((ref, workflowInstanceId) =>
        ref.read(workflowRepositoryProvider).stepsForInstance(workflowInstanceId));
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/data/repositories/workflow_repository.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/workflow_repository.dart
git commit -m "feat(workflows): list / byId / stepsForInstance providers"
```

---

### Task 5: `insertWithSteps` (atomic-ish kickoff)

**Files:**
- Modify: `lib/data/repositories/workflow_repository.dart` (append method + value objects)

- [ ] **Step 1: Add input value objects + `insertWithSteps`**

At the TOP of the file (after imports), add:

```dart
/// Pure input shape for a new workflow_instance. Used by the seeders in
/// `lib/features/workflows/seeders.dart` so kickoff handlers don't have to
/// know SQL column names.
class WorkflowInstanceInput {
  final String companyId;
  final String employeeId;
  final String workflowType;
  final String title;
  final Map<String, dynamic> context;
  final String initiatedById;
  const WorkflowInstanceInput({
    required this.companyId,
    required this.employeeId,
    required this.workflowType,
    required this.title,
    this.context = const {},
    required this.initiatedById,
  });
}

class WorkflowStepInput {
  final int stepIndex;
  final String stepType;
  final String name;
  final String? description;
  final Map<String, dynamic>? inputData;
  final String? generatedDocumentId;
  const WorkflowStepInput({
    required this.stepIndex,
    required this.stepType,
    required this.name,
    this.description,
    this.inputData,
    this.generatedDocumentId,
  });
}
```

Append to the `WorkflowRepository` class:

```dart
  /// Insert one workflow_instance + N workflow_steps. Two sequential calls —
  /// Supabase Dart client doesn't expose multi-statement transactions, so this
  /// is best-effort atomic. If steps insert fails, the orphan instance is left
  /// in DRAFT and surfaces in the UI for manual cancel/cleanup. Acceptable for
  /// MVP given low-concurrency single-handler usage.
  Future<String> insertWithSteps({
    required WorkflowInstanceInput instance,
    required List<WorkflowStepInput> steps,
  }) async {
    final instanceRow = await _client
        .from('workflow_instances')
        .insert({
          'company_id': instance.companyId,
          'employee_id': instance.employeeId,
          'workflow_type': instance.workflowType,
          'status': 'IN_PROGRESS',  // not DRAFT — DRAFT means "not yet kicked off"
          'title': instance.title,
          'context': instance.context,
          'initiated_by_id': instance.initiatedById,
        })
        .select('id')
        .single();
    final instanceId = (instanceRow as Map<String, dynamic>)['id'] as String;

    if (steps.isNotEmpty) {
      final stepPayload = [
        for (final s in steps)
          {
            'workflow_instance_id': instanceId,
            'step_index': s.stepIndex,
            'step_type': s.stepType,
            'name': s.name,
            'description': s.description,
            'input_data': s.inputData,
            'generated_document_id': s.generatedDocumentId,
          },
      ];
      await _client.from('workflow_steps').insert(stepPayload);
    }
    return instanceId;
  }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/data/repositories/workflow_repository.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/workflow_repository.dart
git commit -m "feat(workflows): insertWithSteps + input value objects"
```

---

### Task 6: Step lifecycle + `maybeCompleteInstance` + `cancelInstance`

**Files:**
- Modify: `lib/data/repositories/workflow_repository.dart`

- [ ] **Step 1: Append lifecycle methods**

Inside the `WorkflowRepository` class:

```dart
  Future<void> markStepInProgress(String stepId) async {
    await _client
        .from('workflow_steps')
        .update({'status': 'IN_PROGRESS'})
        .eq('id', stepId);
  }

  Future<void> markStepCompleted({
    required String stepId,
    required String completedById,
    String? remarks,
    Map<String, dynamic>? outputData,
    String? generatedDocumentId,
  }) async {
    final payload = <String, dynamic>{
      'status': 'COMPLETED',
      'completed_by_id': completedById,
      'completed_at': DateTime.now().toIso8601String(),
      if (remarks != null) 'remarks': remarks,
      if (outputData != null) 'output_data': outputData,
      if (generatedDocumentId != null) 'generated_document_id': generatedDocumentId,
    };
    await _client.from('workflow_steps').update(payload).eq('id', stepId);
  }

  Future<void> markStepSkipped({
    required String stepId,
    required String completedById,
    String? remarks,
  }) async {
    await _client.from('workflow_steps').update({
      'status': 'SKIPPED',
      'completed_by_id': completedById,
      'completed_at': DateTime.now().toIso8601String(),
      if (remarks != null) 'remarks': remarks,
    }).eq('id', stepId);
  }

  Future<void> markStepRejected({
    required String stepId,
    required String completedById,
    required String remarks,
  }) async {
    await _client.from('workflow_steps').update({
      'status': 'REJECTED',
      'completed_by_id': completedById,
      'completed_at': DateTime.now().toIso8601String(),
      'remarks': remarks,
    }).eq('id', stepId);
  }

  /// If every step on the instance is COMPLETED or SKIPPED, flip the instance
  /// status to COMPLETED + stamp completed_at. Called after every step status
  /// change. No-op if any step is still PENDING/IN_PROGRESS, or if the instance
  /// is already COMPLETED/CANCELLED.
  Future<void> maybeCompleteInstance(String instanceId) async {
    final stepRows = await _client
        .from('workflow_steps')
        .select('status')
        .eq('workflow_instance_id', instanceId);
    final statuses = [
      for (final r in (stepRows as List))
        (r as Map<String, dynamic>)['status'] as String,
    ];
    if (statuses.isEmpty) return;
    final allDone = statuses.every((s) => s == 'COMPLETED' || s == 'SKIPPED');
    if (!allDone) return;
    await _client.from('workflow_instances').update({
      'status': 'COMPLETED',
      'completed_at': DateTime.now().toIso8601String(),
    })
    .eq('id', instanceId)
    .inFilter('status', ['DRAFT', 'IN_PROGRESS']);  // idempotent — don't re-complete
  }

  Future<void> cancelInstance({
    required String instanceId,
    required String cancelReason,
    required String cancelledById,
  }) async {
    await _client.from('workflow_instances').update({
      'status': 'CANCELLED',
      'cancelled_at': DateTime.now().toIso8601String(),
      'cancel_reason': cancelReason,
    })
    .eq('id', instanceId)
    .inFilter('status', ['DRAFT', 'IN_PROGRESS']);  // idempotent
  }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/data/repositories/workflow_repository.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/workflow_repository.dart
git commit -m "feat(workflows): step lifecycle (complete/skip/reject) + maybeCompleteInstance + cancelInstance"
```

---

## Phase 2 — Seeders (pure functions)

### Task 7: `seedSeparationWorkflow` + test

**Files:**
- Create: `lib/features/workflows/seeders.dart`
- Create: `test/features/workflows/seeders_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/workflows/seeders_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workflows/seeders.dart';

void main() {
  test('seedSeparationWorkflow with 3 docs produces instance + 3 DOCUMENT_GENERATION steps', () {
    final seed = seedSeparationWorkflow(
      companyId: 'c1',
      employeeId: 'e1',
      employeeFullName: 'Maria Santos',
      documentTypes: const ['QUITCLAIM', 'COE', 'NTE'],
      eventId: 'ev1',
      docIdByType: const {
        'QUITCLAIM': 'd1',
        'COE': 'd2',
        'NTE': 'd3',
      },
      initiatedById: 'u1',
    );
    expect(seed.instance.workflowType, 'SEPARATION');
    expect(seed.instance.title, 'Separation — Maria Santos');
    expect(seed.instance.context['event_id'], 'ev1');
    expect(seed.steps.length, 3);
    expect(seed.steps[0].stepIndex, 0);
    expect(seed.steps[0].stepType, 'DOCUMENT_GENERATION');
    expect(seed.steps[0].name, contains('Quitclaim'));
    expect(seed.steps[0].generatedDocumentId, 'd1');
    expect(seed.steps[0].inputData?['template_id'], 'quitclaim');
    expect(seed.steps[2].generatedDocumentId, 'd3');
  });

  test('seedSeparationWorkflow with empty doc list produces 0 steps', () {
    final seed = seedSeparationWorkflow(
      companyId: 'c1',
      employeeId: 'e1',
      employeeFullName: 'Maria Santos',
      documentTypes: const [],
      eventId: 'ev1',
      docIdByType: const {},
      initiatedById: 'u1',
    );
    expect(seed.steps, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/workflows/seeders_test.dart`
Expected: FAIL — `seeders.dart` missing.

- [ ] **Step 3: Implement the seeder**

Create `lib/features/workflows/seeders.dart`:

```dart
import '../../data/repositories/workflow_repository.dart';

/// Pure output of a seeder: an instance + its steps. Used by kickoff
/// handlers (separation, hiring) to assemble inputs before calling
/// `workflowRepository.insertWithSteps`.
class WorkflowSeed {
  final WorkflowInstanceInput instance;
  final List<WorkflowStepInput> steps;
  const WorkflowSeed({required this.instance, required this.steps});
}

/// Map from `employee_documents.document_type` enum value to the
/// `template_registry.dart` template id.
const _templateIdByDocType = <String, String>{
  'QUITCLAIM': 'quitclaim',
  'COE': 'coe',
  'NTE': 'nte',
  'NON_REG': 'non_reg',
  'EMPLOYMENT_CONTRACT': 'employment_contract',
  'NDA': 'nda',
  'LIABILITY_WAIVER': 'liability_waiver',
};

/// Human-readable label for a document type.
const _docLabel = <String, String>{
  'QUITCLAIM': 'Quitclaim',
  'COE': 'Certificate of Employment',
  'NTE': 'Notice to Explain',
  'NON_REG': 'Notice of Non-Regularization',
  'EMPLOYMENT_CONTRACT': 'Employment Contract',
  'NDA': 'NDA',
  'LIABILITY_WAIVER': 'Liability Waiver',
};

/// Build a SEPARATION workflow: one DOCUMENT_GENERATION step per selected
/// document type. Each step's `input_data` carries the template id + the id
/// of the DRAFT `employee_documents` row that's already been inserted by
/// the separation confirmation handler.
WorkflowSeed seedSeparationWorkflow({
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  required List<String> documentTypes,    // e.g. ['QUITCLAIM', 'COE']
  required String eventId,
  required Map<String, String> docIdByType,  // employee_documents.id keyed by document_type
  required String initiatedById,
}) {
  final steps = <WorkflowStepInput>[];
  for (var i = 0; i < documentTypes.length; i++) {
    final type = documentTypes[i];
    final templateId = _templateIdByDocType[type] ?? type.toLowerCase();
    final label = _docLabel[type] ?? type;
    steps.add(WorkflowStepInput(
      stepIndex: i,
      stepType: 'DOCUMENT_GENERATION',
      name: 'Generate $label',
      description: 'Render the $label PDF and mark this step complete.',
      inputData: {
        'template_id': templateId,
        'employee_document_id': docIdByType[type],
      },
      generatedDocumentId: docIdByType[type],
    ));
  }
  return WorkflowSeed(
    instance: WorkflowInstanceInput(
      companyId: companyId,
      employeeId: employeeId,
      workflowType: 'SEPARATION',
      title: 'Separation — $employeeFullName',
      context: {'event_id': eventId},
      initiatedById: initiatedById,
    ),
    steps: steps,
  );
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/features/workflows/seeders_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workflows/seeders.dart test/features/workflows/seeders_test.dart
git commit -m "feat(workflows): seedSeparationWorkflow (DOCUMENT_GENERATION steps per selected doc)"
```

---

### Task 8: `seedHiringWorkflow` + test

**Files:**
- Modify: `lib/features/workflows/seeders.dart`
- Modify: `test/features/workflows/seeders_test.dart`

- [ ] **Step 1: Append failing tests**

Append to `test/features/workflows/seeders_test.dart` (inside `main()`):

```dart
  test('seedHiringWorkflow produces 4 default STATUS_UPDATE onboarding steps', () {
    final seed = seedHiringWorkflow(
      companyId: 'c1',
      employeeId: 'e1',
      employeeFullName: 'Juan Cruz',
      applicantId: 'a1',
      initiatedById: 'u1',
    );
    expect(seed.instance.workflowType, 'HIRING');
    expect(seed.instance.title, 'Hiring — Juan Cruz');
    expect(seed.instance.context['applicant_id'], 'a1');
    expect(seed.steps.length, 4);
    expect(seed.steps[0].stepType, 'STATUS_UPDATE');
    expect(seed.steps[0].name, contains('IT account'));
    expect(seed.steps[3].name, contains('30-day'));
    for (var i = 0; i < seed.steps.length; i++) {
      expect(seed.steps[i].stepIndex, i);
    }
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/workflows/seeders_test.dart`
Expected: FAIL — `seedHiringWorkflow` not defined.

- [ ] **Step 3: Append the seeder**

Append to `lib/features/workflows/seeders.dart`:

```dart
/// Build a HIRING workflow with 4 default onboarding steps. Each step is a
/// STATUS_UPDATE that HR manually marks complete as the onboarding work
/// happens. Schema supports per-step assignment via `assigned_to_id` — v1
/// leaves it null (implicitly assigned to whoever initiated the workflow).
WorkflowSeed seedHiringWorkflow({
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  required String applicantId,
  required String initiatedById,
}) {
  const onboardingSteps = <String>[
    'IT account & email setup',
    'Equipment provisioning (laptop, peripherals)',
    'Day-1 orientation completed',
    '30-day check-in completed',
  ];
  final steps = <WorkflowStepInput>[
    for (var i = 0; i < onboardingSteps.length; i++)
      WorkflowStepInput(
        stepIndex: i,
        stepType: 'STATUS_UPDATE',
        name: onboardingSteps[i],
      ),
  ];
  return WorkflowSeed(
    instance: WorkflowInstanceInput(
      companyId: companyId,
      employeeId: employeeId,
      workflowType: 'HIRING',
      title: 'Hiring — $employeeFullName',
      context: {'applicant_id': applicantId},
      initiatedById: initiatedById,
    ),
    steps: steps,
  );
}
```

- [ ] **Step 4: Run to verify passing**

Run: `flutter test test/features/workflows/seeders_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workflows/seeders.dart test/features/workflows/seeders_test.dart
git commit -m "feat(workflows): seedHiringWorkflow (4 default STATUS_UPDATE onboarding steps)"
```

---

## Phase 3 — Workflows list screen

### Task 9: Replace stub + unhide nav + permission gate

**Files:**
- Modify: `lib/features/workflows/workflows_screen.dart` (full rewrite)
- Modify: `lib/app/shell.dart` (find Workflows nav line; remove `comingSoon: true`)

- [ ] **Step 1: Replace the screen**

Overwrite `lib/features/workflows/workflows_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../auth/profile_provider.dart';

class WorkflowsScreen extends ConsumerWidget {
  const WorkflowsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.isHrOrAdmin ?? false;
    if (!canManage) {
      return Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(title: const Text('Workflows')),
        body: const Center(
          child: Text('You do not have permission to view workflows.'),
        ),
      );
    }
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Workflows')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Workflows list lands in Task 10.')),
      ),
    );
  }
}
```

- [ ] **Step 2: Unhide nav**

In `lib/app/shell.dart`, find the Workflows nav line (around line 127) reading:

```dart
    _NavItem('Workflows', Icons.alt_route_outlined, '/workflows', _always,
        comingSoon: true),
```

Replace with:

```dart
    _NavItem('Workflows', Icons.alt_route_outlined, '/workflows', _always),
```

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/workflows/ lib/app/shell.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/workflows/workflows_screen.dart lib/app/shell.dart
git commit -m "feat(workflows): unhide nav + permission-gated scaffold (list placeholder)"
```

---

### Task 10: Workflows list table + filter bar

**Files:**
- Modify: `lib/features/workflows/workflows_screen.dart`

- [ ] **Step 1: Convert to ConsumerStatefulWidget + add filter state**

Replace the existing `WorkflowsScreen` class with:

```dart
class WorkflowsScreen extends ConsumerStatefulWidget {
  const WorkflowsScreen({super.key});
  @override
  ConsumerState<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends ConsumerState<WorkflowsScreen> {
  // Default: exclude CANCELLED to keep the inbox focused on actionable cases.
  List<String> _statuses = const ['DRAFT', 'IN_PROGRESS', 'COMPLETED'];
  List<String> _types = const [];  // empty = all types

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (!(profile?.isHrOrAdmin ?? false)) {
      return Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(title: const Text('Workflows')),
        body: const Center(child: Text('You do not have permission to view workflows.')),
      );
    }
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Workflows')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(
            statuses: _statuses,
            types: _types,
            onStatusesChanged: (s) => setState(() => _statuses = s),
            onTypesChanged: (t) => setState(() => _types = t),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _HintBanner(),
          ),
          Expanded(
            child: _WorkflowsTable(statuses: _statuses, types: _types),
          ),
        ],
      ),
    );
  }
}
```

Add the imports at the top:

```dart
import 'package:go_router/go_router.dart';

import '../../data/models/workflow_instance.dart';
import '../../data/repositories/workflow_repository.dart';
import '../../data/repositories/employee_repository.dart';
```

Add helper widgets at the bottom of the file:

```dart
const _kAllTypes = <String>[
  'HIRING', 'REGULARIZATION', 'SALARY_CHANGE', 'ROLE_CHANGE',
  'DISCIPLINARY', 'SEPARATION', 'REPAYMENT_AGREEMENT',
];
const _kAllStatuses = <String>['DRAFT', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'];

class _HintBanner extends StatelessWidget {
  const _HintBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Workflows are created automatically when you confirm a separation or convert an applicant. No manual create in v1.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<String> statuses;
  final List<String> types;
  final ValueChanged<List<String>> onStatusesChanged;
  final ValueChanged<List<String>> onTypesChanged;
  const _FilterBar({
    required this.statuses,
    required this.types,
    required this.onStatusesChanged,
    required this.onTypesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
          const SizedBox(width: 12),
          for (final t in _kAllTypes)
            FilterChip(
              label: Text(t),
              selected: types.contains(t),
              onSelected: (v) {
                final next = [...types];
                if (v) {
                  next.add(t);
                } else {
                  next.remove(t);
                }
                onTypesChanged(next);
              },
            ),
        ],
      ),
    );
  }
}

class _WorkflowsTable extends ConsumerWidget {
  final List<String> statuses;
  final List<String> types;
  const _WorkflowsTable({required this.statuses, required this.types});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = WorkflowListQuery(
      statuses: statuses.isEmpty ? null : statuses,
      types: types.isEmpty ? null : types,
    );
    final async = ref.watch(workflowListProvider(q));
    final employees = ref.watch(employeeListProvider(const EmployeeListQuery(includeArchived: true))).asData?.value ?? const [];
    final empNameById = {for (final e in employees) e.id: e.fullName};

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No workflows match the current filters.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final w = rows[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(w.title),
                subtitle: Text(
                  '${empNameById[w.employeeId] ?? '(unknown employee)'} · '
                  '${w.workflowType} · ${w.status}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                trailing: Text(
                  w.createdAt.toIso8601String().substring(0, 10),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => context.go('/workflows/${w.id}'),
              ),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/workflows/workflows_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/workflows/workflows_screen.dart
git commit -m "feat(workflows): filterable workflows list + hint banner"
```

---

## Phase 4 — Workflow detail screen

### Task 11: Detail screen scaffold + steps timeline (read-only)

**Files:**
- Create: `lib/features/workflows/workflow_detail_screen.dart`
- Modify: `lib/app/router.dart` (add `/workflows/:id`)

- [ ] **Step 1: Create the detail screen**

Create `lib/features/workflows/workflow_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/workflow_instance.dart';
import '../../data/models/workflow_step.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/workflow_repository.dart';
import '../auth/profile_provider.dart';

class WorkflowDetailScreen extends ConsumerWidget {
  final String instanceId;
  const WorkflowDetailScreen({super.key, required this.instanceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (!(profile?.isHrOrAdmin ?? false)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: const Center(child: Text('You do not have permission.')),
      );
    }
    final async = ref.watch(workflowByIdProvider(instanceId));
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Workflow')),
        body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      ),
      data: (w) {
        if (w == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Workflow')),
            body: const Center(child: Text('Workflow not found.')),
          );
        }
        return _Body(w: w);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final WorkflowInstance w;
  const _Body({required this.w});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeByIdProvider(w.employeeId)).asData?.value;
    final stepsAsync = ref.watch(workflowStepsProvider(w.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(w.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/workflows'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Chip(label: Text(w.workflowType)),
              const SizedBox(width: 8),
              Chip(label: Text(w.status)),
              const SizedBox(width: 12),
              if (employee != null)
                Text(employee.fullName, style: const TextStyle(fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            Text(
              'Created ${w.createdAt.toIso8601String().substring(0, 10)}'
              '${w.completedAt != null ? '  ·  Completed ${w.completedAt!.toIso8601String().substring(0, 10)}' : ''}'
              '${w.cancelledAt != null ? '  ·  Cancelled ${w.cancelledAt!.toIso8601String().substring(0, 10)}' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            stepsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Text('Error loading steps: $e', style: const TextStyle(color: Colors.red)),
              data: (steps) => _StepsTimeline(workflow: w, steps: steps),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepsTimeline extends StatelessWidget {
  final WorkflowInstance workflow;
  final List<WorkflowStep> steps;
  const _StepsTimeline({required this.workflow, required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Text('No steps in this workflow.');
    }
    final done = steps.where((s) => s.status == 'COMPLETED' || s.status == 'SKIPPED').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$done / ${steps.length} steps complete',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        for (final s in steps)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    child: Text('${s.stepIndex + 1}', style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (s.description != null) ...[
                          const SizedBox(height: 2),
                          Text(s.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              )),
                        ],
                        const SizedBox(height: 6),
                        Row(children: [
                          Chip(label: Text(s.status)),
                          const SizedBox(width: 8),
                          Text(s.stepType,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              )),
                        ]),
                        if (s.completedAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Completed ${s.completedAt!.toIso8601String().substring(0, 16)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                        if (s.remarks != null) ...[
                          const SizedBox(height: 4),
                          Text(s.remarks!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              )),
                        ],
                        // Action buttons land in Task 12.
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Add the route**

In `lib/app/router.dart`, find the existing `/workflows` route (around line 153). After it, add:

```dart
          GoRoute(
            path: '/workflows/:id',
            builder: (c, s) => WorkflowDetailScreen(instanceId: s.pathParameters['id']!),
          ),
```

And add the import:

```dart
import '../features/workflows/workflow_detail_screen.dart';
```

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/workflows/ lib/app/router.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/workflows/workflow_detail_screen.dart lib/app/router.dart
git commit -m "feat(workflows): detail screen scaffold + read-only steps timeline"
```

---

### Task 12: Step action buttons (Generate now / Mark complete / Skip)

**Files:**
- Modify: `lib/features/workflows/workflow_detail_screen.dart`

- [ ] **Step 1: Add per-step action widgets**

Append to `lib/features/workflows/workflow_detail_screen.dart` (at the bottom, after `_StepsTimeline`):

```dart
class _StepActions extends ConsumerWidget {
  final WorkflowInstance workflow;
  final WorkflowStep step;
  const _StepActions({required this.workflow, required this.step});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = step.status == 'PENDING' || step.status == 'IN_PROGRESS';
    final isTerminal = workflow.status == 'COMPLETED' || workflow.status == 'CANCELLED';
    if (!isOpen || isTerminal) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, children: [
        if (step.stepType == 'DOCUMENT_GENERATION')
          FilledButton.icon(
            onPressed: () => _generateNow(context, ref),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Generate now'),
          ),
        if (step.stepType != 'DOCUMENT_GENERATION' && step.stepType != 'APPROVAL')
          FilledButton.tonal(
            onPressed: () => _markComplete(context, ref),
            child: const Text('Mark complete'),
          ),
        if (step.stepType == 'APPROVAL') ...[
          FilledButton.tonal(
            onPressed: () => _approve(context, ref),
            child: const Text('Approve'),
          ),
          OutlinedButton(
            onPressed: () => _reject(context, ref),
            child: const Text('Reject'),
          ),
        ],
        TextButton(
          onPressed: () => _skip(context, ref),
          child: const Text('Skip'),
        ),
      ]),
    );
  }

  Future<void> _generateNow(BuildContext context, WidgetRef ref) async {
    // Deep-link to the existing documents generate flow. The user renders
    // and shares the PDF there, then returns and clicks "Mark complete"
    // back here. v1 does NOT auto-render; persistence of PDF bytes to
    // Supabase storage is a separate v2 enhancement.
    final templateId = step.inputData?['template_id'] as String?;
    if (templateId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Step has no template_id; cannot generate.')),
      );
      return;
    }
    // Mark step IN_PROGRESS so HR can see "this one's actively being worked on".
    // The step stays open until HR explicitly clicks "Mark complete" — Skipping
    // back to /workflows preserves the IN_PROGRESS state.
    await ref.read(workflowRepositoryProvider).markStepInProgress(step.id);
    ref.invalidate(workflowStepsProvider(workflow.id));
    if (!context.mounted) return;
    // Pre-select the employee so the form opens ready to go.
    context.go('/documents/generate/$templateId?employeeId=${workflow.employeeId}');
  }

  Future<void> _markComplete(BuildContext context, WidgetRef ref) async {
    final remarks = await _remarksDialog(context, 'Mark step complete?', 'Remarks (optional)');
    if (remarks == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).markStepCompleted(
          stepId: step.id,
          completedById: profile.userId,
          remarks: remarks.trim().isEmpty ? null : remarks.trim(),
          generatedDocumentId: step.stepType == 'DOCUMENT_GENERATION' ? step.generatedDocumentId : null,
        );
    await ref.read(workflowRepositoryProvider).maybeCompleteInstance(workflow.id);
    ref.invalidate(workflowStepsProvider(workflow.id));
    ref.invalidate(workflowByIdProvider(workflow.id));
    ref.invalidate(workflowListProvider);
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final remarks = await _remarksDialog(context, 'Approve this step?', 'Approval remarks (optional)');
    if (remarks == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).markStepCompleted(
          stepId: step.id,
          completedById: profile.userId,
          remarks: remarks.trim().isEmpty ? null : remarks.trim(),
        );
    await ref.read(workflowRepositoryProvider).maybeCompleteInstance(workflow.id);
    ref.invalidate(workflowStepsProvider(workflow.id));
    ref.invalidate(workflowByIdProvider(workflow.id));
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final remarks = await _remarksDialog(context, 'Reject this step?', 'Rejection reason (required)', requireNonEmpty: true);
    if (remarks == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).markStepRejected(
          stepId: step.id,
          completedById: profile.userId,
          remarks: remarks.trim(),
        );
    ref.invalidate(workflowStepsProvider(workflow.id));
  }

  Future<void> _skip(BuildContext context, WidgetRef ref) async {
    final remarks = await _remarksDialog(context, 'Skip this step?', 'Skip reason (optional)');
    if (remarks == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).markStepSkipped(
          stepId: step.id,
          completedById: profile.userId,
          remarks: remarks.trim().isEmpty ? null : remarks.trim(),
        );
    await ref.read(workflowRepositoryProvider).maybeCompleteInstance(workflow.id);
    ref.invalidate(workflowStepsProvider(workflow.id));
    ref.invalidate(workflowByIdProvider(workflow.id));
  }
}

Future<String?> _remarksDialog(
  BuildContext context,
  String title,
  String label, {
  bool requireNonEmpty = false,
}) async {
  final ctl = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (requireNonEmpty && ctl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(ctl.text);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  } finally {
    ctl.dispose();
  }
}
```

- [ ] **Step 2: Wire `_StepActions` into `_StepsTimeline`**

Inside `_StepsTimeline.build`, find `// Action buttons land in Task 12.` and replace with:

```dart
                        _StepActions(workflow: workflow, step: s),
```

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/workflows/workflow_detail_screen.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/workflows/workflow_detail_screen.dart
git commit -m "feat(workflows): per-step actions (Generate now / Mark complete / Approve / Reject / Skip)"
```

---

### Task 13: "Cancel workflow" action + completed banner

**Files:**
- Modify: `lib/features/workflows/workflow_detail_screen.dart`

- [ ] **Step 1: Add Cancel button + COMPLETED banner**

In `_Body.build`, insert a banner block BEFORE the `Row(children: [Chip(...)...])`:

```dart
            if (w.status == 'COMPLETED') ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Workflow completed ${w.completedAt?.toIso8601String().substring(0, 10) ?? ''}',
                    style: const TextStyle(color: Colors.green),
                  ),
                ]),
              ),
            ],
            if (w.status == 'CANCELLED') ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Icon(Icons.cancel_outlined, color: Theme.of(context).colorScheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cancelled${w.cancelReason != null ? ' — ${w.cancelReason}' : ''}',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ]),
              ),
            ],
```

At the BOTTOM of the body Column (after the steps timeline), add the Cancel button:

```dart
            if (w.status == 'IN_PROGRESS' || w.status == 'DRAFT') ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelWorkflow(context, ref),
                  icon: Icon(Icons.cancel_outlined, color: Theme.of(context).colorScheme.error, size: 18),
                  label: Text('Cancel workflow', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            ],
```

Add the `_cancelWorkflow` method inside `_Body`:

```dart
  Future<void> _cancelWorkflow(BuildContext context, WidgetRef ref) async {
    final reason = await _remarksDialog(context, 'Cancel this workflow?', 'Cancellation reason (required)', requireNonEmpty: true);
    if (reason == null) return;
    final profile = ref.read(userProfileProvider).asData!.value!;
    await ref.read(workflowRepositoryProvider).cancelInstance(
          instanceId: w.id,
          cancelReason: reason.trim(),
          cancelledById: profile.userId,
        );
    ref.invalidate(workflowByIdProvider(w.id));
    ref.invalidate(workflowListProvider);
  }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/features/workflows/workflow_detail_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/workflows/workflow_detail_screen.dart
git commit -m "feat(workflows): cancel workflow action + COMPLETED/CANCELLED banners"
```

---

## Phase 5 — Kickoff hooks

### Task 14: Separation kickoff in `profile_header.dart`

**Files:**
- Modify: `lib/features/employees/profile/widgets/profile_header.dart`

- [ ] **Step 1: Read the existing separation handler**

Run: `grep -n "SEPARATION_CONFIRMED\|generated_from_event_id\|employee_documents" lib/features/employees/profile/widgets/profile_header.dart | head -20`

Confirm the existing handler structure: it currently inserts `employment_events` (capturing `eventId`) then conditionally inserts `employee_documents` rows. Your task: after the `employee_documents` insert succeeds, query the inserted rows back to get their ids by document_type, then insert a SEPARATION workflow.

- [ ] **Step 2: Modify the separation handler**

In `lib/features/employees/profile/widgets/profile_header.dart`, find the existing block (around line 332-345) that ends with `await client.from('employee_documents').insert(docs);`.

REPLACE that whole block with:

```dart
    // 3) Queue document placeholders (DRAFT) + insert a SEPARATION workflow
    //    so HR has a single "what's in-flight" inbox. The workflow_steps link
    //    to the placeholder rows via input_data + generated_document_id; the
    //    actual PDF rendering happens via "Generate now" on /workflows/:id.
    if (result.documents.isNotEmpty) {
      final docs = [
        for (final type in result.documents)
          {
            'employee_id': employee.id,
            'document_type': type,
            'title': _docTitleFor(type),
            'file_name': '${employee.fullName} — ${_docTitleFor(type)}.pdf',
            'status': 'DRAFT',
            'generated_from_event_id': eventId,
            if (actorId != null) 'uploaded_by_id': actorId,
          },
      ];
      // Insert with .select() so we get the new ids back to link the workflow steps.
      final insertedDocs = await client
          .from('employee_documents')
          .insert(docs)
          .select('id, document_type');
      final docIdByType = <String, String>{
        for (final d in (insertedDocs as List))
          (d as Map<String, dynamic>)['document_type'] as String:
              d['id'] as String,
      };
      if (actorId != null) {
        final seed = seedSeparationWorkflow(
          companyId: employee.companyId,
          employeeId: employee.id,
          employeeFullName: employee.fullName,
          documentTypes: result.documents,
          eventId: eventId,
          docIdByType: docIdByType,
          initiatedById: actorId,
        );
        await container
            .read(workflowRepositoryProvider)
            .insertWithSteps(instance: seed.instance, steps: seed.steps);
        container.invalidate(workflowListProvider);
      }
    }
```

Add the imports at the top of `profile_header.dart`:

```dart
import '../../../../data/repositories/workflow_repository.dart';
import '../../../workflows/seeders.dart';
```

Verify the existing handler uses `container` (a `ProviderContainer`) — if it uses `ref.read(...)` instead, adapt accordingly. The grep above showed `container.invalidate(...)` patterns, so the file likely has a `ProviderContainer`-based handler (called from outside a widget). Match that pattern.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/employees/profile/widgets/profile_header.dart`
Expected: No issues.

Run: `flutter test`
Expected: All existing tests pass — the change is additive on a code path that doesn't run during unit tests.

- [ ] **Step 4: Commit**

```bash
git add lib/features/employees/profile/widgets/profile_header.dart
git commit -m "feat(workflows): insert SEPARATION workflow on separation confirmation"
```

---

### Task 15: Hiring kickoff in `convert_action.dart`

**Files:**
- Modify: `lib/features/hiring/convert_action.dart`
- Modify: `lib/features/employees/employee_form_screen.dart` (verify `onCreatedFromApplicant` callback receives the new employee — read-only check; modify only if needed)

- [ ] **Step 1: Read the existing convert handler**

Run: `grep -n "onCreatedFromApplicant\|markConverted\|seedHiringWorkflow" lib/features/hiring/convert_action.dart lib/features/employees/employee_form_screen.dart`

Confirm the current flow: `onCreatedFromApplicant: (employeeId) async { ... markConverted(...); ... }`. Your task: after `markConverted` succeeds, also insert a HIRING workflow.

- [ ] **Step 2: Add HIRING workflow kickoff after markConverted**

In `lib/features/hiring/convert_action.dart`, find the existing `onCreatedFromApplicant` callback (around the line `await ref.read(applicantRepositoryProvider).markConverted(...)`). After the `ref.invalidate(...)` lines (and inside the success branch of the try), append:

```dart
            // Insert a HIRING workflow so onboarding work is tracked in /workflows.
            final profile = ref.read(userProfileProvider).asData?.value;
            if (profile != null) {
              final seed = seedHiringWorkflow(
                companyId: a.companyId,
                employeeId: employeeId,
                employeeFullName: a.fullName,
                applicantId: a.id,
                initiatedById: profile.userId,
              );
              await ref.read(workflowRepositoryProvider).insertWithSteps(
                    instance: seed.instance,
                    steps: seed.steps,
                  );
              ref.invalidate(workflowListProvider);
            }
```

Add imports at the top of `convert_action.dart`:

```dart
import '../../data/repositories/workflow_repository.dart';
import '../auth/profile_provider.dart';
import 'workflows/seeders.dart';
```

(If `'workflows/seeders.dart'` resolves wrong because `convert_action.dart` is in `hiring/` and seeders is in `workflows/`, use the correct relative path: `'../workflows/seeders.dart'`. Verify.)

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/hiring/convert_action.dart`
Expected: No issues.

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/hiring/convert_action.dart
git commit -m "feat(workflows): insert HIRING workflow on applicant conversion"
```

---

## Phase 6 — Onboarding/Offboarding stub cleanup

### Task 16: Delete Onboarding + Offboarding stubs

**Files:**
- Delete: `lib/features/onboarding/onboarding_screen.dart`
- Delete: `lib/features/offboarding/offboarding_screen.dart`
- Modify: `lib/app/router.dart` (remove imports + routes)
- Modify: `lib/app/shell.dart` (remove nav items)

- [ ] **Step 1: Delete the stub files**

Run:

```bash
rm lib/features/onboarding/onboarding_screen.dart
rm lib/features/offboarding/offboarding_screen.dart
rmdir lib/features/onboarding lib/features/offboarding 2>/dev/null || true
```

- [ ] **Step 2: Remove router entries**

In `lib/app/router.dart`:

1. Delete lines 36-37 (or whichever lines have):
```dart
import '../features/offboarding/offboarding_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
```

2. Delete lines 156-157 (or whichever lines have):
```dart
          GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
          GoRoute(path: '/offboarding', builder: (c, s) => const OffboardingScreen()),
```

- [ ] **Step 3: Remove nav items from shell**

In `lib/app/shell.dart`, find the two NavItem lines (around 96, 98):

```dart
    _NavItem('Onboarding', Icons.rocket_launch_outlined, '/onboarding', _always,
        comingSoon: true),
    _NavItem('Offboarding', Icons.logout_outlined, '/offboarding', _always,
        comingSoon: true),
```

DELETE both `_NavItem(...)` entries entirely (along with their `comingSoon: true` continuation lines). Make sure trailing commas of surrounding items remain syntactically correct.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/`
Expected: No new issues. Any pre-existing analyzer issues remain unchanged. No "Onboarding/Offboarding" symbols anywhere.

Run: `grep -rn "OnboardingScreen\|OffboardingScreen\|/onboarding\|/offboarding" lib/ test/ 2>/dev/null`
Expected: no matches.

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A lib/app/router.dart lib/app/shell.dart
git add -A lib/features/onboarding lib/features/offboarding 2>/dev/null || true
git commit -m "refactor(nav): remove Onboarding/Offboarding stubs (collapsed into Workflows)"
```

---

## Phase 7 — Final verification

### Task 17: Full green-bar checkpoint

- [ ] **Step 1: Run full analyzer**

Run: `flutter analyze lib/ test/`
Expected: No new issues introduced by this branch. Compare to baseline (`git stash && flutter analyze lib/ test/ && git stash pop` if uncertain — though the working tree should be clean by now).

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Expected: All tests pass. Baseline was 250 from the Hiring MVP merge; expect 250 + 7 new (2 model tests × 2 = 4 + 3 seeder tests = 7) → ~257 total.

- [ ] **Step 3: Compare branch state**

Run: `git log --oneline main..HEAD`
Expected: ~16-17 commits, all hiring/workflows-related, nothing else.

Run: `git status --short`
Expected: clean working tree.

- [ ] **Step 4: No commit — checkpoint only.**

---

## Self-review checklist (planner — run before handing this plan off)

- [x] **Spec coverage:** Every spec section maps to a task. Scope (in) items 1-10 → Tasks 1-16.
- [x] **No placeholders:** Each step has actual code or commands; no "TBD", "implement later", or "add appropriate error handling".
- [x] **Type consistency:** `WorkflowInstanceInput`/`WorkflowStepInput` defined in Task 5, used in Tasks 7-8 (seeders) and Tasks 14-15 (kickoff). `WorkflowSeed` returned by seeders in Tasks 7-8, consumed in Tasks 14-15. `seedSeparationWorkflow` and `seedHiringWorkflow` signatures match consumer calls.
- [x] **Integration rule (user-stated):** No copies of employee data anywhere; workflow rows reference FKs only. DOCUMENT_GENERATION step's `input_data.employee_document_id` points at the existing DRAFT row created by the separation handler — not a duplicate.
- [x] **"Generate now" mechanics:** Deep-links to `/documents/generate/<template>?employeeId=...` rather than implementing new PDF storage. Plan-time open item from the spec (about `file_path` storage) is resolved by deferring file persistence to v2.

## Open items to verify at execution time (small, intentional)

1. **`profile_header.dart` `container.invalidate` vs `ref.invalidate`** (Task 14): the existing separation handler uses `container` (a `ProviderContainer`). The new workflow insert needs to match — read the file and use whichever pattern is there.
2. **Relative import path for `seeders.dart` from `convert_action.dart`** (Task 15): `convert_action.dart` is in `lib/features/hiring/` and seeders is in `lib/features/workflows/` — the correct relative import is `'../workflows/seeders.dart'`. Verify before committing.
3. **`/documents/generate/:templateId?employeeId=...`** (Task 12): GoRouter query parameters are passed through `state.uri.queryParameters['employeeId']`. The existing `generate_screen.dart` may or may not consume this query param. Verify at execution time; if not, the deep link still works (template loads, employee picker is empty, HR picks the employee manually). Acceptable for MVP; a follow-up patch can wire the query param through.
