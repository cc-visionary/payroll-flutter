# Optional image attachment for NTE & NOD memos

**Date:** 2026-06-23
**Status:** Approved design — pending implementation plan
**Templates affected:** Notice to Explain (`nte`), Notice of Decision (`nod`)

## Goal

Let HR optionally attach **one image** (e.g. photo evidence, a CCTV still, a
signed slip) to a disciplinary memo. The image appears in the live preview and
in the PDF the user downloads/prints at generation time, with an **optional
caption** beneath it.

## Explicit non-goal: the image is NOT persisted

The image is **generation-time only**. It must never be saved. A re-rendered
saved memo (the `/documents/view/:id` path) will simply not contain it. This is
a deliberate, user-confirmed decision — it avoids all storage infrastructure
(no Supabase Storage bucket, no migration, no base64 bloat in `generation_options`).

## Key insight — mirror `logoBytes` exactly

The document system already carries one piece of binary through the
form → live-preview → PDF pipeline **without persisting it**: the brand
`logoBytes` field on `NteInputs`.

- It lives on the inputs object and is consumed synchronously by `build()`.
- It is **deliberately excluded from `toJson()`** (see the comment in
  `nte_inputs.dart`: *"logoBytes is intentionally excluded from toJson
  (binary)"*), so it never reaches `generation_options`.
- On saved-doc re-render it is re-supplied *deterministically* from the company
  (`loadBrandLogoBytes`) — but that is logo-specific. A user-uploaded image has
  no deterministic source, so on re-render it is simply absent. That is exactly
  the desired behavior here.

The attachment gets the **same treatment as `logoBytes`**: held on inputs,
consumed by `build()`, excluded from `toJson`/`fromJson`. No persistence code,
no renderer changes.

## Architecture

Five small, isolated units. Nothing else changes.

### 1. `ImageAttachmentBlock` — new block

`lib/features/documents/blocks/image_attachment_block.dart`

```dart
class ImageAttachmentBlock extends Block {
  final Uint8List bytes;
  final String? caption;   // null/empty => no caption rendered
  const ImageAttachmentBlock(this.bytes, {this.caption});
  pw.Widget toPdf(PdfTheme theme) => /* image + optional caption */;
}
```

- Renders `pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain)` inside a
  `pw.ConstrainedBox` with a **capped max height** (≈520pt) so a tall photo
  cannot overflow the page; width is bounded by the `MultiPage` column.
- When `caption` is non-empty, renders it under the image in small, muted text
  (use `theme`'s secondary text color / a small font size, consistent with
  other blocks).
- Pure `toPdf`, byte-identical preview/PDF like every other block.

### 2. Inputs — add a binary field to `NteInputs` and `NodInputs`

Add two fields to each:

```dart
final Uint8List? attachmentBytes;
final String? attachmentCaption;
```

- Add to the constructor (both optional, default null).
- Add to `copyWith` **with a clear-to-null path** so "Remove" works. Use the
  existing `_undef` sentinel pattern (already present in `nod_inputs.dart`;
  introduce the same sentinel in `nte_inputs.dart`) for `attachmentBytes` and
  `attachmentCaption`, since plain `?? this.x` cannot reset a field to null.
- **Excluded from `toJson()`** (binary — matches `logoBytes`). `attachmentCaption`
  is also excluded: it is meaningless without the image it captions, and the
  whole attachment is generation-time only.
- **Not reconstructed in `fromJson()`** — stays null on re-render.

### 3. `ImageAttachmentField` — new reusable form input

`lib/features/documents/inputs/image_attachment_field.dart`

- Uses the existing `file_picker` dependency, matching the house pattern in
  `attendance_import_dialog.dart`:
  `FilePicker.platform.pickFiles(type: FileType.image, withData: true)` →
  `result.files.single.bytes`.
- States:
  - **Empty:** an outlined "Add image" button.
  - **Set:** a small thumbnail preview (`Image.memory`) + the picked file name +
    a "Remove" button, plus an optional caption `TextFormField`.
- API: `bytes`, `caption`, `fileName`, and callbacks
  `onChanged(Uint8List? bytes, String? fileName)` + `onCaptionChanged(String)`
  (final shape decided in the plan; the parent maps these into `copyWith`).
- Optional: a soft guard if bytes are unexpectedly large (e.g. > ~8 MB) shown as
  a non-blocking hint. Not a hard validation — the attachment is always optional.

### 4. Forms — wire the field in

- `NteForm` and `NodForm` each gain an **"Attachment (optional)"** labelled
  section using `ImageAttachmentField`, following their existing
  `_label(...) + widget` layout. `onChanged` maps to
  `copyWith(attachmentBytes: ..., attachmentCaption: ...)`.

### 5. `build()` — append the attachment section only when present

In both `NteTemplate.build` and `NodTemplate.build`, at the very end, append
**only if `attachmentBytes != null`**:

```
PageBreakBlock()           // keep the memo body clean; evidence on its own page
HeadingBlock('Attachment')
SpacerBlock(8)
ImageAttachmentBlock(i.attachmentBytes!, caption: i.attachmentCaption)
```

- NTE already builds a mutable `List<Block>` — append with an `if`.
- NOD returns a list literal — use a trailing collection-`if` + spread
  (`if (i.attachmentBytes != null) ...[ ... ]`).
- When no image is attached, output is **byte-identical to today** (no page
  break, no heading) — existing golden tests stay green.

## What does NOT change

- `generate_screen.dart` — attachment bytes already flow through inputs via the
  existing `onChanged` → `copyWith` path; the live preview and generate-stage
  bytes both call `build()`, so the image appears automatically.
- `employee_document_repository.dart` — persists `toJson()`, which excludes the
  attachment. Nothing to do.
- `saved_document_renderer.dart` — reconstructs via `fromJson` (attachment stays
  null) and re-supplies only `logoBytes`. The saved memo re-renders without the
  image, as intended.

## Testing

Mirror the existing suite:

- **Block test** (`test/features/documents/blocks/image_attachment_block_test.dart`):
  `toPdf` produces a non-empty PDF given bytes; caption rendered when provided,
  omitted when null/empty.
- **Build tests** (extend `nte_build_test.dart` and `nod_template_test.dart`):
  the attachment heading + `ImageAttachmentBlock` are present **iff**
  `attachmentBytes` is set, and absent otherwise (guards byte-identical output).
- **`toJson` exclusion** (extend `template_inputs_to_json_test.dart`):
  assert `toJson()` of NTE/NOD inputs with an attachment set contains **no**
  `attachmentBytes`/`attachmentCaption` keys.
- **copyWith** (extend `nte_from_json_test.dart` / a copyWith test): can set the
  attachment and clear it back to null via the sentinel.
- Existing golden pagination tests (`nte_pagination_test.dart`,
  `nod_pagination_test.dart`) must remain unchanged (no-attachment path).

## Scope summary

| Item | New / Changed |
|------|----------------|
| `blocks/image_attachment_block.dart` | new |
| `inputs/image_attachment_field.dart` | new |
| `templates/nte_inputs.dart` | +fields, copyWith, (no toJson/fromJson) |
| `templates/nod_inputs.dart` | +fields, copyWith, (no toJson/fromJson) |
| `templates/nte_template.dart` | append attachment section in `build` |
| `templates/nod_template.dart` | append attachment section in `build` |
| `forms/nte_form.dart` | +attachment field |
| `forms/nod_form.dart` | +attachment field |
| tests | block, build, toJson-exclusion, copyWith |

No migrations, no storage, no repository or renderer changes.
