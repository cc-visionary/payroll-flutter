import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/employees/profile/tabs/document_status.dart';
import 'package:payroll_flutter/features/employees/profile/widgets/info_card.dart'
    show ChipTone;

void main() {
  group('documentStatusTone', () {
    test('ISSUED and SIGNED are positive (success)', () {
      expect(documentStatusTone('ISSUED'), ChipTone.success);
      expect(documentStatusTone('SIGNED'), ChipTone.success);
    });

    test('DRAFT and PENDING_APPROVAL are amber (warning)', () {
      expect(documentStatusTone('DRAFT'), ChipTone.warning);
      expect(documentStatusTone('PENDING_APPROVAL'), ChipTone.warning);
    });

    test('VOIDED is red (danger)', () {
      expect(documentStatusTone('VOIDED'), ChipTone.danger);
    });

    test('SUPERSEDED and EXPIRED are muted (neutral)', () {
      expect(documentStatusTone('SUPERSEDED'), ChipTone.neutral);
      expect(documentStatusTone('EXPIRED'), ChipTone.neutral);
    });

    test('is case-insensitive', () {
      expect(documentStatusTone('issued'), ChipTone.success);
      expect(documentStatusTone('voided'), ChipTone.danger);
    });

    test('null and unknown fall back to neutral', () {
      expect(documentStatusTone(null), ChipTone.neutral);
      expect(documentStatusTone(''), ChipTone.neutral);
      expect(documentStatusTone('SOMETHING_ELSE'), ChipTone.neutral);
    });
  });

  group('documentStatusLabel', () {
    test('maps known statuses to friendly labels', () {
      expect(documentStatusLabel('ISSUED'), 'Issued');
      expect(documentStatusLabel('SIGNED'), 'Signed');
      expect(documentStatusLabel('DRAFT'), 'Draft');
      expect(documentStatusLabel('PENDING_APPROVAL'), 'Pending Approval');
      expect(documentStatusLabel('VOIDED'), 'Voided');
      expect(documentStatusLabel('SUPERSEDED'), 'Superseded');
      expect(documentStatusLabel('EXPIRED'), 'Expired');
    });

    test('null/empty becomes "Unknown"', () {
      expect(documentStatusLabel(null), 'Unknown');
      expect(documentStatusLabel('   '), 'Unknown');
    });

    test('unmapped statuses are title-cased from the raw string', () {
      expect(documentStatusLabel('SOME_NEW_STATE'), 'Some New State');
      expect(documentStatusLabel('archived'), 'Archived');
    });
  });

  group('documentHasFile', () {
    test('true when file_path is a non-empty string', () {
      expect(documentHasFile({'file_path': 'emp-1/doc-1.pdf'}), isTrue);
    });

    test('false when file_path is null', () {
      expect(documentHasFile({'file_path': null}), isFalse);
    });

    test('false when file_path is missing', () {
      expect(documentHasFile(<String, dynamic>{}), isFalse);
    });

    test('false when file_path is blank/whitespace', () {
      expect(documentHasFile({'file_path': ''}), isFalse);
      expect(documentHasFile({'file_path': '   '}), isFalse);
    });
  });
}
