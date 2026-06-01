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
