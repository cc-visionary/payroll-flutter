import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workflows/generate_url.dart';

void main() {
  group('buildGenerateDocumentUrl', () {
    test('employee only (separation-style step with no linked ids)', () {
      expect(
        buildGenerateDocumentUrl(templateId: 'quitclaim', employeeId: 'E1'),
        '/documents/generate/quitclaim?employeeId=E1',
      );
    });

    test('appends documentId when the step has a pre-inserted DRAFT', () {
      expect(
        buildGenerateDocumentUrl(
          templateId: 'quitclaim',
          employeeId: 'E1',
          documentId: 'D1',
        ),
        '/documents/generate/quitclaim?employeeId=E1&documentId=D1',
      );
    });

    test('appends changeId for compensation workflows', () {
      expect(
        buildGenerateDocumentUrl(
          templateId: 'salary_adjustment',
          employeeId: 'E1',
          changeId: 'C1',
        ),
        '/documents/generate/salary_adjustment?employeeId=E1&changeId=C1',
      );
    });

    test('appends both, changeId before documentId', () {
      expect(
        buildGenerateDocumentUrl(
          templateId: 'salary_adjustment',
          employeeId: 'E1',
          changeId: 'C1',
          documentId: 'D1',
        ),
        '/documents/generate/salary_adjustment?employeeId=E1&changeId=C1&documentId=D1',
      );
    });
  });
}
