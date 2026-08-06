import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/company_header_block.dart';
import 'package:payroll_flutter/features/documents/blocks/letter_meta_block.dart';

void main() {
  test('CompanyHeaderBlock stores name and address', () {
    const b = CompanyHeaderBlock(
      name: 'LUXIUM TRADING CO.',
      address: '908 Alvarado Street, Binondo Manila, 1006 Metro Manila',
    );
    expect(b.name, 'LUXIUM TRADING CO.');
    expect(b.address, isNotNull);
  });

  test('LetterMetaBlock stores all sections', () {
    final block = LetterMetaBlock(
      date: DateTime(2026, 4, 27),
      to: const LetterParty(
        name: 'Orlando Del Prado',
        subtitle: 'Sales Associate',
      ),
      from: const LetterParty(
        name: 'Brixter Del Mundo',
        subtitle: 'HR Manager',
      ),
      subject: 'Preventive Suspension Pending Investigation',
    );
    expect(block.subject, 'Preventive Suspension Pending Investigation');
  });

  test('blocks render without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const CompanyHeaderBlock(name: 'X', address: 'Y').toPdf(theme),
      returnsNormally,
    );
    expect(
      () => LetterMetaBlock(
        date: DateTime(2026, 1, 1),
        to: const LetterParty(name: 'A'),
        from: const LetterParty(name: 'B'),
        subject: 'S',
      ).toPdf(theme),
      returnsNormally,
    );
  });

  test('LetterMetaBlock stores optional position', () {
    final block = LetterMetaBlock(
      date: DateTime(2025, 12, 3),
      to: const LetterParty(name: 'Jamaica Phomela Litang Vidal'),
      position: 'Human Resources and Administrative Assistant',
      from: const LetterParty(name: 'Brixter Del Mundo'),
      subject: 'NOTICE OF NON-REGULARIZATION',
    );
    expect(block.position, 'Human Resources and Administrative Assistant');
  });

  test('LetterMetaBlock renders with position without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => LetterMetaBlock(
        date: DateTime(2025, 12, 3),
        to: const LetterParty(name: 'A'),
        position: 'Some Position',
        from: const LetterParty(name: 'B'),
        subject: 'S',
      ).toPdf(theme),
      returnsNormally,
    );
  });

  test('LetterMetaBlock renders with null subject without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => LetterMetaBlock(
        date: DateTime(2025, 12, 3),
        to: const LetterParty(name: 'A'),
        from: const LetterParty(name: 'B'),
        subject: null,
      ).toPdf(theme),
      returnsNormally,
    );
  });

  test('LetterMetaBlock honors showDividers flag', () {
    final theme = PdfTheme.testStub();
    expect(
      () => LetterMetaBlock(
        date: DateTime(2025, 12, 3),
        to: const LetterParty(name: 'A'),
        from: const LetterParty(name: 'B'),
        subject: null,
        showDividers: false,
      ).toPdf(theme),
      returnsNormally,
    );
    // showDividers default is true; verify constructor stores both values.
    final dividers = LetterMetaBlock(
      date: DateTime(2025, 12, 3),
      to: const LetterParty(name: 'A'),
      from: const LetterParty(name: 'B'),
      subject: 'S',
    );
    expect(dividers.showDividers, true);
    final noDividers = LetterMetaBlock(
      date: DateTime(2025, 12, 3),
      to: const LetterParty(name: 'A'),
      from: const LetterParty(name: 'B'),
      subject: 'S',
      showDividers: false,
    );
    expect(noDividers.showDividers, false);
  });
}
