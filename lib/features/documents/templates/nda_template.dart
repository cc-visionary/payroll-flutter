import 'package:flutter/material.dart' show Icons, IconData;

import '../blocks/block.dart';
import '../providers.dart';
import 'document_template.dart';
import 'nda_inputs.dart';
import 'nda_validate.dart';

class NdaTemplate extends DocumentTemplate<NdaInputs> {
  const NdaTemplate();
  @override
  String get id => 'nda';
  @override
  String get name => 'Confidentiality & Non-Disclosure Agreement';
  @override
  String get description => 'NDA signed upon employment.';
  @override
  IconData get icon => Icons.lock_outline;
  @override
  int get version => 1;

  @override
  NdaInputs emptyInputs() => NdaInputs(
        employeeId: '',
        employeeFullName: '',
        companyId: '',
        companyName: '',
      );

  @override
  Future<NdaInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    DateTime? hireDate;
    try {
      final row = await ctx.ref.read(latestEmploymentEventProvider(
              (employeeId: emp.id, eventType: 'HIRE'))
          .future);
      final v = row?['event_date'] as String?;
      hireDate = v == null ? null : DateTime.parse(v);
    } catch (_) {
      hireDate = null;
    }
    return NdaInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeePosition: emp.jobTitle ?? '',
      employeeHomeAddress: _composeAddress(emp.addressLine1, emp.addressLine2,
          emp.city, emp.province, emp.zipCode),
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null
          ? ''
          : _composeAddress(co.addressLine1, co.addressLine2, co.city,
              co.province, co.zipCode),
      effectiveDate: hireDate ?? emp.hireDate,
      authorizedSignatoryName: (co?.legalSignatoryName?.isNotEmpty == true)
          ? co!.legalSignatoryName!
          : (co?.hrManagerName ?? ''),
      authorizedSignatoryRole: (co?.legalSignatoryRole?.isNotEmpty == true)
          ? co!.legalSignatoryRole!
          : 'Authorized Signatory',
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];
  @override
  List<ValidationError> validate(NdaInputs inputs) => validateNda(inputs);
  @override
  List<Block> build(NdaInputs i) => const [];
}

String _composeAddress(
    String? l1, String? l2, String? city, String? prov, String? zip) {
  final tail = [city, prov, zip].where((s) => s != null && s.isNotEmpty).join(', ');
  return [l1, l2, tail]
      .where((s) => s != null && s.isNotEmpty)
      .cast<String>()
      .join(', ');
}
