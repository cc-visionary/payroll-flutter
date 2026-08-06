import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/letterhead_block.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/template_registry.dart';
import 'package:payroll_flutter/features/documents/view/saved_document_renderer.dart';

EmploymentContractInputs _sample() => EmploymentContractInputs(
  employeeId: 'emp-1',
  employeeFullName: 'Arriane Reynido Pabelonia',
  employeeAddress: '1 Mabini St',
  companyId: 'co-1',
  companyName: 'LUXIUM TRADING CO.',
  companyAddress: '1 Ayala Ave',
  representativeName: 'Brixter',
  representativeRole: 'HR Manager',
  place: 'Makati',
  dateEntered: DateTime(2026, 6, 15),
  industry: 'Retail',
  position: 'Sales & Ops Assistant',
  probationStart: DateTime(2026, 6, 15),
  probationEnd: DateTime(2026, 12, 15),
  monthlySalary: '695',
  salaryPeriod: 'day',
  workHoursPerDay: 8,
  workDaysPerWeek: 'Monday to Saturday',
  nonCompeteMonths: 24,
  trainingWage: const TrainingWage(dailyRate: '350', trainingDays: 7),
  employerSignatoryName: 'Brixter Legaspi Del Mundo',
  employerSignatoryRole: 'HR Manager',
  witness1Name: 'Witness One',
  witness1Role: 'Colleague',
  responsibilities: const [
    ContractResponsibility(area: 'Sales', tasks: ['Quote', 'Close']),
  ],
  kpis: const [ContractKpi(metric: 'Revenue', frequency: 'Monthly')],
  missionStatement: 'Drive sales.',
);

void main() {
  group('EmploymentContractInputs.fromJson', () {
    test(
      'round-trips toJson, including nested lists, training wage and dates',
      () {
        final original = _sample();
        final restored = EmploymentContractInputs.fromJson(original.toJson());

        // The JSON snapshot is the contract; a full round-trip must be identical.
        expect(restored.toJson(), original.toJson());
        // Spot-check the typed (non-string) fields survived deserialization.
        expect(restored.workHoursPerDay, 8);
        expect(restored.nonCompeteMonths, 24);
        expect(restored.trainingWage?.dailyRate, '350');
        expect(restored.trainingWage?.trainingDays, 7);
        expect(restored.responsibilities.single.tasks, ['Quote', 'Close']);
        expect(restored.kpis.single.metric, 'Revenue');
        expect(restored.probationEnd, DateTime(2026, 12, 15));
      },
    );

    test('handles null training wage and empty nested lists', () {
      final original = _sample().copyWith(
        trainingWage: null,
        responsibilities: const [],
        kpis: const [],
      );
      final restored = EmploymentContractInputs.fromJson(original.toJson());
      expect(restored.trainingWage, isNull);
      expect(restored.responsibilities, isEmpty);
      expect(restored.kpis, isEmpty);
    });
  });

  group('blocksForSavedDocument', () {
    test(
      'rebuilds employment-contract blocks from saved generation_options',
      () {
        final options = {
          ..._sample().toJson(),
          '__template_id': 'employment_contract',
        };
        final blocks = blocksForSavedDocument(options);
        expect(blocks, isNotEmpty);
      },
    );

    test('throws UnsupportedSavedDocument for an unknown template id', () {
      expect(
        () =>
            blocksForSavedDocument(const {'__template_id': 'totally_unknown'}),
        throwsA(isA<UnsupportedSavedDocument>()),
      );
    });
  });

  group('every registered template is re-renderable', () {
    test('kReRenderableSavedTemplateIds covers all kTemplates ids', () {
      final ids = kTemplates.map((t) => t.id).toSet();
      final missing = ids.difference(kReRenderableSavedTemplateIds);
      expect(
        missing,
        isEmpty,
        reason: 'Templates with no saved-settings re-render path: $missing',
      );
    });

    for (final t in kTemplates) {
      test(
        'rebuilds ${t.id} blocks from emptyInputs via the central switch',
        () {
          final options = {...t.emptyInputs().toJson(), '__template_id': t.id};
          expect(blocksForSavedDocument(options), isNotEmpty);
        },
      );
    }
  });

  group('logoBytes propagation', () {
    test('salary_adjustment saved render carries the passed logo', () {
      final opts = {
        '__template_id': 'salary_adjustment',
        'employeeId': 'e',
        'employeeFullName': 'Bob',
        'companyId': 'c',
        'companyName': 'GameCove',
        'companyAddress': '1 St',
        'oldSalary': '1',
        'newSalary': '2',
        'effectiveDate': '2026-07-01T00:00:00.000',
        'issueDate': '2026-06-05T00:00:00.000',
        'type': 'salaryAdjustment',
      };
      final blocks = blocksForSavedDocument(
        opts,
        logoBytes: Uint8List.fromList(const [137, 80, 78, 71]),
      );
      final head = blocks.whereType<LetterheadBlock>().toList();
      expect(head, isNotEmpty);
      expect(head.first.logoBytes, isNotNull);
    });
  });
}
