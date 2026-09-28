import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/pdf/pdf_theme.dart';
import '../../core/pdf/signature_png.dart';
import '../documents/blocks/block.dart';
import '../documents/blocks/emphasis_paragraph_block.dart';
import '../documents/blocks/logo_block.dart';
import '../documents/blocks/numbered_list_block.dart';
import '../documents/blocks/paragraph_block.dart';
import '../documents/blocks/signature_image_block.dart';
import '../documents/blocks/spacer_block.dart';

/// Pre-employment requirements listed on every offer letter, in the order
/// of the HR template.
const kOfferLetterRequirements = <String>[
  'Proof of SSS Number (SSS E-1 and/or E-4)',
  "Proof of Taxpayer's Identification Number (2316, Verification Slip, TIN ID)",
  'Proof of Pag-Ibig Number (Loyalty card, MDF)',
  'Proof of Philhealth Number (MDR, Philhealth ID)',
  'Original Copy of NBI Clearance',
  'Original Copy of PNP and / or Barangay Clearance',
  'Medical Clearance',
  'Copy of Diploma / Transcript of Records',
  'Copy of PSA Birth Certificate',
  'Clearance / certificate of employment from previous employers',
  '3 pcs 1x1; 2x2 ID picture; Digital Copy of ID Picture (white background)',
  '2 Valid IDs',
];

/// Everything the offer letter prints. The editable fields (dates, reporting
/// line, office hours, contact number) are confirmed by HR in a dialog
/// before rendering; the rest is autofilled from the applicant, role and
/// hiring entity.
class OfferLetterInputs {
  final DateTime dateIssued;
  final String applicantFullName;
  final String salutationName; // e.g. last name
  final String position;
  final String brandName;
  final String basicSalary; // e.g. "₱755.00 per day"
  final String status;
  final String department;
  final String reportingTo;
  final String reportingOffice;
  final String officeHours;
  final String scheduleType;
  final String contactNumber;
  final DateTime? requirementsDeadline;
  final DateTime? targetStartDate;
  final String signatoryName;
  final String signatoryTitle;
  final String? signaturePngB64;
  final Uint8List? logoBytes;

  const OfferLetterInputs({
    required this.dateIssued,
    required this.applicantFullName,
    required this.salutationName,
    required this.position,
    required this.brandName,
    required this.basicSalary,
    this.status =
        '6 Months Probationary (to be evaluated 3 times prior to '
        'regularization)',
    required this.department,
    required this.reportingTo,
    required this.reportingOffice,
    required this.officeHours,
    this.scheduleType = 'Flexible',
    required this.contactNumber,
    this.requirementsDeadline,
    this.targetStartDate,
    required this.signatoryName,
    this.signatoryTitle = 'People Manager',
    this.signaturePngB64,
    this.logoBytes,
  });

  OfferLetterInputs copyWith({
    DateTime? dateIssued,
    String? reportingTo,
    String? officeHours,
    String? contactNumber,
    DateTime? requirementsDeadline,
    DateTime? targetStartDate,
  }) => OfferLetterInputs(
    dateIssued: dateIssued ?? this.dateIssued,
    applicantFullName: applicantFullName,
    salutationName: salutationName,
    position: position,
    brandName: brandName,
    basicSalary: basicSalary,
    status: status,
    department: department,
    reportingTo: reportingTo ?? this.reportingTo,
    reportingOffice: reportingOffice,
    officeHours: officeHours ?? this.officeHours,
    scheduleType: scheduleType,
    contactNumber: contactNumber ?? this.contactNumber,
    requirementsDeadline: requirementsDeadline ?? this.requirementsDeadline,
    targetStartDate: targetStartDate ?? this.targetStartDate,
    signatoryName: signatoryName,
    signatoryTitle: signatoryTitle,
    signaturePngB64: signaturePngB64,
    logoBytes: logoBytes,
  );
}

/// "₱755.00 per day" — the pay unit follows the role's wage type.
String formatOfferSalary(num? amount, String? wageType) {
  if (amount == null) return '';
  final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final unit = switch ((wageType ?? '').toUpperCase()) {
    'DAILY' => 'day',
    'HOURLY' => 'hour',
    _ => 'month',
  };
  return '${money.format(amount)} per $unit';
}

/// Default office-hours text, e.g. "9am-10am to 6pm-7pm / Monday to
/// Saturday (8 working hours per day)".
String defaultOfficeHours({required int hoursPerDay, required String days}) =>
    '9am-10am to 6pm-7pm / $days ($hoursPerDay working hours per day)';

