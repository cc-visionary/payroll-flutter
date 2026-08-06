import 'package:flutter_test/flutter_test.dart';

import 'package:payroll_flutter/features/documents/document_type_mapping.dart';
import 'package:payroll_flutter/features/documents/templates/template_registry.dart';

void main() {
  group('documentTypeForTemplateId', () {
    test('resolves employment_contract', () {
      final info = documentTypeForTemplateId('employment_contract');
      expect(info, isNotNull);
      expect(info!.code, 'EMPLOYMENT_CONTRACT');
      expect(info.title, 'Employment Contract');
    });

    test('spot-checks a few ids', () {
      expect(documentTypeForTemplateId('coe')!.code, 'COE');
      expect(
        documentTypeForTemplateId('coe')!.title,
        'Certificate of Employment',
      );
      expect(documentTypeForTemplateId('nte')!.code, 'NTE');
      expect(documentTypeForTemplateId('non_reg')!.code, 'NON_REGULARIZATION');
      expect(
        documentTypeForTemplateId('non_reg')!.title,
        'Notice of Non-Regularization',
      );
    });

    test('returns null for unknown id', () {
      expect(documentTypeForTemplateId('does_not_exist'), isNull);
    });

    test('every registered template id resolves to a DocumentTypeInfo', () {
      for (final t in kTemplates) {
        expect(
          documentTypeForTemplateId(t.id),
          isNotNull,
          reason: 'No document_type mapping for template id "${t.id}"',
        );
      }
    });
  });
}
