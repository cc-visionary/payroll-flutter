import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons, IconData;
import 'package:intl/intl.dart';

import '../../../data/models/role_scorecard.dart';

import '../blocks/block.dart';
import '../brand_logo.dart';
import '../providers.dart';
import 'document_template.dart';
import 'employment_contract_inputs.dart';
import 'employment_contract_validate.dart';
import 'non_reg_template.dart' show defaultProbationaryEnd;

class EmploymentContractTemplate
    extends DocumentTemplate<EmploymentContractInputs> {
  const EmploymentContractTemplate();

  @override
  String get id => 'employment_contract';
  @override
  String get name => 'Employment Contract';
  @override
  String get description =>
      'Probationary employment agreement with Annex A duties.';
  @override
  IconData get icon => Icons.assignment_outlined;
  @override
  int get version => 1;

  @override
  EmploymentContractInputs emptyInputs() {
    final today = DateTime.now();
    return EmploymentContractInputs(
      employeeId: '',
      employeeFullName: '',
      employeeAddress: '',
      companyId: '',
      companyName: '',
      companyAddress: '',
      representativeName: '',
      representativeRole: 'People Manager',
      place: '',
      dateEntered: today,
      industry: 'Retail Industry',
      position: '',
      monthlySalary: '',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Saturday',
      nonCompeteMonths: 24,
      employerSignatoryName: '',
      employerSignatoryRole: '',
      responsibilities: const [],
      kpis: const [],
    );
  }

  @override
  Future<EmploymentContractInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();

    // Role scorecard drives Annex A (mission, duties, KPIs) plus salary
    // and work-schedule defaults. Best-effort: a missing/unreadable
    // scorecard (e.g. no Supabase client in tests) falls back to the
    // template defaults below.
    RoleScorecard? scorecard;
    final scorecardId = emp.roleScorecardId;
    if (scorecardId != null && scorecardId.isNotEmpty) {
      try {
        scorecard = await ctx.ref
            .read(roleScorecardByIdProvider(scorecardId).future);
      } catch (_) {
        scorecard = null;
      }
    }

    // Latest HIRE event seeds the probation start; fall back to the
    // employee's hireDate. Wrapped so dev/test envs without Supabase
    // degrade gracefully (mirrors the Non-Reg autofill pattern).
    Map<String, dynamic>? hireRow;
    try {
      hireRow = await ctx.ref.read(latestEmploymentEventProvider(
              (employeeId: emp.id, eventType: 'HIRE'))
          .future);
    } catch (_) {
      hireRow = null;
    }
    DateTime? eventDate(Map<String, dynamic>? r) {
      if (r == null) return null;
      final v = r['event_date'] as String?;
      return v == null ? null : DateTime.parse(v);
    }

    final probStart = eventDate(hireRow) ?? emp.hireDate;
    final probEnd = defaultProbationaryEnd(probStart);

    final repName = co?.hrManagerName ?? '';
    final repRole = (co?.legalSignatoryRole?.isNotEmpty == true)
        ? co!.legalSignatoryRole!
        : 'People Manager';

    final place = <String?>[co?.city, co?.province, 'Philippines']
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .join(', ');

    final salary = scorecard?.baseSalary;
    final monthlySalary = salary == null
        ? ''
        : NumberFormat('#,##0', 'en_US').format(salary.toDouble());

    Uint8List? logo;
    try {
      logo = await loadBrandLogoBytes(companyName: co?.name, code: co?.code);
    } catch (_) {
      logo = null;
    }

    return EmploymentContractInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeAddress: _composeAddress(
        emp.addressLine1,
        emp.addressLine2,
        emp.city,
        emp.province,
        emp.zipCode,
      ),
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: _composeAddress(
        co?.addressLine1,
        co?.addressLine2,
        co?.city,
        co?.province,
        co?.zipCode,
      ),
      representativeName: repName,
      representativeRole: repRole,
      place: place,
      dateEntered: today,
      industry: 'Retail Industry',
      position: emp.jobTitle ?? scorecard?.jobTitle ?? '',
      probationStart: probStart,
      probationEnd: probEnd,
      monthlySalary: monthlySalary,
      workHoursPerDay: scorecard?.workHoursPerDay ?? 8,
      workDaysPerWeek: scorecard?.workDaysPerWeek ?? 'Monday to Saturday',
      nonCompeteMonths: 24,
      employerSignatoryName: repName,
      employerSignatoryRole: repRole,
      missionStatement: scorecard?.missionStatement ?? '',
      responsibilities: scorecard == null
          ? const []
          : scorecard.responsibilities
              .map((r) =>
                  ContractResponsibility(area: r.area, tasks: r.tasks))
              .toList(),
      kpis: scorecard == null
          ? const []
          : scorecard.kpis
              .map((k) =>
                  ContractKpi(metric: k.metric, frequency: k.frequency))
              .toList(),
      logoBytes: logo,
    );
  }

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(EmploymentContractInputs inputs) =>
      validateEmploymentContract(inputs);

  @override
  List<Block> build(EmploymentContractInputs i) => const [];
}

/// Joins the individual nullable address parts into a single
/// comma-separated line, skipping any that are null or empty. Unlike
/// `_addressOf` in other templates (which renders a `·`-separated block),
/// the contract recital wants one inline address string.
String _composeAddress(
  String? line1,
  String? line2,
  String? city,
  String? province,
  String? zipCode,
) =>
    [line1, line2, city, province, zipCode]
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .join(', ');
