import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'adjuncts_repository.dart' show AdjunctDeleteException;

/// Result of persisting a generated document's settings: the saved row id.
///
/// The PDF itself is never stored — it is always rendered on the fly — so the
/// only thing that round-trips is the `employee_documents` row id (held by the
/// generate screen as its `sessionRecordId`).
class SavedDocument {
  final String id;
  const SavedDocument({required this.id});
}

/// Pure builder for the INSERT payload (new `employee_documents` record).
///
/// Kept top-level (no Supabase dependency) so it is unit-testable in isolation.
/// We persist the document's SETTINGS only (no file is stored), so there is no
/// `file_path` / `file_size_bytes` / `mime_type`. `file_name` is retained
/// because the table column is NOT NULL. The template code is NOT a uuid, so it
/// is folded into `generation_options` under the reserved key `'__template_id'`
/// rather than `generated_from_template_id` (which stays null). The spread of
/// [generationOptions] guarantees the caller's original map is never mutated.
Map<String, dynamic> buildInsertPayload({
  required String id,
  required String employeeId,
  required String documentType,
  required String title,
  required String fileName,
  required Map<String, dynamic> generationOptions,
  String? templateId,
}) {
  final opts = {
    ...generationOptions,
    if (templateId != null) '__template_id': templateId,
  };
  return {
    'id': id,
    'employee_id': employeeId,
    'document_type': documentType,
    'title': title,
    'file_name': fileName,
    'generation_options': opts,
    'status': 'ISSUED',
    'generated_from_template_id': null,
  };
}

/// Pure builder for the UPDATE payload (existing session `employee_documents`
/// record being re-saved). Like [buildInsertPayload], it persists settings only
/// (no file columns), never mutates the caller's [generationOptions] map, and
/// folds [templateId] into `generation_options` under `'__template_id'`.
Map<String, dynamic> buildUpdatePayload({
  required String fileName,
  required Map<String, dynamic> generationOptions,
  required DateTime updatedAt,
  String? templateId,
}) {
  final opts = {
    ...generationOptions,
    if (templateId != null) '__template_id': templateId,
  };
  return {
    'file_name': fileName,
    'generation_options': opts,
    'updated_at': updatedAt.toIso8601String(),
    // The update path is also how a pre-inserted DRAFT placeholder becomes the
    // issued notice (see workflow_detail_screen's "Generate now"). Idempotent
    // for the in-session re-save case, where the row is already ISSUED.
    'status': 'ISSUED',
  };
}

/// Records a generated document's SETTINGS in the `employee_documents` table.
///
/// The PDF is always rendered on the fly and is NOT stored anywhere; only the
/// `generation_options` (and a handful of metadata columns) are persisted, "if
/// ever" the settings are needed to reconstruct the document.
///
/// On a fresh save, any prior ISSUED document of the same type for the same
/// employee is marked SUPERSEDED and linked via `supersedes_document_id`. When
/// re-saving an in-session record, the existing row is updated in place.
class EmployeeDocumentRepository {
  final SupabaseClient _client;
  EmployeeDocumentRepository(this._client);

  Future<SavedDocument> saveGenerated({
    required String employeeId,
    required String documentType,
    required String title,
    required String fileName,
    required Map<String, dynamic> generationOptions,
    String? templateId,
    String? sessionRecordId,
  }) async {
    final documentId = sessionRecordId ?? const Uuid().v4();
    if (sessionRecordId == null) {
      final payload = buildInsertPayload(
        id: documentId,
        employeeId: employeeId,
        documentType: documentType,
        title: title,
        fileName: fileName,
        generationOptions: generationOptions,
        templateId: templateId,
      );
      final prior = await _client
          .from('employee_documents')
          .select('id')
          .eq('employee_id', employeeId)
          .eq('document_type', documentType)
          .eq('status', 'ISSUED')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (prior != null) {
        payload['supersedes_document_id'] = prior['id'];
      }
      await _client.from('employee_documents').insert(payload);
      if (prior != null) {
        await _client
            .from('employee_documents')
            .update({'status': 'SUPERSEDED'}).eq('id', prior['id']);
      }
      return SavedDocument(id: documentId);
    } else {
      final payload = buildUpdatePayload(
        fileName: fileName,
        generationOptions: generationOptions,
        updatedAt: DateTime.now().toUtc(),
        templateId: templateId,
      );
      await _client
          .from('employee_documents')
          .update(payload)
          .eq('id', sessionRecordId);
      return SavedDocument(id: sessionRecordId);
    }
  }

  /// Hard-deletes one document record via the `delete_employee_document` RPC
  /// (migration 20260806000001). Unlinks the workflow step that produced it and
  /// any successor that supersedes it, then removes the row.
  ///
  /// This is the manual counterpart to the penalty-workflow cascade: for
  /// paperwork left stranded when whatever it documented was removed by hand.
  Future<void> deleteDocument(String id) async {
    try {
      await _client.rpc('delete_employee_document', params: {'p_id': id});
    } on PostgrestException catch (e) {
      if (e.message.contains('DELETE_FORBIDDEN')) {
        throw AdjunctDeleteException(
          'You do not have permission to delete this document.',
        );
      }
      throw AdjunctDeleteException("Couldn't delete this document.");
    }
  }
}

final employeeDocumentRepositoryProvider =
    Provider<EmployeeDocumentRepository>(
        (ref) => EmployeeDocumentRepository(Supabase.instance.client));
