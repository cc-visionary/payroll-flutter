import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:payroll_flutter/features/documents/templates/coe_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nda_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';

void main() {
  final logo = Uint8List.fromList([1, 2, 3]);

  group('EmploymentContractInputs.toJson', () {
    test('serializes all fields, excludes logoBytes, nests responsibilities/kpis',
        () {
      final dateEntered = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final probationStart = DateTime.utc(2026, 1, 10);
      final probationEnd = DateTime.utc(2026, 7, 10);
      final inputs = EmploymentContractInputs(
        employeeId: 'EMP-1',
        applicantId: null,
        employeeFullName: 'Jane Doe',
        employeeAddress: '1 Main St',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: '2 Side St',
        representativeName: 'Rep Name',
        representativeRole: 'Rep Role',
        place: 'Manila',
        dateEntered: dateEntered,
        industry: 'Retail',
        position: 'Clerk',
        probationStart: probationStart,
        probationEnd: probationEnd,
        monthlySalary: '20000',
        salaryPeriod: 'month',
        workHoursPerDay: 8,
        workDaysPerWeek: '5',
        nonCompeteMonths: 12,
        trainingWage: const TrainingWage(dailyRate: '350', trainingDays: 7),
        employerSignatoryName: 'Sig Name',
        employerSignatoryRole: 'Sig Role',
        witness1Name: 'W1',
        witness1Role: 'W1R',
        witness2Name: 'W2',
        witness2Role: 'W2R',
        missionStatement: 'Mission',
        responsibilities: const [
          ContractResponsibility(area: 'Sales', tasks: ['t1', 't2']),
        ],
        kpis: const [
          ContractKpi(metric: 'Revenue', frequency: 'Monthly'),
        ],
        logoBytes: logo,
      );

      final json = inputs.toJson();

      expect(json['employeeId'], 'EMP-1');
      expect(json['applicantId'], isNull);
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeeAddress'], '1 Main St');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], '2 Side St');
      expect(json['representativeName'], 'Rep Name');
      expect(json['representativeRole'], 'Rep Role');
      expect(json['place'], 'Manila');
      expect(json['dateEntered'], dateEntered.toIso8601String());
      expect(json['industry'], 'Retail');
      expect(json['position'], 'Clerk');
      expect(json['probationStart'], probationStart.toIso8601String());
      expect(json['probationEnd'], probationEnd.toIso8601String());
      expect(json['monthlySalary'], '20000');
      expect(json['salaryPeriod'], 'month');
      expect(json['workHoursPerDay'], 8);
      expect(json['workDaysPerWeek'], '5');
      expect(json['nonCompeteMonths'], 12);
      expect(json['trainingWage'], {'dailyRate': '350', 'trainingDays': 7});
      expect(json['employerSignatoryName'], 'Sig Name');
      expect(json['employerSignatoryRole'], 'Sig Role');
      expect(json['witness1Name'], 'W1');
      expect(json['witness1Role'], 'W1R');
      expect(json['witness2Name'], 'W2');
      expect(json['witness2Role'], 'W2R');
      expect(json['missionStatement'], 'Mission');

      final resp = json['responsibilities'] as List;
      expect(resp.length, 1);
      expect(resp.first, isA<Map>());
      expect((resp.first as Map)['area'], 'Sales');
      expect((resp.first as Map)['tasks'], ['t1', 't2']);

      final kpis = json['kpis'] as List;
      expect(kpis.length, 1);
      expect((kpis.first as Map)['metric'], 'Revenue');
      expect((kpis.first as Map)['frequency'], 'Monthly');

      expect(json.containsKey('logoBytes'), isFalse);
    });

    test('applicant-mode object serializes (assert passes)', () {
      final inputs = EmploymentContractInputs(
        employeeId: null,
        applicantId: 'APP-1',
        employeeFullName: 'App Name',
        employeeAddress: 'addr',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr2',
        representativeName: 'Rep',
        representativeRole: 'Role',
        place: 'Manila',
        dateEntered: DateTime.utc(2026, 1, 1),
        industry: 'Retail',
        position: 'Clerk',
        monthlySalary: '20000',
        workHoursPerDay: 8,
        workDaysPerWeek: '5',
        nonCompeteMonths: 12,
        employerSignatoryName: 'Sig',
        employerSignatoryRole: 'SigRole',
      );
      final json = inputs.toJson();
      expect(json['employeeId'], isNull);
      expect(json['applicantId'], 'APP-1');
      expect(json['trainingWage'], isNull);
      expect((json['responsibilities'] as List), isEmpty);
    });
  });

  group('CoeInputs.toJson', () {
    test('serializes all fields, excludes logoBytes', () {
      final dateStart = DateTime.utc(2024, 1, 1);
      final dateEnd = DateTime.utc(2025, 1, 1);
      final dateIssued = DateTime.utc(2026, 1, 1);
      final inputs = CoeInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeLastName: 'Doe',
        employeeHonorific: 'Ms.',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr',
        hrManagerName: 'HR Mgr',
        position: 'Clerk',
        place: 'Manila',
        dateStart: dateStart,
        dateEnd: dateEnd,
        dateIssued: dateIssued,
        logoBytes: logo,
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeeLastName'], 'Doe');
      expect(json['employeeHonorific'], 'Ms.');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'addr');
      expect(json['hrManagerName'], 'HR Mgr');
      expect(json['position'], 'Clerk');
      expect(json['place'], 'Manila');
      expect(json['dateStart'], dateStart.toIso8601String());
      expect(json['dateEnd'], dateEnd.toIso8601String());
      expect(json['dateIssued'], dateIssued.toIso8601String());
      expect(json.containsKey('logoBytes'), isFalse);
    });
  });

  group('QuitclaimInputs.toJson', () {
    test('serializes all fields incl Decimal as string', () {
      final dateTerminated = DateTime.utc(2026, 1, 1);
      final dateSigned = DateTime.utc(2026, 2, 1);
      final amount = Decimal.parse('12345.67');
      final inputs = QuitclaimInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeAddress: 'addr',
        civilStatus: 'married',
        companyId: 'CO-1',
        companyName: 'Acme',
        finalPayAmount: amount,
        dateTerminated: dateTerminated,
        dateSigned: dateSigned,
        placeSigned: 'Manila',
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeeAddress'], 'addr');
      expect(json['civilStatus'], 'married');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['finalPayAmount'], amount.toString());
      expect(json['dateTerminated'], dateTerminated.toIso8601String());
      expect(json['dateSigned'], dateSigned.toIso8601String());
      expect(json['placeSigned'], 'Manila');
    });
  });

  group('NdaInputs.toJson', () {
    test('serializes all fields', () {
      final effectiveDate = DateTime.utc(2026, 3, 1);
      final inputs = NdaInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeePosition: 'Clerk',
        employeeHomeAddress: 'addr',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'co addr',
        effectiveDate: effectiveDate,
        authorizedSignatoryName: 'Sig',
        authorizedSignatoryRole: 'Role',
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeePosition'], 'Clerk');
      expect(json['employeeHomeAddress'], 'addr');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'co addr');
      expect(json['effectiveDate'], effectiveDate.toIso8601String());
      expect(json['authorizedSignatoryName'], 'Sig');
      expect(json['authorizedSignatoryRole'], 'Role');
    });
  });

  group('LiabilityWaiverInputs.toJson', () {
    test('serializes all fields', () {
      final dateOfEmployment = DateTime.utc(2024, 1, 1);
      final outingDate = DateTime.utc(2026, 6, 1);
      final dateSigned = DateTime.utc(2026, 6, 2);
      final inputs = LiabilityWaiverInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeAddress: 'addr',
        companyId: 'CO-1',
        companyName: 'Acme',
        dateOfEmployment: dateOfEmployment,
        outingDate: outingDate,
        outingLocation: 'Beach',
        dateSigned: dateSigned,
        signingPlace: 'Manila',
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeeAddress'], 'addr');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['dateOfEmployment'], dateOfEmployment.toIso8601String());
      expect(json['outingDate'], outingDate.toIso8601String());
      expect(json['outingLocation'], 'Beach');
      expect(json['dateSigned'], dateSigned.toIso8601String());
      expect(json['signingPlace'], 'Manila');
    });
  });

  group('FinalPayInputs.toJson', () {
    test('serializes all fields incl 5 Decimals and bool locks', () {
      final hireDate = DateTime.utc(2024, 1, 1);
      final sepDate = DateTime.utc(2026, 1, 1);
      final computedAsOf = DateTime.utc(2026, 1, 2);
      final releaseDate = DateTime.utc(2026, 1, 10);
      final lastNetPay = Decimal.parse('1000.00');
      final thirteenth = Decimal.parse('2000.00');
      final unusedLeave = Decimal.parse('300.00');
      final cashAdvance = Decimal.parse('150.00');
      final otherDed = Decimal.parse('50.00');
      final inputs = FinalPayInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeePosition: 'Clerk',
        employeeHireDate: hireDate,
        employeeSeparationDate: sepDate,
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr',
        hrManagerName: 'HR Mgr',
        lastNetPay: lastNetPay,
        thirteenthMonth: thirteenth,
        unusedLeaveConversion: unusedLeave,
        outstandingCashAdvance: cashAdvance,
        otherDeductions: otherDed,
        otherDeductionsLabel: 'Misc',
        lastNetPayLocked: true,
        thirteenthMonthLocked: true,
        unusedLeaveConversionLocked: true,
        outstandingCashAdvanceLocked: true,
        computedAsOf: computedAsOf,
        releaseDate: releaseDate,
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeePosition'], 'Clerk');
      expect(json['employeeHireDate'], hireDate.toIso8601String());
      expect(json['employeeSeparationDate'], sepDate.toIso8601String());
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'addr');
      expect(json['hrManagerName'], 'HR Mgr');
      expect(json['lastNetPay'], lastNetPay.toString());
      expect(json['thirteenthMonth'], thirteenth.toString());
      expect(json['unusedLeaveConversion'], unusedLeave.toString());
      expect(json['outstandingCashAdvance'], cashAdvance.toString());
      expect(json['otherDeductions'], otherDed.toString());
      expect(json['otherDeductionsLabel'], 'Misc');
      expect(json['lastNetPayLocked'], true);
      expect(json['thirteenthMonthLocked'], true);
      expect(json['unusedLeaveConversionLocked'], true);
      expect(json['outstandingCashAdvanceLocked'], true);
      expect(json['computedAsOf'], computedAsOf.toIso8601String());
      expect(json['releaseDate'], releaseDate.toIso8601String());
    });
  });

  group('SalaryAdjustmentInputs.toJson', () {
    test('serializes all fields incl enum name and Decimals', () {
      final effectiveDate = DateTime.utc(2026, 1, 1);
      final issueDate = DateTime.utc(2026, 1, 2);
      final oldSalary = Decimal.parse('1000.00');
      final newSalary = Decimal.parse('1500.00');
      final inputs = SalaryAdjustmentInputs(
        type: SalaryAdjustmentType.promotion,
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeePosition: 'Clerk',
        employeeGender: 'FEMALE',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr',
        hrManagerName: 'HR Mgr',
        oldRoleScorecardId: 'OLD-SC',
        newRoleScorecardId: 'NEW-SC',
        oldPosition: 'Clerk',
        newPosition: 'Manager',
        oldSalary: oldSalary,
        newSalary: newSalary,
        salaryPeriod: 'MONTHLY',
        effectiveDate: effectiveDate,
        issueDate: issueDate,
        reason: 'Great work',
      );
      final json = inputs.toJson();
      expect(json['type'], 'promotion');
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeePosition'], 'Clerk');
      expect(json['employeeGender'], 'FEMALE');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'addr');
      expect(json['hrManagerName'], 'HR Mgr');
      expect(json['oldRoleScorecardId'], 'OLD-SC');
      expect(json['newRoleScorecardId'], 'NEW-SC');
      expect(json['oldPosition'], 'Clerk');
      expect(json['newPosition'], 'Manager');
      expect(json['oldSalary'], oldSalary.toString());
      expect(json['newSalary'], newSalary.toString());
      expect(json['salaryPeriod'], 'MONTHLY');
      expect(json['effectiveDate'], effectiveDate.toIso8601String());
      expect(json['issueDate'], issueDate.toIso8601String());
      expect(json['reason'], 'Great work');
    });
  });

  group('NodInputs.toJson', () {
    test('serializes all fields incl enum name, charges/findings are Strings',
        () {
      final nteDate = DateTime.utc(2026, 1, 1);
      final effectiveDate = DateTime.utc(2026, 2, 1);
      final issueDate = DateTime.utc(2026, 1, 15);
      final inputs = NodInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeePosition: 'Clerk',
        employeeGender: 'FEMALE',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr',
        hrManagerName: 'HR Mgr',
        linkedNteDocumentId: 'NTE-1',
        nteDate: nteDate,
        charges: 'Tardiness',
        employeeResponseSummary: 'Sorry',
        findings: 'Guilty',
        decision: NodDecision.suspension,
        suspensionDays: 3,
        effectiveDate: effectiveDate,
        issueDate: issueDate,
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeePosition'], 'Clerk');
      expect(json['employeeGender'], 'FEMALE');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'addr');
      expect(json['hrManagerName'], 'HR Mgr');
      expect(json['linkedNteDocumentId'], 'NTE-1');
      expect(json['nteDate'], nteDate.toIso8601String());
      expect(json['charges'], 'Tardiness');
      expect(json['employeeResponseSummary'], 'Sorry');
      expect(json['findings'], 'Guilty');
      expect(json['decision'], 'suspension');
      expect(json['suspensionDays'], 3);
      expect(json['effectiveDate'], effectiveDate.toIso8601String());
      expect(json['issueDate'], issueDate.toIso8601String());
    });

    test('excludes attachmentBytes and attachmentCaption', () {
      final inputs = NodInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        companyId: 'CO-1',
        companyName: 'Acme',
        effectiveDate: DateTime.utc(2026, 2, 1),
        issueDate: DateTime.utc(2026, 1, 15),
        attachmentBytes: logo,
        attachmentCaption: 'Photo of damaged unit',
      );
      final json = inputs.toJson();
      expect(json.containsKey('attachmentBytes'), isFalse);
      expect(json.containsKey('attachmentCaption'), isFalse);
    });

    test('copyWith sets and clears the attachment', () {
      final base = NodInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        companyId: 'CO-1',
        companyName: 'Acme',
        effectiveDate: DateTime.utc(2026, 2, 1),
        issueDate: DateTime.utc(2026, 1, 15),
      );
      final withImg =
          base.copyWith(attachmentBytes: logo, attachmentCaption: 'cap');
      expect(withImg.attachmentBytes, logo);
      expect(withImg.attachmentCaption, 'cap');
      final cleared =
          withImg.copyWith(attachmentBytes: null, attachmentCaption: null);
      expect(cleared.attachmentBytes, isNull);
      expect(cleared.attachmentCaption, isNull);
      expect(withImg.copyWith().attachmentBytes, logo);
    });
  });

  group('NonRegInputs.toJson', () {
    test('serializes all fields, nested findings + subFindings, excludes logo',
        () {
      final dateIssued = DateTime.utc(2026, 1, 1);
      final probStart = DateTime.utc(2025, 7, 1);
      final probEnd = DateTime.utc(2026, 1, 1);
      final effEnd = DateTime.utc(2026, 1, 5);
      final inputs = NonRegInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeLastName: 'Doe',
        employeePosition: 'Clerk',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr',
        hrManagerName: 'HR Mgr',
        dateIssued: dateIssued,
        probationaryStart: probStart,
        probationaryEnd: probEnd,
        effectiveEndDate: effEnd,
        salutationName: 'Jane',
        noteOnScope: 'scope note',
        findings: const [
          FindingSection(
            title: 'Attendance',
            standard: 'Be on time',
            finding: 'Often late',
            subFindings: [
              SubFinding(title: 'Late 1', body: 'b1'),
              SubFinding(title: 'Late 2', body: 'b2'),
            ],
          ),
        ],
        witnessName: 'Witness',
        logoBytes: logo,
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeeLastName'], 'Doe');
      expect(json['employeePosition'], 'Clerk');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'addr');
      expect(json['hrManagerName'], 'HR Mgr');
      expect(json['dateIssued'], dateIssued.toIso8601String());
      expect(json['probationaryStart'], probStart.toIso8601String());
      expect(json['probationaryEnd'], probEnd.toIso8601String());
      expect(json['effectiveEndDate'], effEnd.toIso8601String());
      expect(json['salutationName'], 'Jane');
      expect(json['noteOnScope'], 'scope note');
      expect(json['witnessName'], 'Witness');

      final findings = json['findings'] as List;
      expect(findings.length, 1);
      final f0 = findings.first as Map;
      expect(f0['title'], 'Attendance');
      expect(f0['standard'], 'Be on time');
      expect(f0['finding'], 'Often late');
      final subs = f0['subFindings'] as List;
      expect(subs.length, 2);
      expect((subs.first as Map)['title'], 'Late 1');
      expect((subs.first as Map)['body'], 'b1');

      expect(json.containsKey('logoBytes'), isFalse);
    });
  });

  group('NteInputs.toJson', () {
    test('serializes all fields, charge body is a List (Delta), excludes logo',
        () {
      final dateIssued = DateTime.utc(2026, 1, 1);
      final responseDeadline = DateTime.utc(2026, 1, 6);
      final body = Delta()..insert('hello\n');
      final inputs = NteInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeFirstName: 'Jane',
        employeeLastName: 'Doe',
        employeeHonorific: 'Ms.',
        employeePosition: 'Clerk',
        employeeDepartment: 'Ops',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr',
        hrManagerName: 'HR Mgr',
        dateIssued: dateIssued,
        responseDeadline: responseDeadline,
        subjectSubtopic: 'Tardiness',
        charges: [NteCharge(title: 'Charge 1', body: body)],
        applicableViolations: const ['V1', 'V2'],
        logoBytes: logo,
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeeFirstName'], 'Jane');
      expect(json['employeeLastName'], 'Doe');
      expect(json['employeeHonorific'], 'Ms.');
      expect(json['employeePosition'], 'Clerk');
      expect(json['employeeDepartment'], 'Ops');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'addr');
      expect(json['hrManagerName'], 'HR Mgr');
      expect(json['dateIssued'], dateIssued.toIso8601String());
      expect(json['responseDeadline'], responseDeadline.toIso8601String());
      expect(json['subjectSubtopic'], 'Tardiness');

      final charges = json['charges'] as List;
      expect(charges.length, 1);
      final c0 = charges.first as Map;
      expect(c0['title'], 'Charge 1');
      expect(c0['body'], isA<List>());

      expect(json['applicableViolations'], ['V1', 'V2']);
      expect(json.containsKey('logoBytes'), isFalse);
    });

    test('excludes attachmentBytes and attachmentCaption', () {
      final inputs = NteInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeFirstName: 'Jane',
        employeeLastName: 'Doe',
        employeePosition: 'Clerk',
        employeeDepartment: 'Ops',
        companyId: 'CO-1',
        companyName: 'Acme',
        dateIssued: DateTime.utc(2026, 1, 1),
        responseDeadline: DateTime.utc(2026, 1, 6),
        subjectSubtopic: '',
        charges: const [],
        applicableViolations: const [],
        attachmentBytes: logo,
        attachmentCaption: 'CCTV still',
      );
      final json = inputs.toJson();
      expect(json.containsKey('attachmentBytes'), isFalse);
      expect(json.containsKey('attachmentCaption'), isFalse);
    });

    test('copyWith sets and clears the attachment', () {
      final base = NteInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeFirstName: 'Jane',
        employeeLastName: 'Doe',
        employeePosition: 'Clerk',
        employeeDepartment: 'Ops',
        companyId: 'CO-1',
        companyName: 'Acme',
        dateIssued: DateTime.utc(2026, 1, 1),
        responseDeadline: DateTime.utc(2026, 1, 6),
        subjectSubtopic: '',
        charges: const [],
        applicableViolations: const [],
      );
      final withImg =
          base.copyWith(attachmentBytes: logo, attachmentCaption: 'cap');
      expect(withImg.attachmentBytes, logo);
      expect(withImg.attachmentCaption, 'cap');
      final cleared =
          withImg.copyWith(attachmentBytes: null, attachmentCaption: null);
      expect(cleared.attachmentBytes, isNull);
      expect(cleared.attachmentCaption, isNull);
    });
  });

  group('RegularizationInputs.toJson', () {
    test('serializes all fields incl Decimal', () {
      final hireDate = DateTime.utc(2025, 7, 1);
      final regDate = DateTime.utc(2026, 1, 1);
      final issueDate = DateTime.utc(2026, 1, 2);
      final baseSalary = Decimal.parse('25000.00');
      final inputs = RegularizationInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeePosition: 'Clerk',
        employeeGender: 'FEMALE',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr',
        hrManagerName: 'HR Mgr',
        hireDate: hireDate,
        regularizationDate: regDate,
        baseSalary: baseSalary,
        salaryPeriod: 'MONTHLY',
        issueDate: issueDate,
        performanceSummary: 'Excellent',
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeePosition'], 'Clerk');
      expect(json['employeeGender'], 'FEMALE');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'addr');
      expect(json['hrManagerName'], 'HR Mgr');
      expect(json['hireDate'], hireDate.toIso8601String());
      expect(json['regularizationDate'], regDate.toIso8601String());
      expect(json['baseSalary'], baseSalary.toString());
      expect(json['salaryPeriod'], 'MONTHLY');
      expect(json['issueDate'], issueDate.toIso8601String());
      expect(json['performanceSummary'], 'Excellent');
    });
  });

  group('ResignationAcceptanceInputs.toJson', () {
    test('serializes all fields incl bools', () {
      final resignationDate = DateTime.utc(2026, 1, 1);
      final lastDay = DateTime.utc(2026, 1, 31);
      final issueDate = DateTime.utc(2026, 1, 2);
      final inputs = ResignationAcceptanceInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeePosition: 'Clerk',
        employeeGender: 'FEMALE',
        companyId: 'CO-1',
        companyName: 'Acme',
        companyAddress: 'addr',
        hrManagerName: 'HR Mgr',
        resignationDate: resignationDate,
        lastDayOfWork: lastDay,
        issueDate: issueDate,
        turnoverInstructions: 'Turn over stuff',
        includeClearanceMention: false,
        includeFinalPayMention: false,
      );
      final json = inputs.toJson();
      expect(json['employeeId'], 'EMP-1');
      expect(json['employeeFullName'], 'Jane Doe');
      expect(json['employeePosition'], 'Clerk');
      expect(json['employeeGender'], 'FEMALE');
      expect(json['companyId'], 'CO-1');
      expect(json['companyName'], 'Acme');
      expect(json['companyAddress'], 'addr');
      expect(json['hrManagerName'], 'HR Mgr');
      expect(json['resignationDate'], resignationDate.toIso8601String());
      expect(json['lastDayOfWork'], lastDay.toIso8601String());
      expect(json['issueDate'], issueDate.toIso8601String());
      expect(json['turnoverInstructions'], 'Turn over stuff');
      expect(json['includeClearanceMention'], false);
      expect(json['includeFinalPayMention'], false);
    });
  });
}
