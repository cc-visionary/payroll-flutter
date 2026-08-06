import 'dart:typed_data';

import '../blocks/block.dart';
import '../templates/coe_inputs.dart';
import '../templates/coe_template.dart';
import '../templates/employment_contract_inputs.dart';
import '../templates/employment_contract_template.dart';
import '../templates/final_pay_inputs.dart';
import '../templates/final_pay_template.dart';
import '../templates/liability_waiver_inputs.dart';
import '../templates/liability_waiver_template.dart';
import '../templates/nda_inputs.dart';
import '../templates/nda_template.dart';
import '../templates/nod_inputs.dart';
import '../templates/nod_template.dart';
import '../templates/non_reg_inputs.dart';
import '../templates/non_reg_template.dart';
import '../templates/nte_inputs.dart';
import '../templates/nte_template.dart';
import '../templates/penalty_agreement_inputs.dart';
import '../templates/penalty_agreement_template.dart';
import '../templates/quitclaim_inputs.dart';
import '../templates/quitclaim_template.dart';
import '../templates/regularization_inputs.dart';
import '../templates/regularization_template.dart';
import '../templates/resignation_acceptance_inputs.dart';
import '../templates/resignation_acceptance_template.dart';
import '../templates/salary_adjustment_inputs.dart';
import '../templates/salary_adjustment_template.dart';

/// Thrown when a saved document's `__template_id` has no re-render path yet.
/// The viewer catches this to show a friendly "not available" message instead
/// of a raw stack trace.
class UnsupportedSavedDocument implements Exception {
  final String templateId;
  const UnsupportedSavedDocument(this.templateId);
  @override
  String toString() =>
      'Re-rendering a saved "$templateId" document is not supported yet.';
}

/// Template ids that [blocksForSavedDocument] can re-render. Keep in sync with
/// the switch in [blocksForSavedDocument]; the viewer uses this to show a
/// friendly message instead of attempting an unsupported render. A test asserts
/// this set covers every template in `kTemplates`.
const Set<String> kReRenderableSavedTemplateIds = {
  'employment_contract',
  'coe',
  'nte',
  'non_reg',
  'nda',
  'nod',
  'final_pay',
  'penalty_agreement',
  'quitclaim',
  'regularization',
  'resignation_acceptance',
  'salary_adjustment',
  'liability_waiver',
};

/// Whether a saved document (by its `__template_id`) can be re-rendered.
bool canRenderSavedDocument(Map<String, dynamic> generationOptions) =>
    kReRenderableSavedTemplateIds.contains(generationOptions['__template_id']);

/// Rebuilds a previously-generated document's blocks from its persisted
/// `generation_options` snapshot (which embeds `__template_id`).
///
/// Documents are stored settings-only — the PDF is never persisted — so this is
/// the "render on the fly" view path: reconstruct the typed inputs via the
/// template's `fromJson`, then call its `build`. Pure and synchronous; pass
/// [logoBytes] to restore branding on the templates that carry a logo (it is
/// intentionally excluded from the JSON snapshot).
///
/// To support another template: add its `__template_id` to
/// [kReRenderableSavedTemplateIds] and a case here mapping it to
/// `<Inputs>.fromJson(generationOptions)` and `<Template>().build(...)`.
List<Block> blocksForSavedDocument(
  Map<String, dynamic> generationOptions, {
  Uint8List? logoBytes,
}) {
  final o = generationOptions;
  switch (o['__template_id']) {
    case 'employment_contract':
      return const EmploymentContractTemplate().build(
        EmploymentContractInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'coe':
      return const CoeTemplate().build(
        CoeInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'nte':
      return const NteTemplate().build(
        NteInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'non_reg':
      return const NonRegTemplate().build(
        NonRegInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'nda':
      return const NdaTemplate().build(
        NdaInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'nod':
      return const NodTemplate().build(
        NodInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'final_pay':
      return const FinalPayTemplate().build(
        FinalPayInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'penalty_agreement':
      return const PenaltyAgreementTemplate().build(
        PenaltyAgreementInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'quitclaim':
      return const QuitclaimTemplate().build(
        QuitclaimInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'regularization':
      return const RegularizationTemplate().build(
        RegularizationInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'resignation_acceptance':
      return const ResignationAcceptanceTemplate().build(
        ResignationAcceptanceInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'salary_adjustment':
      return const SalaryAdjustmentTemplate().build(
        SalaryAdjustmentInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    case 'liability_waiver':
      return const LiabilityWaiverTemplate().build(
        LiabilityWaiverInputs.fromJson(o).copyWith(logoBytes: logoBytes),
      );
    default:
      throw UnsupportedSavedDocument(
        o['__template_id'] as String? ?? '(unknown)',
      );
  }
}
