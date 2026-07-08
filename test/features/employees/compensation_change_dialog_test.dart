import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/documents/templates/document_template.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/employees/profile/widgets/compensation_change_dialog.dart';

Employee _emp() => Employee(
      id: 'e1',
      companyId: 'c1',
      employeeNumber: 'EMP-001',
      firstName: 'Maria',
      lastName: 'Santos',
      employmentType: 'REGULAR',
      employmentStatus: 'ACTIVE',
      hireDate: DateTime.utc(2024, 1, 1),
      isRankAndFile: true,
      isOtEligible: true,
      isNdEligible: true,
      isHolidayPayEligible: true,
      taxOnFullEarnings: false,
    );

RoleScorecard _card(String id, String title, Decimal base) => RoleScorecard(
      id: id,
      companyId: 'c1',
      jobTitle: title,
      missionStatement: '',
      responsibilities: const [],
      kpis: const [],
      baseSalary: base,
      wageType: 'MONTHLY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Saturday',
      isActive: true,
      effectiveDate: DateTime.utc(2025, 1, 1),
    );

final _current = _card('rc1', 'Associate', Decimal.fromInt(30000));
final _target = _card('rc2', 'Senior Associate', Decimal.fromInt(40000));

/// Pumps a button that opens the dialog and stores the resolved result.
Future<void> _openDialog(
  WidgetTester tester, {
  required void Function(CompensationChangeRequest?) onResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final r = await showCompensationChangeDialog(
                  context,
                  employee: _emp(),
                  currentCard: _current,
                  allCards: [_current, _target],
                );
                onResult(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('widget', () {
    testWidgets('salary field is hidden for a lateral transfer',
        (tester) async {
      await _openDialog(tester, onResult: (_) {});

      // Default change type shows the new-salary field.
      expect(find.byKey(const Key('newSalaryField')), findsOneWidget);

      // Switch to Lateral Transfer.
      await tester.tap(find.byKey(const Key('changeTypeDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lateral Transfer').last);
      await tester.pumpAndSettle();

      // A lateral transfer keeps the current salary, so the field is gone.
      expect(find.byKey(const Key('newSalaryField')), findsNothing);
    });

    testWidgets(
        'salary increase equal to current shows an error and keeps the dialog '
        'open', (tester) async {
      CompensationChangeRequest? result;
      var resolved = false;
      await _openDialog(tester, onResult: (r) {
        result = r;
        resolved = true;
      });

      // Default type is Salary Increase. Enter a value equal to current salary.
      await tester.enterText(
          find.byKey(const Key('newSalaryField')), '30000');
      await tester.enterText(
          find.byKey(const Key('reasonField')), 'Annual review');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Validation blocks the confirm: dialog is still on screen…
      expect(find.textContaining('Adjust Compensation'), findsOneWidget);
      // …the error surfaces under the salary field…
      expect(find.text('New salary must differ from current'),
          findsOneWidget);
      // …and the future never resolved (dialog did not pop).
      expect(resolved, isFalse);
      expect(result, isNull);
    });

    testWidgets(
        'valid salary increase pops with a populated request', (tester) async {
      CompensationChangeRequest? result;
      await _openDialog(tester, onResult: (r) => result = r);

      // Default type is Salary Increase; the effective date defaults to the
      // 1st of next month — recompute it here for the assertion.
      final now = DateTime.now();
      final expectedEffective = DateTime(now.year, now.month + 1, 1);

      // New salary strictly greater than current (30000).
      await tester.enterText(
          find.byKey(const Key('newSalaryField')), '35000');
      // Change the wage type so its flow-through is actually exercised.
      await tester.tap(find.byKey(const Key('wageTypeDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('reasonField')), 'Annual merit increase');

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Dialog popped and returned a fully-populated request.
      expect(find.textContaining('Adjust Compensation'), findsNothing);
      expect(result, isNotNull);
      expect(result!.changeType, 'SALARY_INCREASE');
      expect(result!.newSalary, Decimal.fromInt(35000));
      expect(result!.newWageType, 'DAILY');
      expect(result!.reason, 'Annual merit increase');
      expect(result!.effectiveDate, expectedEffective);
      // Pay-only change carries no target scorecard.
      expect(result!.newScorecardId, isNull);
    });

    testWidgets(
        'valid lateral transfer pops carrying current salary + target role',
        (tester) async {
      CompensationChangeRequest? result;
      await _openDialog(tester, onResult: (r) => result = r);

      // Switch to Lateral Transfer — hides the salary field, shows the role
      // dropdown.
      await tester.tap(find.byKey(const Key('changeTypeDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lateral Transfer').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('newSalaryField')), findsNothing);

      // Pick the different target role (_target = 'Senior Associate', rc2).
      await tester.tap(find.byKey(const Key('roleDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senior Associate').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('reasonField')), 'Team realignment');

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Adjust Compensation'), findsNothing);
      expect(result, isNotNull);
      expect(result!.changeType, 'LATERAL_TRANSFER');
      expect(result!.newScorecardId, 'rc2');
      // Lateral carries the CURRENT salary (30000) unchanged.
      expect(result!.newSalary, Decimal.fromInt(30000));
      expect(result!.reason, 'Team realignment');
    });
  });

  group('validateCompensationRequest', () {
    final emp = _emp();
    final future = DateTime.now().add(const Duration(days: 30));

    List<ValidationError> run({
      required String changeType,
      required Decimal current,
      required Decimal proposed,
      String? newScorecardId,
      String? currentScorecardId = 'rc1',
      DateTime? effectiveDate,
      String reason = 'Merit adjustment',
    }) {
      return validateCompensationRequest(
        changeType: changeType,
        currentSalary: current,
        newSalary: proposed,
        newWageType: 'MONTHLY',
        newScorecardId: newScorecardId,
        currentScorecardId: currentScorecardId,
        effectiveDate: effectiveDate ?? future,
        reason: reason,
        employee: emp,
      );
    }

    test('salary increase must exceed the current salary', () {
      final errs = run(
        changeType: 'SALARY_INCREASE',
        current: Decimal.fromInt(30000),
        proposed: Decimal.fromInt(25000),
      );
      expect(errs.any((e) => e.field == 'newSalary'), isTrue);
    });

    test('valid salary increase has no errors', () {
      final errs = run(
        changeType: 'SALARY_INCREASE',
        current: Decimal.fromInt(30000),
        proposed: Decimal.fromInt(35000),
      );
      expect(errs, isEmpty);
    });

    test('salary decrease must be below the current salary', () {
      final errs = run(
        changeType: 'SALARY_DECREASE',
        current: Decimal.fromInt(30000),
        proposed: Decimal.fromInt(35000),
      );
      expect(errs.any((e) => e.field == 'newSalary'), isTrue);
    });

    test('demotion must lower the salary', () {
      final errs = run(
        changeType: 'DEMOTION',
        current: Decimal.fromInt(30000),
        proposed: Decimal.fromInt(31000),
        newScorecardId: 'rc2',
      );
      expect(errs.any((e) => e.field == 'newSalary'), isTrue);
    });

    test('lateral transfer must keep salary unchanged', () {
      final errs = run(
        changeType: 'LATERAL_TRANSFER',
        current: Decimal.fromInt(30000),
        proposed: Decimal.fromInt(31000),
        newScorecardId: 'rc2',
      );
      expect(errs.any((e) => e.field == 'newSalary'), isTrue);
    });

    test('role change must target a different scorecard', () {
      final errs = run(
        changeType: 'PROMOTION',
        current: Decimal.fromInt(30000),
        proposed: Decimal.fromInt(40000),
        newScorecardId: 'rc1', // same as current
      );
      expect(errs.any((e) => e.field == 'newRoleScorecardId'), isTrue);
    });

    test('past effective date is rejected', () {
      final errs = run(
        changeType: 'SALARY_INCREASE',
        current: Decimal.fromInt(30000),
        proposed: Decimal.fromInt(35000),
        effectiveDate: DateTime.now().subtract(const Duration(days: 5)),
      );
      expect(errs.any((e) => e.field == 'effectiveDate'), isTrue);
    });

    test('valid promotion has no errors', () {
      final errs = run(
        changeType: 'PROMOTION',
        current: Decimal.fromInt(30000),
        proposed: Decimal.fromInt(45000),
        newScorecardId: 'rc2',
      );
      expect(errs, isEmpty);
    });
  });

  group('field visibility + type mapping', () {
    test('new-salary field hidden only for lateral transfer', () {
      expect(showsNewSalaryField('SALARY_INCREASE'), isTrue);
      expect(showsNewSalaryField('SALARY_DECREASE'), isTrue);
      expect(showsNewSalaryField('PROMOTION'), isTrue);
      expect(showsNewSalaryField('DEMOTION'), isTrue);
      expect(showsNewSalaryField('LATERAL_TRANSFER'), isFalse);
    });

    test('role dropdown shown only for role-change types', () {
      expect(showsRoleDropdown('PROMOTION'), isTrue);
      expect(showsRoleDropdown('LATERAL_TRANSFER'), isTrue);
      expect(showsRoleDropdown('DEMOTION'), isTrue);
      expect(showsRoleDropdown('SALARY_INCREASE'), isFalse);
      expect(showsRoleDropdown('SALARY_DECREASE'), isFalse);
    });

    test('change type maps to the right salary-adjustment type', () {
      expect(changeTypeToAdjustmentType('SALARY_INCREASE'),
          SalaryAdjustmentType.salaryAdjustment);
      expect(changeTypeToAdjustmentType('SALARY_DECREASE'),
          SalaryAdjustmentType.salaryAdjustment);
      expect(changeTypeToAdjustmentType('PROMOTION'),
          SalaryAdjustmentType.promotion);
      expect(changeTypeToAdjustmentType('LATERAL_TRANSFER'),
          SalaryAdjustmentType.lateral);
      expect(changeTypeToAdjustmentType('DEMOTION'),
          SalaryAdjustmentType.demotion);
    });
  });
}
