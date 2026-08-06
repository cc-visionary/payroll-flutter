import 'package:flutter_test/flutter_test.dart';

import 'package:payroll_flutter/data/repositories/employee_document_repository.dart';

void main() {
  group('buildInsertPayload', () {
    test('with templateId set: folds __template_id, does not mutate input', () {
      final original = <String, dynamic>{'foo': 'bar', 'count': 3};
      final payload = buildInsertPayload(
        id: 'ID-1',
        employeeId: 'EMP-1',
        documentType: 'COE',
        title: 'Certificate of Employment',
        fileName: 'coe.pdf',
        generationOptions: original,
        templateId: 'coe',
      );

      expect(payload['id'], 'ID-1');
      expect(payload['employee_id'], 'EMP-1');
      expect(payload['document_type'], 'COE');
      expect(payload['title'], 'Certificate of Employment');
      expect(payload['file_name'], 'coe.pdf');
      expect(payload['status'], 'ISSUED');
      expect(payload['generated_from_template_id'], isNull);

      // Settings-only: no file is stored anymore.
      expect(payload.containsKey('file_path'), isFalse);
      expect(payload.containsKey('file_size_bytes'), isFalse);
      expect(payload.containsKey('mime_type'), isFalse);

      final opts = payload['generation_options'] as Map<String, dynamic>;
      expect(opts['foo'], 'bar');
      expect(opts['count'], 3);
      expect(opts['__template_id'], 'coe');

      // Original map must NOT be mutated.
      expect(original.containsKey('__template_id'), isFalse);
    });

    test('with templateId null: no __template_id key', () {
      final payload = buildInsertPayload(
        id: 'ID-2',
        employeeId: 'EMP-2',
        documentType: 'NDA',
        title: 'Non-Disclosure Agreement',
        fileName: 'nda.pdf',
        generationOptions: const {'a': 1},
        templateId: null,
      );
      final opts = payload['generation_options'] as Map<String, dynamic>;
      expect(opts.containsKey('__template_id'), isFalse);
      expect(opts['a'], 1);
    });
  });

  group('buildUpdatePayload', () {
    test('builds update fields with iso updated_at and folds template id', () {
      final original = <String, dynamic>{'x': 'y'};
      final updatedAt = DateTime.utc(2026, 6, 15, 10, 30);
      final payload = buildUpdatePayload(
        fileName: 'doc.pdf',
        generationOptions: original,
        updatedAt: updatedAt,
        templateId: 'nte',
      );

      expect(payload['file_name'], 'doc.pdf');
      expect(payload['updated_at'], updatedAt.toIso8601String());

      // Settings-only: no file columns on update either.
      expect(payload.containsKey('file_path'), isFalse);
      expect(payload.containsKey('file_size_bytes'), isFalse);
      expect(payload.containsKey('mime_type'), isFalse);

      final opts = payload['generation_options'] as Map<String, dynamic>;
      expect(opts['x'], 'y');
      expect(opts['__template_id'], 'nte');
      expect(original.containsKey('__template_id'), isFalse);

      // Update payload marks the row ISSUED (see dedicated test below) but must
      // NOT carry insert-only keys.
      expect(payload['status'], 'ISSUED');
      expect(payload.containsKey('id'), isFalse);
      expect(payload.containsKey('employee_id'), isFalse);
    });

    test('with templateId null: no __template_id key', () {
      final payload = buildUpdatePayload(
        fileName: 'doc.pdf',
        generationOptions: const {'k': 'v'},
        updatedAt: DateTime.utc(2026, 1, 1),
        templateId: null,
      );
      final opts = payload['generation_options'] as Map<String, dynamic>;
      expect(opts.containsKey('__template_id'), isFalse);
      expect(opts['k'], 'v');
    });

    test(
      'marks the row ISSUED so a DRAFT placeholder becomes the real notice',
      () {
        final payload = buildUpdatePayload(
          fileName: 'notice.pdf',
          generationOptions: const {'foo': 'bar'},
          updatedAt: DateTime.utc(2026, 7, 10),
          templateId: 'salary_adjustment',
        );
        expect(payload['status'], 'ISSUED');
        expect(payload['file_name'], 'notice.pdf');
        expect(
          payload['updated_at'],
          DateTime.utc(2026, 7, 10).toIso8601String(),
        );
        final opts = payload['generation_options'] as Map<String, dynamic>;
        expect(opts['__template_id'], 'salary_adjustment');
      },
    );
  });
}
