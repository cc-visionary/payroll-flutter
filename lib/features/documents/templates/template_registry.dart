import 'coe_template.dart';
import 'document_template.dart';
import 'employment_contract_template.dart';
import 'final_pay_template.dart';
import 'liability_waiver_template.dart';
import 'nda_template.dart';
import 'nod_template.dart';
import 'non_reg_template.dart';
import 'nte_template.dart';
import 'quitclaim_template.dart';
import 'regularization_template.dart';
import 'resignation_acceptance_template.dart';
import 'salary_adjustment_template.dart';

/// Registry of all document templates. The picker reads this list directly.
const List<DocumentTemplate> kTemplates = [
  QuitclaimTemplate(),
  CoeTemplate(),
  NteTemplate(),
  NonRegTemplate(),
  EmploymentContractTemplate(),
  NdaTemplate(),
  LiabilityWaiverTemplate(),
  FinalPayTemplate(),
  SalaryAdjustmentTemplate(),
  NodTemplate(),
  RegularizationTemplate(),
  ResignationAcceptanceTemplate(),
];

DocumentTemplate? findTemplateById(String id) {
  for (final t in kTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
