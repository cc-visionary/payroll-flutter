import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/emphasis_paragraph_block.dart';
import 'package:payroll_flutter/features/documents/blocks/numbered_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/paragraph_block.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/hiring/offer_letter_template.dart';

OfferLetterInputs _inputs({DateTime? deadline, DateTime? start}) =>
    OfferLetterInputs(
      dateIssued: DateTime(2026, 9, 28),
      applicantFullName: 'Juan Dela Cruz',
      salutationName: 'Dela Cruz',
      position: 'Kiosk Sales Representative',
      brandName: 'HAVIT',
      basicSalary: formatOfferSalary(755, 'DAILY'),
      department: 'Retail',
      reportingTo: 'Retail Manager',
      reportingOffice: '908 Alvarado Street, Binondo, Manila',
      officeHours: defaultOfficeHours(
        hoursPerDay: 8,
        days: 'Monday to Saturday',
      ),
      contactNumber: '09278212182',
      requirementsDeadline: deadline,
      targetStartDate: start,
      signatoryName: 'Brixter Del Mundo',
    );

String _text(Object b) => switch (b) {
  ParagraphBlock p => p.text,
  EmphasisParagraphBlock e => e.spans.map((s) => s.text).join(),
  _ => '',
};

void main() {
  test('salary unit follows the wage type', () {
    expect(formatOfferSalary(755, 'DAILY'), '₱755.00 per day');
    expect(formatOfferSalary(20000, 'MONTHLY'), '₱20,000.00 per month');
    expect(formatOfferSalary(null, 'DAILY'), '');
  });

  test('renders the offer letter, not the employment contract', () {
    final blocks = buildOfferLetterBlocks(_inputs());
    final all = blocks.map(_text).join('\n');
    expect(
      all,
      contains(
        'We are pleased to offer you the position of Kiosk Sales '
        'Representative under HAVIT.',
      ),
    );
    expect(all, contains('Dear Mr./Ms. Dela Cruz,'));
    expect(all, contains('September 28, 2026'));
    expect(all, contains('09278212182'));
    expect(all, isNot(contains('EMPLOYMENT CONTRACT')));

    final table = blocks.whereType<OfferTermsTableBlock>().single;
    final labels = table.rows.map((r) => r.$1).toList();
    expect(labels, [
      'Basic Salary',
      'Status',
      'Department',
      'Reporting to',
      'Reporting Office',
      'Office Hours',
      'Schedule Type',
      'HMO',
      'Service Incentive Leave',
      'Issuance of',
      'Regular Benefits',
    ]);
    expect(table.rows.first.$2, '₱755.00 per day');

    final reqs = blocks.whereType<NumberedListBlock>().single;
    expect(reqs.items, hasLength(12));
    expect(blocks.whereType<OfferAcceptanceBlock>(), hasLength(1));
  });

  test('deadline and start date print when set, blanks when not', () {
    final unset = buildOfferLetterBlocks(_inputs()).map(_text).join();
    expect(unset, contains('on or before ______________'));

    final set = buildOfferLetterBlocks(
      _inputs(deadline: DateTime(2026, 10, 5), start: DateTime(2026, 10, 12)),
    ).map(_text).join();
    expect(set, contains('on or before October 5, 2026'));
    expect(set, contains('Target start date: October 12, 2026'));
  });

  test('builds a PDF', () async {
    final bytes = await buildDocumentPdf(
      blocks: buildOfferLetterBlocks(_inputs()),
      theme: PdfTheme.testStub(),
    );
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });
}
