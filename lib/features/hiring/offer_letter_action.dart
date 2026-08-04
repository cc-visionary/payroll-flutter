import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import '../../data/models/applicant.dart';
import '../documents/pdf/pdf_builder.dart';
import '../documents/signatory_autofill.dart';
import '../documents/templates/document_template.dart';
import '../documents/templates/employment_contract_template.dart';

/// Renders the [EmploymentContractTemplate] in applicant mode (offer-letter
/// variant). Returns raw PDF bytes. Pure — no UI side effects.
///
/// The template's [AutofillContext.applicantId] branch (added in Task 22)
/// pulls applicant + scorecard + hiring-entity data from Riverpod providers
/// and populates salary, position, duties, and company details. Probation
/// dates are intentionally left blank because the applicant has no hireDate
/// yet; the user fills them in before signing.
Future<Uint8List> renderOfferLetter({
  required Applicant applicant,
  required WidgetRef ref,
}) async {
  final theme = await PdfTheme.defaults();
  const tpl = EmploymentContractTemplate();
  final sigs = await loadAutofillSignatories(ref);
  final ctx = AutofillContext(
    // Applicant mode — employee is intentionally null. The template checks
    // ctx.applicantId != null first and branches accordingly.
    employee: null,
    // Company resolved by the template from applicant.hiringEntityId; pass
    // null here so the template's own entity lookup takes precedence.
    company: null,
    ref: ref,
    applicantId: applicant.id,
    hrSignatory: sigs.hr,
    legalSignatory: sigs.legal,
  );
  final inputs = await tpl.autofill(ctx);
  final blocks = tpl.build(inputs);
  return buildDocumentPdf(blocks: blocks, theme: theme);
}

/// Pushes a full-screen PDF preview over the current route. The preview
/// includes Download and Print actions (Print is suppressed on web) via
/// [PdfPreviewScaffold], matching the house pattern used by the payslip and
/// document-generate flows.
///
/// The button that triggers this should be disabled when
/// [applicant.roleScorecardId] is null — the template falls back gracefully
/// but the offer letter is meaningless without scorecard data.
Future<void> showOfferLetterPreview(
  BuildContext context, {
  required Applicant applicant,
  required WidgetRef ref,
}) async {
  final today = DateTime.now();
  final ymd =
      '${today.year.toString().padLeft(4, '0')}'
      '${today.month.toString().padLeft(2, '0')}'
      '${today.day.toString().padLeft(2, '0')}';
  // Use the first 8 chars of the applicant UUID as a stable identifier
  // (no employee number exists yet).
  final shortId = applicant.id.length >= 8
      ? applicant.id.substring(0, 8).toUpperCase()
      : applicant.id.toUpperCase();
  final filename = 'OfferLetter_${shortId}_$ymd.pdf';

  // Capture ref outside the builder so the closure is stable across
  // hot-reloads (ref is valid for the lifetime of the ConsumerWidget).
  final capturedRef = ref;

  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: const Text('Offer Letter Preview'),
        ),
        body: PdfPreviewScaffold(
          filename: filename,
          enabled: true,
          buildPdf: (PdfPageFormat _) => renderOfferLetter(
            applicant: applicant,
            ref: capturedRef,
          ),
        ),
      ),
    ),
  );
}
