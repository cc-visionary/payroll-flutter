import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/coe_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/coe_template.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_template.dart';
import 'package:payroll_flutter/features/documents/templates/nda_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nda_template.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_template.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nte_template.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_template.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_template.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_template.dart';

/// Round-trip: copyWith sets the field, toJson persists it, fromJson reads
/// it back; a JSON WITHOUT the key (legacy saved docs) must yield null.
void main() {
  void roundTrip<T>(
    String label,
    dynamic inputsWithSig,
    T Function(Map<String, dynamic>) fromJson,
    String? Function(T) getSig,
  ) {
    test('$label round-trips companySignaturePngB64', () {
      final json = inputsWithSig.toJson() as Map<String, dynamic>;
      expect(getSig(fromJson(json)), 'QUJD');
      json.remove('companySignaturePngB64');
      expect(getSig(fromJson(json)), isNull);
    });
  }

  roundTrip<CoeInputs>(
    'CoeInputs',
    const CoeTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
    CoeInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<NteInputs>(
    'NteInputs',
    const NteTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
    NteInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<NonRegInputs>(
    'NonRegInputs',
    const NonRegTemplate().emptyInputs().copyWith(
      companySignaturePngB64: 'QUJD',
    ),
    NonRegInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<NodInputs>(
    'NodInputs',
    const NodTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
    NodInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<FinalPayInputs>(
    'FinalPayInputs',
    const FinalPayTemplate().emptyInputs().copyWith(
      companySignaturePngB64: 'QUJD',
    ),
    FinalPayInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<SalaryAdjustmentInputs>(
    'SalaryAdjustmentInputs',
    const SalaryAdjustmentTemplate().emptyInputs().copyWith(
      companySignaturePngB64: 'QUJD',
    ),
    SalaryAdjustmentInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<RegularizationInputs>(
    'RegularizationInputs',
    const RegularizationTemplate().emptyInputs().copyWith(
      companySignaturePngB64: 'QUJD',
    ),
    RegularizationInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<ResignationAcceptanceInputs>(
    'ResignationAcceptanceInputs',
    const ResignationAcceptanceTemplate().emptyInputs().copyWith(
      companySignaturePngB64: 'QUJD',
    ),
    ResignationAcceptanceInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<NdaInputs>(
    'NdaInputs',
    const NdaTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
    NdaInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
  roundTrip<EmploymentContractInputs>(
    'EmploymentContractInputs',
    const EmploymentContractTemplate().emptyInputs().copyWith(
      companySignaturePngB64: 'QUJD',
    ),
    EmploymentContractInputs.fromJson,
    (i) => i.companySignaturePngB64,
  );
}