/// Renders the offer letter (NOT the employment contract) as document blocks.
List<Block> buildOfferLetterBlocks(OfferLetterInputs i) {
  final fmt = DateFormat('MMMM d, yyyy');
  String dateOrBlank(DateTime? d) => d == null ? '______________' : fmt.format(d);
  final sig = decodeSignaturePngB64(i.signaturePngB64);
  final contact = i.contactNumber.trim();
  return [
    if (i.logoBytes != null) ...[
      LogoBlock(i.logoBytes!, height: 56, alignment: pw.Alignment.center),
      const SpacerBlock(20),
    ],
    ParagraphBlock(fmt.format(i.dateIssued)),
    const SpacerBlock(12),
    EmphasisParagraphBlock(
      spans: [EmphasisSpan(i.applicantFullName, bold: true)],
      align: pw.TextAlign.left,
    ),
    const SpacerBlock(12),
    ParagraphBlock('Dear Mr./Ms. ${i.salutationName},'),
    const SpacerBlock(8),
    EmphasisParagraphBlock(
      spans: [
        const EmphasisSpan('We are pleased to offer you the position of '),
        EmphasisSpan(i.position, bold: true),
        const EmphasisSpan(' under '),
        EmphasisSpan(i.brandName, bold: true),
        const EmphasisSpan('.'),
      ],
      align: pw.TextAlign.left,
    ),
    const SpacerBlock(10),
    OfferTermsTableBlock([
      ('Basic Salary', i.basicSalary),
      ('Status', i.status),
      ('Department', i.department),
      ('Reporting to', i.reportingTo),
      ('Reporting Office', i.reportingOffice),
      ('Office Hours', i.officeHours),
      ('Schedule Type', i.scheduleType),
      ('HMO', 'Upon regularization'),
      ('Service Incentive Leave', 'Upon regularization'),
      ('Issuance of', 'Standard Office Equipment'),
      ('Regular Benefits', 'As prescribed by the government'),
    ]),
    const SpacerBlock(12),
    ParagraphBlock(
      'We hope that you will accept this job offer and look forward to '
      'welcoming you aboard.'
      '${contact.isEmpty ? '' : ' Feel free to call us at $contact should '
                'you have any concerns.'}',
    ),
    const SpacerBlock(8),
    const ParagraphBlock(
      'This offer shall be valid upon the completion of the background '
      'investigation process and provided that the following requirements '
      'are submitted:',
    ),
    const SpacerBlock(6),
    const NumberedListBlock(kOfferLetterRequirements),
    const SpacerBlock(12),
    EmphasisParagraphBlock(
      spans: [
        const EmphasisSpan(
          'You are requested to submit the above stated requirements to the '
          'Director on or before ',
        ),
        EmphasisSpan(dateOrBlank(i.requirementsDeadline), bold: true),
        const EmphasisSpan('. Target start date: '),
        EmphasisSpan(dateOrBlank(i.targetStartDate), bold: true),
        const EmphasisSpan('.'),
      ],
      align: pw.TextAlign.left,
    ),
    if (sig == null)
      const SpacerBlock(40)
    else ...[
      const SpacerBlock(12),
      SignatureImageBlock(sig),
    ],
    EmphasisParagraphBlock(
      spans: [EmphasisSpan(i.signatoryName, bold: true)],
      align: pw.TextAlign.left,
    ),
    ParagraphBlock(i.signatoryTitle),
    const SpacerBlock(16),
    const OfferAcceptanceBlock(),
  ];
}

/// Two-column bordered terms table with no header row (label | value).
class OfferTermsTableBlock extends Block {
  final List<(String, String)> rows;
  const OfferTermsTableBlock(this.rows);

  @override
  pw.Widget toPdf(PdfTheme theme) {
    pw.Widget cell(String text) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: theme.bodySize, color: theme.textColor),
      ),
    );
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
      },
      children: [
        for (final (label, value) in rows)
          pw.TableRow(children: [cell(label), cell(value)]),
      ],
    );
  }
}

/// Right-hand conforme: "I accept the offer as outlined above." with a
/// signature-over-printed-name line and a date line.
class OfferAcceptanceBlock extends Block {
  const OfferAcceptanceBlock();

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final style = pw.TextStyle(
      fontSize: theme.bodySize,
      color: theme.textColor,
    );
    pw.Widget line(String caption) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 22),
        pw.Container(
          width: 180,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
            ),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(caption, style: style),
      ],
    );
    return pw.Row(
      children: [
        pw.Spacer(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('I accept the offer as outlined above.', style: style),
            line('(Signature above printed name)'),
            line('(Date)'),
          ],
        ),
      ],
    );
  }
}
