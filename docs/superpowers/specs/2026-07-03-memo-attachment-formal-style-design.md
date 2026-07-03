# Memo Attachment — Formal Styling

**Date:** 2026-07-03
**Status:** Approved
**Follows:** `2026-06-23-memo-image-attachment-design.md`

## Problem

The optional image attachment now renders on its own page of NTE/NOD memos, but
its presentation is too informal for a legal HR document: the image is stretched
full-bleed edge-to-edge with no frame, under a bare "Attachment" heading, so it
reads as a pasted screenshot rather than a formal exhibit.

## Approach — Framed exhibit + Annex label

Keep the document's existing formal look (black-on-white A4, Inter, 0.75" margins).
Three changes:

1. **Formal label.** The attachment page heading changes from `'Attachment'` to
   `'Annex A'` (same bold `headingSize` `HeadingBlock` style as other sections).
   "Annex A" is the idiomatic exhibit label in PH HR/legal memos, and leaves room
   for Annex B/C if multiple attachments are ever supported.

2. **Framed, padded image.** In `ImageAttachmentBlock.toPdf`, wrap the image in a
   `pw.Container` with a hairline border (`PdfColors.grey400`, `0.5`) and ~8pt inner
   padding. The image keeps `BoxFit.contain` and letterboxes within the frame, so a
   high-resolution photo still cannot overflow. The border is what makes it read as
   a mounted exhibit instead of a raw image.

3. **Upright caption.** The optional caption below the frame renders upright (not
   italic), centered, `bodySize - 1`, `grey800` — a formal descriptive line. The
   "no/blank caption ⇒ no caption" behaviour is unchanged.

## Scope

- `lib/features/documents/blocks/image_attachment_block.dart` — border, padding,
  caption style.
- `lib/features/documents/templates/nte_template.dart`,
  `lib/features/documents/templates/nod_template.dart` — heading `'Attachment'` →
  `'Annex A'`.

## Testing

- Template build tests (`nte_build_test.dart`, `nod_template_test.dart`) assert the
  attachment heading text; update `'Attachment'` → `'Annex A'` (incl. the NOD block
  ordering assertion).
- `ImageAttachmentBlock.toPdf` structure is not introspectable via the `pdf`
  package, so the block test keeps its `returnsNormally` guard; the border/caption
  visual is verified by generating an actual memo PDF.

## Out of scope

Multiple attachments, per-attachment lettering, and configurable label text. Single
"Annex A" only, matching the current single-image feature.
