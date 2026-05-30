import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pdf/pdf_filename.dart';
import '../../../core/pdf/pdf_theme.dart';
import '../blocks/block.dart';
import '../pdf/pdf_builder.dart';
import '../providers.dart';
import '../templates/document_template.dart';
import '../templates/liability_waiver_inputs.dart';
import '../templates/liability_waiver_template.dart';

/// One employee that was excluded from a bulk run, with the reason.
class BulkSkip {
  final String employeeName;
  final String reason;
  const BulkSkip(this.employeeName, this.reason);
}

/// A single generated per-employee PDF (filename + bytes) — the ZIP source.
class BulkFile {
  final String filename;
  final Uint8List bytes;
  const BulkFile(this.filename, this.bytes);
}

/// Output of [bulkGenerate]: the combined PDF (each employee's doc on its own
/// page), the per-employee PDFs (for a ZIP), and the skipped employees.
class BulkGenerateResult {
  final Uint8List combinedPdf;
  final List<BulkFile> files;
  final List<BulkSkip> skipped;
  int get generatedCount => files.length;
  const BulkGenerateResult({
    required this.combinedPdf,
    required this.files,
    required this.skipped,
  });
}

/// Generate [template] for many [employeeIds]. Returns a combined PDF (each
/// employee's doc on its own page), the per-employee PDFs (for a ZIP), and
/// a list of skipped employees (gate-blocked or validation failures).
///
/// [shared] carries batch-wide overrides applied to every employee. In v1
/// only the Liability Waiver consumes it (`outingDate`, `outingLocation`).
Future<BulkGenerateResult> bulkGenerate({
  required DocumentTemplate template,
  required List<String> employeeIds,
  required WidgetRef ref,
  required PdfTheme theme,
  Map<String, Object?> shared = const {},
}) async {
  final files = <BulkFile>[];
  final skipped = <BulkSkip>[];
  final perEmployeeBlocks = <List<Block>>[];
  final today = DateTime.now();

  for (final id in employeeIds) {
    final emp = await ref.read(documentEmployeeProvider(id).future);
    if (emp == null) {
      skipped.add(BulkSkip(id, 'Employee not found.'));
      continue;
    }
    final co = emp.hiringEntityId == null
        ? null
        : await ref.read(hiringEntityByIdProvider(emp.hiringEntityId!).future);
    final ctx = AutofillContext(employee: emp, company: co, ref: ref);

    final gates = template.gates(ctx);
    if (gates.isNotEmpty) {
      skipped.add(BulkSkip(emp.fullName, gates.first.reason));
      continue;
    }

    // `template` is a raw `DocumentTemplate` (== `DocumentTemplate<dynamic>`),
    // so `autofill` returns `Future<dynamic>` and `build`/`validate` accept
    // `dynamic` — no cast needed; the concrete template handles its own type.
    var inputs = await template.autofill(ctx);

    // Apply shared overrides (only the Liability Waiver has shared fields in
    // v1). Guard each field with `containsKey` so an absent key never clears
    // the autofilled value via copyWith's null-sentinel semantics.
    if (template is LiabilityWaiverTemplate && inputs is LiabilityWaiverInputs) {
      inputs = inputs.copyWith(
        outingDate: shared.containsKey('outingDate')
            ? shared['outingDate'] as DateTime?
            : inputs.outingDate,
        outingLocation: shared.containsKey('outingLocation')
            ? (shared['outingLocation'] as String?) ?? inputs.outingLocation
            : inputs.outingLocation,
      );
    }

    final errors = template.validate(inputs);
    if (errors.isNotEmpty) {
      skipped.add(BulkSkip(emp.fullName, errors.first.message));
      continue;
    }

    final blocks = template.build(inputs);
    perEmployeeBlocks.add(blocks);

    final bytes = await buildDocumentPdf(blocks: blocks, theme: theme);
    final name = filenameForDocument(
      templateId: template.id,
      employeeNumber: emp.employeeNumber,
      employeeId: emp.id,
      date: today,
    );
    files.add(BulkFile(name, bytes));
  }

  // Use a per-employee MultiPage so each employee's "Page X of Y" footer
  // resets independently (Mark = "Page 1 of 1", Brixter = "Page 1 of 1")
  // instead of running continuously across the batch. Falls back to an
  // empty document when no employees produced output.
  final combinedPdf = perEmployeeBlocks.isEmpty
      ? await buildDocumentPdf(blocks: const [], theme: theme)
      : await buildMultiEmployeePdf(
          employees: perEmployeeBlocks,
          theme: theme,
        );

  return BulkGenerateResult(
    combinedPdf: combinedPdf,
    files: files,
    skipped: skipped,
  );
}
