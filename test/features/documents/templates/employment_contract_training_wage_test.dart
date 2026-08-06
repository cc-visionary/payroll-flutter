import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/emphasis_paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_validate.dart';

void main() {
  EmploymentContractInputs seed({TrainingWage? trainingWage}) =>
      EmploymentContractInputs(
        employeeId: 'e1',
        employeeFullName: 'Jamaica Vidal',
        employeeAddress: '8 Tendido St, Quezon City',
        companyId: 'c1',
        companyName: 'Luxium Trading Co.',
        companyAddress: '908 Alvarado St, Manila',
        representativeName: 'Brixter Del Mundo',
        representativeRole: 'People Manager',
        place: 'Binondo, Metro Manila, Philippines',
        dateEntered: DateTime(2025, 6, 9),
        industry: 'Retail Industry',
        position: 'HR Assistant',
        probationStart: DateTime(2025, 6, 9),
        probationEnd: DateTime(2025, 12, 6),
        monthlySalary: '17,000',
        workHoursPerDay: 8,
        workDaysPerWeek: 'Monday to Saturday',
        nonCompeteMonths: 24,
        employerSignatoryName: 'Brixter Del Mundo',
        employerSignatoryRole: 'People Manager',
        responsibilities: const [
          ContractResponsibility(area: 'Primary', tasks: ['Recruit']),
        ],
        trainingWage: trainingWage,
      );

  // Concatenates all rendered paragraph text (plain + emphasis spans) so we
  // can assert on the contract body as a flat string.
  String renderedText(EmploymentContractInputs i) {
    const t = EmploymentContractTemplate();
    final blocks = t.build(i);
    final buf = StringBuffer();
    for (final b in blocks) {
      if (b is ParagraphBlock) {
        buf.write(b.text);
        buf.write('\n');
      } else if (b is EmphasisParagraphBlock) {
        for (final s in b.spans) {
          buf.write(s.text);
        }
        buf.write('\n');
      }
    }
    return buf.toString();
  }

  group('TrainingWage inputs copyWith', () {
    test('setting trainingWage works', () {
      final i = seed();
      expect(i.trainingWage, isNull);
      final withWage = i.copyWith(
        trainingWage: const TrainingWage(dailyRate: '350', trainingDays: 7),
      );
      expect(withWage.trainingWage, isNotNull);
      expect(withWage.trainingWage!.dailyRate, '350');
      expect(withWage.trainingWage!.trainingDays, 7);
    });

    test('clearing trainingWage via copyWith(trainingWage: null) nulls it', () {
      final i = seed(
        trainingWage: const TrainingWage(dailyRate: '350', trainingDays: 7),
      );
      expect(i.trainingWage, isNotNull);
      final cleared = i.copyWith(trainingWage: null);
      expect(cleared.trainingWage, isNull);
    });

    test('omitting trainingWage in copyWith leaves it unchanged', () {
      final i = seed(
        trainingWage: const TrainingWage(dailyRate: '350', trainingDays: 7),
      );
      final unchanged = i.copyWith(position: 'Cashier');
      expect(unchanged.trainingWage, isNotNull);
      expect(unchanged.trainingWage!.dailyRate, '350');
      expect(unchanged.trainingWage!.trainingDays, 7);
    });
  });

  group('TrainingWage template rendering', () {
    test('renders §5 clause when trainingWage is present', () {
      final text = renderedText(
        seed(
          trainingWage: const TrainingWage(dailyRate: '350', trainingDays: 7),
        ),
      );
      expect(text, contains('training allowance of PHP 350 per day'));
      expect(text, contains('first 7 days'));
    });

    test('omits the clause when trainingWage is null', () {
      final text = renderedText(seed());
      expect(text, isNot(contains('training allowance')));
    });
  });

  group('TrainingWage validation', () {
    test('null trainingWage adds no training errors', () {
      final errs = validateEmploymentContract(seed());
      expect(errs.where((e) => e.field.startsWith('trainingWage')), isEmpty);
    });

    test('valid trainingWage adds no training errors', () {
      final errs = validateEmploymentContract(
        seed(
          trainingWage: const TrainingWage(dailyRate: '350', trainingDays: 7),
        ),
      );
      expect(errs.where((e) => e.field.startsWith('trainingWage')), isEmpty);
    });

    test('zero daily rate flagged', () {
      final errs = validateEmploymentContract(
        seed(trainingWage: const TrainingWage(dailyRate: '0', trainingDays: 7)),
      );
      expect(errs.any((e) => e.field == 'trainingWage.dailyRate'), true);
    });

    test('empty daily rate flagged', () {
      final errs = validateEmploymentContract(
        seed(trainingWage: const TrainingWage(dailyRate: '', trainingDays: 7)),
      );
      expect(errs.any((e) => e.field == 'trainingWage.dailyRate'), true);
    });

    test('zero training days flagged', () {
      final errs = validateEmploymentContract(
        seed(
          trainingWage: const TrainingWage(dailyRate: '350', trainingDays: 0),
        ),
      );
      expect(errs.any((e) => e.field == 'trainingWage.trainingDays'), true);
    });
  });
}
