import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:payroll_flutter/features/documents/templates/penalty_agreement_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/penalty_agreement_template.dart';

void main() {
  group('PenaltyAgreementInputs.fromJson', () {
    final full = PenaltyAgreementInputs(
      employeeId: 'EMP-1',
      employeeFullName: 'Jane Doe',
      employeePosition: 'Analyst',
      companyId: 'CO-1',
      companyName: 'Acme Corp',
      companyAddress: '2 Side St, Manila',
      hrManagerName: 'Brixter',
      penaltyId: 'PEN-1',
      description: 'Damaged company handheld during delivery',
      totalAmount: Decimal.parse('4500.00'),
      effectiveDate: DateTime.utc(2026, 8, 1),
      remarks: 'Deduct starting the August 15 cutoff.',
      installments: [
        PenaltyInstallmentLine(
          number: 1,
          amount: Decimal.parse('1500.00'),
          isDeducted: true,
        ),
        PenaltyInstallmentLine(number: 2, amount: Decimal.parse('1500.00')),
        PenaltyInstallmentLine(number: 3, amount: Decimal.parse('1500.00')),
      ],
      companySignaturePngB64: 'QUJD',
      employeeSignaturePngB64: 'REVG',
    );

    final empty = PenaltyAgreementInputs(
      employeeId: 'EMP-2',
      employeeFullName: 'John Roe',
      companyId: 'CO-2',
      companyName: 'Beta Inc',
      // penaltyId/remarks/signatures null, amount omitted (Decimal.zero),
      // installments default to const []
      effectiveDate: DateTime.utc(2026, 8, 2),
    );

    test('round-trips toJson (full sample)', () {
      expect(
        PenaltyAgreementInputs.fromJson(full.toJson()).toJson(),
        full.toJson(),
      );
    });

    test('round-trips toJson (null/empty sample)', () {
      expect(
        PenaltyAgreementInputs.fromJson(empty.toJson()).toJson(),
        empty.toJson(),
      );
    });

    test('rehydrates the nested installment list with typed fields', () {
      final restored = PenaltyAgreementInputs.fromJson(full.toJson());
      expect(restored.installments.length, 3);
      expect(restored.installments.first.number, 1);
      expect(restored.installments.first.amount, Decimal.parse('1500.00'));
      expect(restored.installments.first.isDeducted, isTrue);
      expect(restored.installments.last.isDeducted, isFalse);
      expect(restored.scheduledTotal, restored.totalAmount);
    });

    test('rehydrates both signature fields', () {
      final restored = PenaltyAgreementInputs.fromJson(full.toJson());
      expect(restored.companySignaturePngB64, 'QUJD');
      expect(restored.employeeSignaturePngB64, 'REVG');
    });

    test('JSON missing the png + nested fields defaults cleanly', () {
      final json = full.toJson();
      json.remove('companySignaturePngB64');
      json.remove('employeeSignaturePngB64');
      json.remove('installments');
      json.remove('penaltyId');
      json.remove('remarks');
      final restored = PenaltyAgreementInputs.fromJson(json);
      expect(restored.companySignaturePngB64, isNull);
      expect(restored.employeeSignaturePngB64, isNull);
      expect(restored.installments, isEmpty);
      expect(restored.penaltyId, isNull);
      expect(restored.remarks, isNull);
      // The surviving fields are untouched.
      expect(restored.totalAmount, Decimal.parse('4500.00'));
      expect(restored.employeeFullName, 'Jane Doe');
    });

    test('toJson omits logoBytes', () {
      expect(full.toJson().containsKey('logoBytes'), isFalse);
    });

    test('toDebugMap redacts both signature PNGs', () {
      final dbg = full.toDebugMap();
      expect(dbg['companySignaturePngB64'], '<png b64, 4 chars>');
      expect(dbg['employeeSignaturePngB64'], '<png b64, 4 chars>');
    });

    test('copyWith clears the nullable penaltyId / remarks', () {
      expect(full.copyWith().penaltyId, 'PEN-1');
      expect(full.copyWith(penaltyId: null).penaltyId, isNull);
      expect(full.copyWith(remarks: null).remarks, isNull);
      expect(full.copyWith().remarks, isNotNull);
    });

    test('rebuilds blocks', () {
      expect(
        const PenaltyAgreementTemplate().build(
          PenaltyAgreementInputs.fromJson(full.toJson()),
        ),
        isNotEmpty,
      );
    });
  });
}
