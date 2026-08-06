/// Single source of truth for the template id → `document_type` mapping.
///
/// Each code-defined template (see `templates/template_registry.dart`) carries
/// a short `id` (e.g. `'coe'`). When a generated PDF is persisted to the
/// `employee_documents` table, the row's `document_type` column must hold the
/// canonical uppercase code (e.g. `'COE'`). This map is the authoritative
/// bridge between the two — update it whenever a template is added.
library;

/// Document-type metadata resolved from a template id.
class DocumentTypeInfo {
  /// Uppercase `document_type` code stored in `employee_documents`.
  final String code;

  /// Human-readable document title.
  final String title;
  const DocumentTypeInfo(this.code, this.title);
}

/// Template id → [DocumentTypeInfo]. Covers every id in [kTemplates].
const Map<String, DocumentTypeInfo> kDocumentTypeByTemplateId = {
  'coe': DocumentTypeInfo('COE', 'Certificate of Employment'),
  'employment_contract': DocumentTypeInfo(
    'EMPLOYMENT_CONTRACT',
    'Employment Contract',
  ),
  'final_pay': DocumentTypeInfo('FINAL_PAY', 'Final Pay Computation'),
  'liability_waiver': DocumentTypeInfo('LIABILITY_WAIVER', 'Liability Waiver'),
  'nda': DocumentTypeInfo('NDA', 'Non-Disclosure Agreement'),
  'nod': DocumentTypeInfo('NOD', 'Notice of Decision'),
  'non_reg': DocumentTypeInfo(
    'NON_REGULARIZATION',
    'Notice of Non-Regularization',
  ),
  'nte': DocumentTypeInfo('NTE', 'Notice to Explain'),
  'penalty_agreement': DocumentTypeInfo(
    'PENALTY_AGREEMENT',
    'Penalty Repayment Agreement',
  ),
  'quitclaim': DocumentTypeInfo('QUITCLAIM', 'Quitclaim'),
  'regularization': DocumentTypeInfo('REGULARIZATION', 'Regularization'),
  'resignation_acceptance': DocumentTypeInfo(
    'RESIGNATION_ACCEPTANCE',
    'Resignation Acceptance',
  ),
  'salary_adjustment': DocumentTypeInfo(
    'SALARY_ADJUSTMENT',
    'Salary Adjustment',
  ),
};

/// Returns the [DocumentTypeInfo] for [templateId], or null if unknown.
DocumentTypeInfo? documentTypeForTemplateId(String templateId) =>
    kDocumentTypeByTemplateId[templateId];
