import 'package:flutter/material.dart' show IconData, Icons;

import 'coe_template.dart';
import 'document_template.dart';
import 'employment_contract_template.dart';
import 'final_pay_template.dart';
import 'liability_waiver_template.dart';
import 'nda_template.dart';
import 'nod_template.dart';
import 'non_reg_template.dart';
import 'nte_template.dart';
import 'penalty_agreement_template.dart';
import 'quitclaim_template.dart';
import 'regularization_template.dart';
import 'resignation_acceptance_template.dart';
import 'salary_adjustment_template.dart';

/// A named grouping of document templates, surfaced as a section in the picker.
/// Categories follow the HR employment lifecycle so the right document is easy
/// to find as the catalog grows.
class DocumentCategory {
  final String id;
  final String label;
  final String blurb;
  final IconData icon;
  final List<DocumentTemplate> templates;
  const DocumentCategory({
    required this.id,
    required this.label,
    required this.blurb,
    required this.icon,
    required this.templates,
  });
}

/// All document templates, grouped by lifecycle stage. **This is the single
/// source of truth.** To add a template, drop it under the category it belongs
/// to — it then appears in the picker (and, if [DocumentTemplate.supportsBulk],
/// the bulk flow) automatically. [kTemplates] is derived from this list.
const List<DocumentCategory> kDocumentCategories = [
  DocumentCategory(
    id: 'employment',
    label: 'Onboarding & Employment',
    blurb: 'Hiring paperwork, contracts, and the probationary lifecycle.',
    icon: Icons.badge_outlined,
    templates: [
      EmploymentContractTemplate(),
      NdaTemplate(),
      RegularizationTemplate(),
      NonRegTemplate(),
    ],
  ),
  DocumentCategory(
    id: 'compensation',
    label: 'Compensation & Movement',
    blurb: 'Salary adjustments, promotions, and role changes.',
    icon: Icons.trending_up,
    templates: [SalaryAdjustmentTemplate()],
  ),
  DocumentCategory(
    id: 'disciplinary',
    label: 'Disciplinary',
    blurb: 'Due-process notices and decisions under the Labor Code.',
    icon: Icons.gavel_outlined,
    templates: [NteTemplate(), NodTemplate(), PenaltyAgreementTemplate()],
  ),
  DocumentCategory(
    id: 'separation',
    label: 'Separation & Offboarding',
    blurb: 'Resignation, clearance, final pay, and certificates.',
    icon: Icons.logout,
    templates: [
      ResignationAcceptanceTemplate(),
      QuitclaimTemplate(),
      FinalPayTemplate(),
      CoeTemplate(),
    ],
  ),
  DocumentCategory(
    id: 'waivers',
    label: 'Waivers & Other',
    blurb: 'Event waivers and miscellaneous releases.',
    icon: Icons.shield_outlined,
    templates: [LiabilityWaiverTemplate()],
  ),
];

/// Flat list of every template, ordered by category. Derived from
/// [kDocumentCategories] so there is exactly one source of truth. The picker,
/// bulk flow, and [findTemplateById] all read from here.
final List<DocumentTemplate> kTemplates = [
  for (final c in kDocumentCategories) ...c.templates,
];

DocumentTemplate? findTemplateById(String id) {
  for (final t in kTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
