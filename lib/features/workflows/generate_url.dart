/// Builds the `/documents/generate/:templateId` URL for a workflow's
/// DOCUMENT_GENERATION step.
///
/// `changeId` makes the salary-adjustment notice render THIS compensation
/// change rather than the newest one. `documentId` is the step's pre-inserted
/// DRAFT `employee_documents` row — passing it makes the generate screen UPDATE
/// that row (flipping it to ISSUED) instead of inserting a second, unlinked
/// document. Both are omitted when the step has no such id.
String buildGenerateDocumentUrl({
  required String templateId,
  required String employeeId,
  String? changeId,
  String? documentId,
}) {
  final buffer = StringBuffer('/documents/generate/$templateId?employeeId=$employeeId');
  if (changeId != null) buffer.write('&changeId=$changeId');
  if (documentId != null) buffer.write('&documentId=$documentId');
  return buffer.toString();
}
