# Memo Image Attachment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, generation-time-only image attachment (with optional caption) to the Notice to Explain (NTE) and Notice of Decision (NOD) memo templates.

**Architecture:** The attachment is treated exactly like the existing brand `logoBytes` binary — held on the template inputs object, consumed synchronously by `build()`, and **deliberately excluded from `toJson()`/`fromJson()`** so it is never persisted. When attached, the image is appended on its own page under an "Attachment" heading; when absent, output is byte-identical to today. A new `ImageAttachmentBlock` renders the image (letterboxed to the page) + optional caption; a new reusable `ImageAttachmentField` (built on the existing `file_picker` dependency) provides the pick/preview/remove/caption UI in both forms.

**Tech Stack:** Flutter (Material 3, Riverpod), `pdf`/`printing` for PDF rendering, `file_picker` (already a dependency), `flutter_test`.

## Global Constraints

- The attachment is **generation-time only — never persisted.** `attachmentBytes` and `attachmentCaption` MUST be excluded from `toJson()` and MUST NOT be reconstructed in `fromJson()` (identical treatment to `logoBytes`). Verbatim from spec: *"The image is generation-time only. It must never be saved."*
- **Single image** per memo, with an **optional caption**.
- Templates affected: **`nte` and `nod` only.** No other template, the repository, `generate_screen.dart`, or `saved_document_renderer.dart` changes.
- No migrations, no Supabase Storage, no base64 in `generation_options`.
- PDFs are intentionally black-on-white (legal docs) — no Luxium purple in the block.
- Run tests with `flutter test <path>`. Work happens on the existing branch `feat/memo-image-attachment`.
- Follow house form conventions: `_label(...)` + widget, `TextFormField(initialValue: ..., onChanged: ...)`, `_set(_i.copyWith(...))`.

---

### Task 1: `ImageAttachmentBlock` — new PDF block

**Files:**
- Create: `lib/features/documents/blocks/image_attachment_block.dart`
- Test: `test/features/documents/blocks/image_attachment_block_test.dart`

