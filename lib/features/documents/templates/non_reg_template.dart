import 'package:flutter/material.dart' show Icons, IconData;

import '../blocks/block.dart';
import 'document_template.dart';
import 'non_reg_inputs.dart';
import 'non_reg_validate.dart';

class NonRegTemplate extends DocumentTemplate<NonRegInputs> {
  const NonRegTemplate();

  @override
  String get id => 'non_reg';
  @override
  String get name => 'Notice of Non-Regularization';
  @override
  String get description =>
      'Issued when a probationary employee fails to regularize.';
  @override
  IconData get icon => Icons.person_off_outlined;
  @override
  int get version => 1;

  @override
  NonRegInputs emptyInputs() {
    final today = DateTime.now();
    return NonRegInputs(
      employeeId: '',
      employeeFullName: '',
      employeeLastName: '',
      employeePosition: '',
      companyId: '',
      companyName: '',
      dateIssued: today,
      salutationName: '',
      findings: const [],
    );
  }

  @override
  Future<NonRegInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();
    return NonRegInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeLastName: emp.lastName,
      employeePosition: '', // Employee model has no `position` field; HR fills.
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      hrManagerName: co?.hrManagerName,
      dateIssued: today,
      salutationName: emp.lastName,
      findings: const [],
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(NonRegInputs inputs) =>
      validateNonReg(inputs);

  @override
  List<Block> build(NonRegInputs i) => const [];
}

String _addressOf(dynamic co) {
  final parts = [
    co.addressLine1,
    co.addressLine2,
    [co.city, co.province, co.zipCode]
        .where((s) => s != null && (s as String).isNotEmpty)
        .join(', '),
  ].where((s) => s != null && (s as String).isNotEmpty).cast<String>().toList();
  return parts.join(' · ');
}
