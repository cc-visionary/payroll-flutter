/// Pure status helpers for `employee_documents` rows shown in the profile
/// Documents tab.
///
/// Document statuses (`document_type_status` enum) are a distinct vocabulary
/// from the payslip/financial statuses handled by the shared
/// `toneForStatus` in `info_card.dart` — e.g. a document `SUPERSEDED` reads as
/// "no longer current" (neutral) rather than an error, and `ISSUED`/`SIGNED`
/// are the healthy/positive terminal states. Keeping this mapping local avoids
/// leaking document-only semantics into the widely-shared payroll tone map.
library;

import '../widgets/info_card.dart' show ChipTone;

/// Map a raw `employee_documents.status` string to a chip tone.
///
/// - ISSUED / SIGNED        → success (the document is current / executed)
/// - DRAFT / PENDING_APPROVAL → warning (not yet final)
/// - VOIDED                 → danger (actively invalidated)
/// - SUPERSEDED / EXPIRED   → neutral (no longer current, but not an error)
/// - unknown / null         → neutral
ChipTone documentStatusTone(String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'ISSUED':
    case 'SIGNED':
      return ChipTone.success;
    case 'DRAFT':
    case 'PENDING_APPROVAL':
      return ChipTone.warning;
    case 'VOIDED':
      return ChipTone.danger;
    case 'SUPERSEDED':
    case 'EXPIRED':
      return ChipTone.neutral;
    default:
      return ChipTone.neutral;
  }
}

/// Human-readable label for a document status chip.
///
/// Falls back to a normalized version of the raw string (underscores → spaces,
/// title-cased) so unmapped statuses still render legibly. `PENDING_APPROVAL`
/// is given an explicit short label.
String documentStatusLabel(String? status) {
  final raw = (status ?? '').trim();
  if (raw.isEmpty) return 'Unknown';
  switch (raw.toUpperCase()) {
    case 'ISSUED':
      return 'Issued';
    case 'SIGNED':
      return 'Signed';
    case 'DRAFT':
      return 'Draft';
    case 'PENDING_APPROVAL':
      return 'Pending Approval';
    case 'VOIDED':
      return 'Voided';
    case 'SUPERSEDED':
      return 'Superseded';
    case 'EXPIRED':
      return 'Expired';
    default:
      return raw
          .split(RegExp(r'[_\s]+'))
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
          .join(' ');
  }
}

/// Whether a document row has a viewable/downloadable stored PDF.
///
/// Legacy rows (created before Storage persistence) have a null/blank
/// `file_path`; the View action must be disabled/hidden for them.
bool documentHasFile(Map<String, dynamic> row) {
  final path = row['file_path'];
  return path is String && path.trim().isNotEmpty;
}
