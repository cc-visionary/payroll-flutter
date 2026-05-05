import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_filename.dart';

void main() {
  group('filenameForDocument', () {
    test('uses employee number when present', () {
      expect(
        filenameForDocument(
          templateId: 'quitclaim',
          employeeNumber: 'EMP-001',
          employeeId: '4f3a9b2c-0000-0000-0000-000000000000',
          date: DateTime(2026, 5, 5),
        ),
        'Quitclaim_EMP-001_20260505.pdf',
      );
    });

    test('falls back to first 8 of UUID when employee number is null', () {
      expect(
        filenameForDocument(
          templateId: 'coe',
          employeeNumber: null,
          employeeId: '4f3a9b2c-0000-0000-0000-000000000000',
          date: DateTime(2026, 5, 5),
        ),
        'COE_4F3A9B2C_20260505.pdf',
      );
    });

    test('NTE template uses NTE prefix', () {
      expect(
        filenameForDocument(
          templateId: 'nte',
          employeeNumber: 'EMP-002',
          employeeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          date: DateTime(2026, 12, 31),
        ),
        'NTE_EMP-002_20261231.pdf',
      );
    });

    test('unknown template id passes through verbatim', () {
      expect(
        filenameForDocument(
          templateId: 'custom',
          employeeNumber: 'EMP-001',
          employeeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          date: DateTime(2026, 1, 1),
        ),
        'custom_EMP-001_20260101.pdf',
      );
    });
  });
}