**Interfaces:**
- Consumes: `Block` (`lib/features/documents/blocks/block.dart`), `PdfTheme` (`lib/core/pdf/pdf_theme.dart`).
- Produces: `class ImageAttachmentBlock extends Block` with constructor `ImageAttachmentBlock(Uint8List bytes, {String? caption})` and fields `bytes` (`Uint8List`), `caption` (`String?`). Used by Tasks 4 and 5.

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/blocks/image_attachment_block_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/image_attachment_block.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  test('stores bytes and caption', () {
    final block = ImageAttachmentBlock(bytes, caption: 'CCTV still');
    expect(block.bytes, bytes);
    expect(block.caption, 'CCTV still');
  });

  test('caption defaults to null', () {
    final block = ImageAttachmentBlock(bytes);
    expect(block.caption, isNull);
  });

  test('toPdf renders without throwing (with and without caption)', () {
    final theme = PdfTheme.testStub();
    expect(() => ImageAttachmentBlock(bytes, caption: 'cap').toPdf(theme),
        returnsNormally);
    expect(() => ImageAttachmentBlock(bytes).toPdf(theme), returnsNormally);
    expect(() => ImageAttachmentBlock(bytes, caption: '   ').toPdf(theme),
        returnsNormally);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/image_attachment_block_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'payroll_flutter' ... image_attachment_block.dart` / "ImageAttachmentBlock isn't defined".

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/documents/blocks/image_attachment_block.dart`:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// Renders an optional, user-supplied image attachment (e.g. photo evidence)
/// for a memo, letterboxed to fit the page content area, with an optional
/// caption beneath it.
///
/// The bytes are NEVER persisted — like the brand logo, this is a
/// generation-time-only binary carried on the template inputs. See the
/// memo-image-attachment design doc.
class ImageAttachmentBlock extends Block {
  final Uint8List bytes;

  /// Optional caption shown under the image. Null or whitespace renders no
  /// caption.
  final String? caption;

  const ImageAttachmentBlock(this.bytes, {this.caption});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final maxWidth =
        theme.pageFormat.width - theme.pageMargin.left - theme.pageMargin.right;
    final hasCaption = caption != null && caption!.trim().isNotEmpty;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Center(
          // Explicit width+height with BoxFit.contain letterboxes any image
          // size into the page, so a high-resolution photo can never overflow.
          child: pw.Image(
            pw.MemoryImage(bytes),
            width: maxWidth,
            height: 480,
            fit: pw.BoxFit.contain,
          ),
        ),
        if (hasCaption) pw.SizedBox(height: 6),
        if (hasCaption)
          pw.Text(
            caption!.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: theme.bodySize - 1,
              color: PdfColors.grey700,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/image_attachment_block_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/blocks/image_attachment_block.dart test/features/documents/blocks/image_attachment_block_test.dart
git commit -m "feat(documents): add ImageAttachmentBlock for memo attachments"
```

---

### Task 2: `NteInputs` — add attachment fields (excluded from JSON)

**Files:**
- Modify: `lib/features/documents/templates/nte_inputs.dart`
- Test: `test/features/documents/template_inputs_to_json_test.dart` (extend the existing `NteInputs.toJson` group)

**Interfaces:**
- Consumes: `Uint8List` (`dart:typed_data`, already imported in this file).
- Produces: `NteInputs` gains `final Uint8List? attachmentBytes;` and `final String? attachmentCaption;` (both optional, default null), settable/clearable via `copyWith`. NOT present in `toJson()` output. Used by Tasks 4 and 7.

- [ ] **Step 1: Write the failing test**

In `test/features/documents/template_inputs_to_json_test.dart`, inside `group('NteInputs.toJson', ...)`, add this test after the existing one (use the same `logo` top-level var already defined in the file):

```dart
    test('excludes attachmentBytes and attachmentCaption', () {
      final inputs = NteInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeFirstName: 'Jane',
        employeeLastName: 'Doe',
        employeePosition: 'Clerk',
        employeeDepartment: 'Ops',
        companyId: 'CO-1',
        companyName: 'Acme',
        dateIssued: DateTime.utc(2026, 1, 1),
        responseDeadline: DateTime.utc(2026, 1, 6),
        subjectSubtopic: '',
        charges: const [],
        applicableViolations: const [],
        attachmentBytes: logo,
        attachmentCaption: 'CCTV still',
      );
      final json = inputs.toJson();
      expect(json.containsKey('attachmentBytes'), isFalse);
      expect(json.containsKey('attachmentCaption'), isFalse);
    });

    test('copyWith sets and clears the attachment', () {
      final base = NteInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        employeeFirstName: 'Jane',
        employeeLastName: 'Doe',
        employeePosition: 'Clerk',
        employeeDepartment: 'Ops',
        companyId: 'CO-1',
        companyName: 'Acme',
        dateIssued: DateTime.utc(2026, 1, 1),
        responseDeadline: DateTime.utc(2026, 1, 6),
        subjectSubtopic: '',
        charges: const [],
        applicableViolations: const [],
      );
      final withImg =
          base.copyWith(attachmentBytes: logo, attachmentCaption: 'cap');
      expect(withImg.attachmentBytes, logo);
      expect(withImg.attachmentCaption, 'cap');
      final cleared =
          withImg.copyWith(attachmentBytes: null, attachmentCaption: null);
      expect(cleared.attachmentBytes, isNull);
      expect(cleared.attachmentCaption, isNull);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/template_inputs_to_json_test.dart`
Expected: FAIL — `No named parameter with the name 'attachmentBytes'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/features/documents/templates/nte_inputs.dart`:

(a) Add the two fields after `final Uint8List? logoBytes;` (around line 37):

```dart
  final Uint8List? logoBytes;
  final Uint8List? attachmentBytes;
  final String? attachmentCaption;
```

(b) Add to the constructor after `this.logoBytes,`:

```dart
    this.logoBytes,
    this.attachmentBytes,
    this.attachmentCaption,
```

(c) In `copyWith`, change the signature's `Uint8List? logoBytes,` line to add two sentinel-typed params, and update the body. Replace the `logoBytes` param line:

```dart
    Uint8List? logoBytes,
    Object? attachmentBytes = _undef,
    Object? attachmentCaption = _undef,
  }) =>
```

and in the returned `NteInputs(...)`, after the `logoBytes: logoBytes ?? this.logoBytes,` line add:

```dart
        logoBytes: logoBytes ?? this.logoBytes,
        attachmentBytes: identical(attachmentBytes, _undef)
            ? this.attachmentBytes
            : attachmentBytes as Uint8List?,
        attachmentCaption: identical(attachmentCaption, _undef)
            ? this.attachmentCaption
            : attachmentCaption as String?,
      );
```

(d) At the very bottom of the file (after the class closing brace), add the sentinel:

```dart
const _undef = Object();
```

Leave `toJson()` and `fromJson()` unchanged (the new fields are intentionally absent from both).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/template_inputs_to_json_test.dart`
Expected: PASS (all groups, including the two new NTE tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/nte_inputs.dart test/features/documents/template_inputs_to_json_test.dart
git commit -m "feat(documents): NteInputs carries non-persisted image attachment"
```

---

### Task 3: `NodInputs` — add attachment fields (excluded from JSON)

**Files:**
- Modify: `lib/features/documents/templates/nod_inputs.dart`
- Test: `test/features/documents/template_inputs_to_json_test.dart` (extend the existing `NodInputs.toJson` group)

**Interfaces:**
- Consumes: `Uint8List` (`dart:typed_data` — must be imported into this file; it currently has no import).
- Produces: `NodInputs` gains `final Uint8List? attachmentBytes;` and `final String? attachmentCaption;`, settable/clearable via `copyWith`, absent from `toJson()`. The file already defines the `_undef` sentinel. Used by Tasks 5 and 7.

- [ ] **Step 1: Write the failing test**

In `test/features/documents/template_inputs_to_json_test.dart`, inside `group('NodInputs.toJson', ...)`, add after the existing test:

```dart
    test('excludes attachmentBytes and attachmentCaption', () {
      final inputs = NodInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        companyId: 'CO-1',
        companyName: 'Acme',
        effectiveDate: DateTime.utc(2026, 2, 1),
        issueDate: DateTime.utc(2026, 1, 15),
        attachmentBytes: logo,
        attachmentCaption: 'Photo of damaged unit',
      );
      final json = inputs.toJson();
      expect(json.containsKey('attachmentBytes'), isFalse);
      expect(json.containsKey('attachmentCaption'), isFalse);
    });

    test('copyWith sets and clears the attachment', () {
      final base = NodInputs(
        employeeId: 'EMP-1',
        employeeFullName: 'Jane Doe',
        companyId: 'CO-1',
        companyName: 'Acme',
        effectiveDate: DateTime.utc(2026, 2, 1),
        issueDate: DateTime.utc(2026, 1, 15),
      );
      final withImg =
          base.copyWith(attachmentBytes: logo, attachmentCaption: 'cap');
      expect(withImg.attachmentBytes, logo);
      expect(withImg.attachmentCaption, 'cap');
      final cleared =
          withImg.copyWith(attachmentBytes: null, attachmentCaption: null);
      expect(cleared.attachmentBytes, isNull);
      expect(cleared.attachmentCaption, isNull);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/template_inputs_to_json_test.dart`
Expected: FAIL — `No named parameter with the name 'attachmentBytes'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/features/documents/templates/nod_inputs.dart`:

(a) Add at the top of the file, above `import 'document_template.dart';`:

```dart
import 'dart:typed_data';

import 'document_template.dart';
```

(b) Add the two fields after `final DateTime issueDate;` (around line 40):

```dart
  final DateTime issueDate;
  final Uint8List? attachmentBytes;
  final String? attachmentCaption;
```

(c) Add to the constructor after `required this.issueDate,`:

```dart
    required this.issueDate,
    this.attachmentBytes,
    this.attachmentCaption,
```

(d) In `copyWith`, add two params after `DateTime? issueDate,`:

```dart
    DateTime? issueDate,
    Object? attachmentBytes = _undef,
    Object? attachmentCaption = _undef,
  }) => NodInputs(
```

and in the returned `NodInputs(...)`, after `issueDate: issueDate ?? this.issueDate,` add:

```dart
    issueDate: issueDate ?? this.issueDate,
    attachmentBytes: identical(attachmentBytes, _undef)
        ? this.attachmentBytes
        : attachmentBytes as Uint8List?,
    attachmentCaption: identical(attachmentCaption, _undef)
        ? this.attachmentCaption
        : attachmentCaption as String?,
  );
```

Leave `toJson()` and `fromJson()` unchanged. The `_undef` sentinel already exists at the bottom of this file — do not add another.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/template_inputs_to_json_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/nod_inputs.dart test/features/documents/template_inputs_to_json_test.dart
git commit -m "feat(documents): NodInputs carries non-persisted image attachment"
```

---

### Task 4: `NteTemplate.build` — append attachment section when present

**Files:**
- Modify: `lib/features/documents/templates/nte_template.dart`
- Test: `test/features/documents/templates/nte_build_test.dart`

**Interfaces:**
- Consumes: `ImageAttachmentBlock` (Task 1), `NteInputs.attachmentBytes`/`attachmentCaption` (Task 2), `PageBreakBlock`, `HeadingBlock`, `SpacerBlock`.
- Produces: when `i.attachmentBytes != null`, `build()` appends `PageBreakBlock`, `HeadingBlock('Attachment')`, `SpacerBlock(8)`, `ImageAttachmentBlock(...)` after the acknowledgment block; otherwise output is unchanged.

- [ ] **Step 1: Write the failing test**

In `test/features/documents/templates/nte_build_test.dart`, add imports at the top (after the existing imports):

```dart
import 'dart:typed_data';
import 'package:payroll_flutter/features/documents/blocks/image_attachment_block.dart';
import 'package:payroll_flutter/features/documents/blocks/page_break_block.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
```

Then add these tests inside `main()`:

```dart
  test('no attachment block when attachmentBytes is null', () {
    const t = NteTemplate();
    final blocks = t.build(valid());
    expect(blocks.whereType<ImageAttachmentBlock>(), isEmpty);
    expect(blocks.whereType<PageBreakBlock>(), isEmpty);
  });

  test('appends attachment section when attachmentBytes is set', () {
    const t = NteTemplate();
    final blocks = t.build(valid().copyWith(
      attachmentBytes: Uint8List.fromList([1, 2, 3]),
      attachmentCaption: 'Evidence photo',
    ));
    final img = blocks.whereType<ImageAttachmentBlock>().toList();
    expect(img.length, 1);
    expect(img.first.caption, 'Evidence photo');
    expect(blocks.whereType<PageBreakBlock>().length, 1);
    expect(
      blocks.whereType<HeadingBlock>().any((h) => h.text == 'Attachment'),
      isTrue,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/nte_build_test.dart`
Expected: FAIL — `ImageAttachmentBlock` found 0 (the append isn't implemented yet).

- [ ] **Step 3: Write minimal implementation**

In `lib/features/documents/templates/nte_template.dart`:

(a) Add imports near the other block imports (keep alphabetical-ish grouping):

```dart
import '../blocks/heading_block.dart';
import '../blocks/image_attachment_block.dart';
import '../blocks/page_break_block.dart';
```

(b) In `build`, immediately before `return blocks;`, insert:

```dart
    if (i.attachmentBytes != null) {
      blocks.add(const PageBreakBlock());
      blocks.add(const HeadingBlock('Attachment'));
      blocks.add(const SpacerBlock(8));
      blocks.add(ImageAttachmentBlock(
        i.attachmentBytes!,
        caption: i.attachmentCaption,
      ));
    }
    return blocks;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/nte_build_test.dart`
Expected: PASS (existing + 2 new tests).

- [ ] **Step 5: Run the NTE golden test to confirm no-attachment output is unchanged**

Run: `flutter test test/features/documents/goldens/nte_pagination_test.dart`
Expected: PASS (no golden regeneration needed — the default `valid()` path has no attachment).

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/nte_template.dart test/features/documents/templates/nte_build_test.dart
git commit -m "feat(documents): NTE appends optional image attachment page"
```

---

### Task 5: `NodTemplate.build` — append attachment section when present

**Files:**
- Modify: `lib/features/documents/templates/nod_template.dart`
- Test: `test/features/documents/templates/nod_template_test.dart`

**Interfaces:**
- Consumes: `ImageAttachmentBlock` (Task 1), `NodInputs.attachmentBytes`/`attachmentCaption` (Task 3), `PageBreakBlock`, `HeadingBlock` (already imported in this file), `SpacerBlock` (already imported).
- Produces: when `i.attachmentBytes != null`, `build()` appends the attachment section after the `MultiSignatureBlock`; otherwise output is unchanged.

- [ ] **Step 1: Write the failing test**

First open `test/features/documents/templates/nod_template_test.dart` to reuse its existing helper that builds a valid `NodInputs` (note the helper's name — it may be `valid()` or similar; use whatever it defines). Add imports at the top:

```dart
import 'dart:typed_data';
import 'package:payroll_flutter/features/documents/blocks/image_attachment_block.dart';
import 'package:payroll_flutter/features/documents/blocks/page_break_block.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
```

Add these tests inside `main()` (replace `validNod()` with the file's actual valid-inputs helper if named differently; if none exists, construct `NodInputs` inline with the required fields `employeeId`, `employeeFullName`, `companyId`, `companyName`, `effectiveDate`, `issueDate`):

```dart
  test('no attachment block when attachmentBytes is null', () {
    const t = NodTemplate();
    final blocks = t.build(validNod());
    expect(blocks.whereType<ImageAttachmentBlock>(), isEmpty);
    expect(blocks.whereType<PageBreakBlock>(), isEmpty);
  });

  test('appends attachment section when attachmentBytes is set', () {
    const t = NodTemplate();
    final blocks = t.build(validNod().copyWith(
      attachmentBytes: Uint8List.fromList([9, 8, 7]),
      attachmentCaption: 'Damaged unit',
    ));
    final img = blocks.whereType<ImageAttachmentBlock>().toList();
    expect(img.length, 1);
    expect(img.first.caption, 'Damaged unit');
    expect(blocks.whereType<PageBreakBlock>().length, 1);
    expect(
      blocks.whereType<HeadingBlock>().any((h) => h.text == 'Attachment'),
      isTrue,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/nod_template_test.dart`
Expected: FAIL — `ImageAttachmentBlock` found 0.

- [ ] **Step 3: Write minimal implementation**

In `lib/features/documents/templates/nod_template.dart`:

(a) Add imports near the other block imports:

```dart
import '../blocks/image_attachment_block.dart';
import '../blocks/page_break_block.dart';
```

(`heading_block.dart` and `spacer_block.dart` are already imported.)

(b) In `build`, the method returns a `<Block>[ ... ]` list literal ending with the `MultiSignatureBlock([...])`. Add a trailing collection-`if` + spread as the last element, after the closing `])` of `MultiSignatureBlock` and its comma:

```dart
      MultiSignatureBlock([
        SignatoryParty(name: i.hrManagerName, role: 'HR Manager'),
        SignatoryParty(
          name: i.employeeFullName,
          role: 'Employee (Acknowledged)',
        ),
      ]),
      if (i.attachmentBytes != null) ...[
        const PageBreakBlock(),
        const HeadingBlock('Attachment'),
        const SpacerBlock(8),
        ImageAttachmentBlock(
          i.attachmentBytes!,
          caption: i.attachmentCaption,
        ),
      ],
    ];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/nod_template_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the NOD golden test to confirm no-attachment output is unchanged**

Run: `flutter test test/features/documents/goldens/nod_pagination_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/nod_template.dart test/features/documents/templates/nod_template_test.dart
git commit -m "feat(documents): NOD appends optional image attachment page"
```

---

### Task 6: `ImageAttachmentField` — reusable form input

**Files:**
- Create: `lib/features/documents/inputs/image_attachment_field.dart`
- Test: `test/features/documents/inputs/image_attachment_field_test.dart`

**Interfaces:**
- Consumes: `file_picker` (`package:file_picker/file_picker.dart`), Flutter Material.
- Produces: `class ImageAttachmentField extends StatefulWidget` with constructor:
  - `bytes` (`Uint8List?`) — current image bytes (controlled by parent)
  - `caption` (`String?`) — current caption (controlled by parent)
  - `onPicked` (`void Function(Uint8List bytes, String fileName)`)
  - `onRemoved` (`VoidCallback`)
  - `onCaptionChanged` (`ValueChanged<String>`)

  Empty state shows an "Add image" `OutlinedButton`; attached state shows a thumbnail + filename + "Remove" button and a caption `TextFormField`. Used by Task 7.

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/inputs/image_attachment_field_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/inputs/image_attachment_field.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('empty state shows an Add image button, no Remove', (t) async {
    await t.pumpWidget(_host(ImageAttachmentField(
      bytes: null,
      caption: null,
      onPicked: (_, __) {},
      onRemoved: () {},
      onCaptionChanged: (_) {},
    )));
    expect(find.text('Add image'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('attached state shows thumbnail, Remove, and caption field',
      (t) async {
    await t.pumpWidget(_host(ImageAttachmentField(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      caption: 'cap',
      onPicked: (_, __) {},
      onRemoved: () {},
      onCaptionChanged: (_) {},
    )));
    expect(find.text('Add image'), findsNothing);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('Remove triggers onRemoved', (t) async {
    var removed = false;
    await t.pumpWidget(_host(ImageAttachmentField(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      caption: null,
      onPicked: (_, __) {},
      onRemoved: () => removed = true,
      onCaptionChanged: (_) {},
    )));
    await t.tap(find.text('Remove'));
    await t.pump();
    expect(removed, isTrue);
  });

  testWidgets('editing the caption triggers onCaptionChanged', (t) async {
    String? captured;
    await t.pumpWidget(_host(ImageAttachmentField(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      caption: null,
      onPicked: (_, __) {},
      onRemoved: () {},
      onCaptionChanged: (v) => captured = v,
    )));
    await t.enterText(find.byType(TextFormField), 'CCTV still');
    expect(captured, 'CCTV still');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/inputs/image_attachment_field_test.dart`
Expected: FAIL — `image_attachment_field.dart` not found / `ImageAttachmentField` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/documents/inputs/image_attachment_field.dart`:

```dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Optional image attachment picker for memo forms (NTE/NOD).
///
/// The image is generation-time only — the parent holds [bytes] in the
/// template inputs and never persists them. This widget is "controlled":
/// [bytes] and [caption] come from the parent; picking/removing/caption edits
/// are reported via callbacks.
class ImageAttachmentField extends StatefulWidget {
  final Uint8List? bytes;
  final String? caption;
  final void Function(Uint8List bytes, String fileName) onPicked;
  final VoidCallback onRemoved;
  final ValueChanged<String> onCaptionChanged;

  const ImageAttachmentField({
    super.key,
    required this.bytes,
    required this.caption,
    required this.onPicked,
    required this.onRemoved,
    required this.onCaptionChanged,
  });

  @override
  State<ImageAttachmentField> createState() => _ImageAttachmentFieldState();
}

class _ImageAttachmentFieldState extends State<ImageAttachmentField> {
  String? _fileName;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() => _fileName = file.name);
    widget.onPicked(bytes, file.name);
  }

  void _remove() {
    setState(() => _fileName = null);
    widget.onRemoved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = widget.bytes;

    if (bytes == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.image_outlined, size: 18),
          label: const Text('Add image'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                bytes,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                // Defensive: a non-decodable byte list shouldn't crash the form.
                errorBuilder: (_, __, ___) => Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _fileName ?? 'Attached image',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _remove,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Remove'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: widget.caption ?? '',
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            labelText: 'Caption (optional)',
            hintText: 'e.g. CCTV still, 2026-06-20 3:14 PM',
          ),
          onChanged: widget.onCaptionChanged,
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/inputs/image_attachment_field_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/inputs/image_attachment_field.dart test/features/documents/inputs/image_attachment_field_test.dart
git commit -m "feat(documents): reusable ImageAttachmentField input"
```

---

### Task 7: Wire `ImageAttachmentField` into `NteForm` and `NodForm`

**Files:**
- Modify: `lib/features/documents/forms/nte_form.dart`
- Modify: `lib/features/documents/forms/nod_form.dart`
- Test: `test/features/documents/forms/memo_attachment_form_test.dart`

**Interfaces:**
- Consumes: `ImageAttachmentField` (Task 6), `NteInputs`/`NodInputs` attachment fields + `copyWith` (Tasks 2/3).
- Produces: both forms render an "Attachment (optional)" section that maps pick/remove/caption to `copyWith(attachmentBytes: ..., attachmentCaption: ...)` and reports via the existing `onChanged`.

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/forms/memo_attachment_form_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/forms/nte_form.dart';
import 'package:payroll_flutter/features/documents/forms/nod_form.dart';
import 'package:payroll_flutter/features/documents/inputs/image_attachment_field.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';

NteInputs _nte() => NteInputs(
      employeeId: 'e1',
      employeeFullName: 'Jane Doe',
      employeeFirstName: 'Jane',
      employeeLastName: 'Doe',
      employeePosition: 'Clerk',
      employeeDepartment: 'Ops',
      companyId: 'c1',
      companyName: 'Acme',
      dateIssued: DateTime(2026, 1, 1),
      responseDeadline: DateTime(2026, 1, 6),
      subjectSubtopic: '',
      charges: const [],
      applicableViolations: const [],
    );

NodInputs _nod() => NodInputs(
      employeeId: 'e1',
      employeeFullName: 'Jane Doe',
      companyId: 'c1',
      companyName: 'Acme',
      effectiveDate: DateTime(2026, 2, 1),
      issueDate: DateTime(2026, 1, 15),
    );

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('NteForm shows the attachment field', (t) async {
    await t.pumpWidget(_host(NteForm(
      initial: _nte(),
      employeeLocked: true,
      onChanged: (_) {},
      onEmployeeChanged: (_) {},
    )));
    await t.pump();
    expect(find.text('Attachment (optional)'), findsOneWidget);
    expect(find.byType(ImageAttachmentField), findsOneWidget);
  });

  testWidgets('NodForm shows the attachment field', (t) async {
    await t.pumpWidget(_host(NodForm(
      initial: _nod(),
      employeeLocked: true,
      onChanged: (_) {},
      onEmployeeChanged: (_) {},
    )));
    await t.pump();
    expect(find.text('Attachment (optional)'), findsOneWidget);
    expect(find.byType(ImageAttachmentField), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/forms/memo_attachment_form_test.dart`
Expected: FAIL — `Attachment (optional)` not found / `ImageAttachmentField` import unused.

- [ ] **Step 3: Wire into `NteForm`**

In `lib/features/documents/forms/nte_form.dart`:

(a) Add import:

```dart
import '../inputs/image_attachment_field.dart';
```

(b) At the end of the `ListView`'s `children:` list, after the `ViolationsEditor(...)` block (the current last child), add:

```dart
      const SizedBox(height: 16),
      _label('Attachment (optional)'),
      const SizedBox(height: 4),
      ImageAttachmentField(
        bytes: _i.attachmentBytes,
        caption: _i.attachmentCaption,
        onPicked: (bytes, _) => _set(_i.copyWith(attachmentBytes: bytes)),
        onRemoved: () => _set(
          _i.copyWith(attachmentBytes: null, attachmentCaption: null),
        ),
        onCaptionChanged: (v) =>
            _set(_i.copyWith(attachmentCaption: v.isEmpty ? null : v)),
      ),
```

- [ ] **Step 4: Wire into `NodForm`**

In `lib/features/documents/forms/nod_form.dart`:

(a) Add import:

```dart
import '../inputs/image_attachment_field.dart';
```

(b) At the end of the `ListView`'s `children:` list, after the final `DateField` for `effectiveDate` and its `_error('effectiveDate')`, add:

```dart
          const SizedBox(height: 16),
          _label('Attachment (optional)'),
          const SizedBox(height: 4),
          ImageAttachmentField(
            bytes: _i.attachmentBytes,
            caption: _i.attachmentCaption,
            onPicked: (bytes, _) => _set(_i.copyWith(attachmentBytes: bytes)),
            onRemoved: () => _set(
              _i.copyWith(attachmentBytes: null, attachmentCaption: null),
            ),
            onCaptionChanged: (v) =>
                _set(_i.copyWith(attachmentCaption: v.isEmpty ? null : v)),
          ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/documents/forms/memo_attachment_form_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/forms/nte_form.dart lib/features/documents/forms/nod_form.dart test/features/documents/forms/memo_attachment_form_test.dart
git commit -m "feat(documents): wire image attachment field into NTE & NOD forms"
```

---

### Task 8: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Static analysis**

Run: `flutter analyze lib/features/documents test/features/documents`
Expected: "No issues found!" (or only pre-existing, unrelated warnings). Fix any new analyzer errors/warnings introduced by this work (e.g. unused imports).

- [ ] **Step 2: Run the full documents test suite**

Run: `flutter test test/features/documents`
Expected: All pass, including the existing golden pagination tests (proves no-attachment output is byte-identical to before).

- [ ] **Step 3: Manual smoke test (desktop)**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`

Then:
1. Open Documents → generate a **Notice to Explain** for an employee.
2. Scroll to **Attachment (optional)** → click **Add image** → pick a PNG/JPG.
3. Confirm the thumbnail + filename appear, type a caption.
4. Confirm the **live preview** shows a new final page with the "Attachment" heading, the image, and the caption.
5. Click **Generate** → confirm the preview page is present; **Download** the PDF and confirm the image is embedded.
6. Open the **saved** document from the Documents hub (`/documents/view/:id`) → confirm it re-renders **without** the image (generation-time only, as designed) and without errors.
7. Repeat 1–6 for a **Notice of Decision**.
8. Remove the image via **Remove** and confirm the attachment page disappears from the live preview.

- [ ] **Step 4: Final no-op commit check**

Run: `git status`
Expected: clean working tree (all changes already committed in Tasks 1–7).

---

## Self-Review

**Spec coverage:**
- "Generation-time only, never persisted" → Tasks 2 & 3 exclude fields from `toJson`/`fromJson`; Task 8 step 6 verifies re-render omits the image. ✓
- "Mirror logoBytes" → Tasks 2/3 add binary field alongside `logoBytes`, excluded from JSON. ✓
- `ImageAttachmentBlock` → Task 1. ✓
- Inputs fields on NTE & NOD → Tasks 2 & 3. ✓
- `ImageAttachmentField` (file_picker) → Task 6. ✓
- Forms wiring → Task 7. ✓
- `build()` appends "Attachment" page only when present → Tasks 4 & 5, with golden tests proving byte-identical no-attachment output. ✓
- No change to generate_screen/repository/renderer → confirmed; not touched. ✓
- Tests: block, build, toJson-exclusion, copyWith, field widget, form wiring → all covered. ✓

**Placeholder scan:** No TBD/TODO; all steps have concrete code and exact commands. The only conditional instruction is Task 5 Step 1's "use the file's actual valid-inputs helper" — mitigated by inline fallback construction details. ✓

**Type consistency:** `attachmentBytes` (`Uint8List?`) and `attachmentCaption` (`String?`) used identically across Tasks 2–7. `ImageAttachmentBlock(Uint8List, {String? caption})` matches its use in Tasks 4/5. `ImageAttachmentField` callback signatures (`onPicked(Uint8List, String)`, `onRemoved()`, `onCaptionChanged(String)`) match the wiring in Task 7. ✓
