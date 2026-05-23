import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/features/documents/bulk/bulk_generate.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:payroll_flutter/features/documents/templates/coe_template.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_template.dart';
import 'package:payroll_flutter/features/documents/templates/nda_template.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';
import 'package:payroll_flutter/features/documents/templates/nte_template.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_template.dart';

void main() {
  group('supportsBulk flag', () {
    test('true for the four fully-autofill templates', () {
      expect(const CoeTemplate().supportsBulk, isTrue);
      expect(const EmploymentContractTemplate().supportsBulk, isTrue);
      expect(const NdaTemplate().supportsBulk, isTrue);
      expect(const LiabilityWaiverTemplate().supportsBulk, isTrue);
    });

    test('false for the per-employee-input templates', () {
      expect(const NteTemplate().supportsBulk, isFalse);
      expect(const NonRegTemplate().supportsBulk, isFalse);
      expect(const QuitclaimTemplate().supportsBulk, isFalse);
    });
  });

  group('bulkGenerate (COE)', () {
    testWidgets(
        'generates eligible employees, skips gate-blocked + not-found',
        (tester) async {
      final separatedA = _employee(
        id: 'sep-a',
        number: 'EMP-001',
        first: 'Alice',
        status: 'RESIGNED',
      );
      final separatedB = _employee(
        id: 'sep-b',
        number: 'EMP-002',
        first: 'Bob',
        status: 'TERMINATED',
      );
      final active = _employee(
        id: 'act-c',
        number: 'EMP-003',
        first: 'Carol',
        status: 'ACTIVE',
      );
      const co = HiringEntity(
        id: 'c1',
        companyId: 'c1',
        code: 'LUX',
        name: 'LUXIUM TRADING CO.',
        hrManagerName: 'Brixter Del Mundo',
        city: 'Makati',
        province: 'Metro Manila',
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentEmployeeProvider('sep-a').overrideWith((ref) => separatedA),
            documentEmployeeProvider('sep-b').overrideWith((ref) => separatedB),
            documentEmployeeProvider('act-c').overrideWith((ref) => active),
            documentEmployeeProvider('missing').overrideWith((ref) => null),
            hiringEntityByIdProvider('c1').overrideWith((ref) => co),
          ],
          child: Consumer(builder: (_, ref, __) {
            capturedRef = ref;
            return const SizedBox();
          }),
        ),
      );

      final result = await bulkGenerate(
        template: const CoeTemplate(),
        employeeIds: const ['sep-a', 'act-c', 'sep-b', 'missing'],
        ref: capturedRef,
        theme: PdfTheme.testStub(),
      );

      // Two separated employees generated; active is gate-blocked; missing
      // id is not found.
      expect(result.generatedCount, 2);
      expect(result.files.length, 2);
      expect(result.skipped.length, 2);

      // Per-employee PDFs are real PDF bytes.
      for (final f in result.files) {
        expect(String.fromCharCodes(f.bytes.take(4)), '%PDF');
      }
      // Combined PDF is also a real PDF.
      expect(String.fromCharCodes(result.combinedPdf.take(4)), '%PDF');

      // Filenames use the COE prefix + employee number.
      final names = result.files.map((f) => f.filename).toList();
      expect(names.any((n) => n.startsWith('COE_EMP-001_')), isTrue);
      expect(names.any((n) => n.startsWith('COE_EMP-002_')), isTrue);

      // Skip reasons: one gate (active), one not-found.
      final reasons = result.skipped.map((s) => s.reason).toList();
      expect(reasons, contains('Available only after separation.'));
      expect(reasons, contains('Employee not found.'));
    });

    testWidgets('empty employee list yields an empty (but valid) combined PDF',
        (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(builder: (_, ref, __) {
            capturedRef = ref;
            return const SizedBox();
          }),
        ),
      );

      final result = await bulkGenerate(
        template: const CoeTemplate(),
        employeeIds: const [],
        ref: capturedRef,
        theme: PdfTheme.testStub(),
      );

      expect(result.generatedCount, 0);
      expect(result.skipped, isEmpty);
      expect(String.fromCharCodes(result.combinedPdf.take(4)), '%PDF');
    });
  });
}

Employee _employee({
  required String id,
  required String number,
  required String first,
  required String status,
}) =>
    Employee(
      id: id,
      companyId: 'c1',
      employeeNumber: number,
      firstName: first,
      lastName: 'Cruz',
      jobTitle: 'Sales Associate',
      hiringEntityId: 'c1',
      gender: 'Female',
      employmentType: 'REGULAR',
      employmentStatus: status,
      hireDate: DateTime(2020, 1, 1),
      separationDate: DateTime(2024, 6, 30),
      isRankAndFile: true,
      isOtEligible: true,
      isNdEligible: true,
      isHolidayPayEligible: true,
      taxOnFullEarnings: false,
      addressLine1: '123 Mabini St',
      city: 'Makati',
      province: 'Metro Manila',
      zipCode: '1200',
    );
