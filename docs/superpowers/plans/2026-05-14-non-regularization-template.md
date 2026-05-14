# Notice of Non-Regularization Template — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Notice of Non-Regularization as the 4th document template in the existing doc-templates feature, generated through the same ephemeral form-to-PDF pipeline as Quitclaim / COE / NTE.

**Architecture:** New `DocumentTemplate` subclass following the v1 pattern. One new block (`LabelledBulletListBlock`) for the "Standard: / Finding:" bullet structure. Two backward-compatible block extensions (`LetterMetaBlock` — optional position row, nullable subject, optional dividers; `SignatureBlock` — nullable date for hand-fill lines). One new form widget (`findings_editor.dart`). Single registry entry to make the picker show it; `generate_screen.dart` gets a new branch. No schema changes, no new dependencies.

**Tech Stack:** Flutter, Riverpod, `pdf` package, `printing`, `flutter_test`, `intl`. The Dart package is `payroll_flutter`; tests run via `flutter test`.

**Spec:** [`docs/superpowers/specs/2026-05-14-non-regularization-template-design.md`](../specs/2026-05-14-non-regularization-template-design.md)

---

## File Structure

**Create:**
- `lib/features/documents/blocks/labelled_bullet_list_block.dart` — new block
- `lib/features/documents/templates/non_reg_inputs.dart` — typed inputs
- `lib/features/documents/templates/non_reg_validate.dart` — pure validation
- `lib/features/documents/templates/non_reg_template.dart` — DocumentTemplate impl + build() + canonical copy
- `lib/features/documents/forms/non_reg_form.dart` — form pane
- `lib/features/documents/inputs/findings_editor.dart` — findings repeater widget
- `test/features/documents/blocks/labelled_bullet_list_block_test.dart`
- `test/features/documents/templates/non_reg_validate_test.dart`
- `test/features/documents/templates/non_reg_autofill_test.dart`
- `test/features/documents/templates/non_reg_build_test.dart`
- `test/features/documents/goldens/non_reg_pagination_test.dart`

**Modify:**
- `lib/features/documents/blocks/letter_meta_block.dart` — add `position`, nullable `subject`, `showDividers`
- `lib/features/documents/blocks/signature_block.dart` — make `date` nullable, hand-fill when null
- `lib/features/documents/templates/template_registry.dart` — add `NonRegTemplate()` to `kTemplates`
- `lib/features/documents/generate_screen.dart` — add NonReg branch in `_runAutofill`, `_formFor`, `_previewFor`
- `test/features/documents/blocks/letterhead_blocks_test.dart` — add assertions for new fields
- `test/features/documents/blocks/signature_blocks_test.dart` — add hand-fill rendering assertion

---

## Phase 1 — LabelledBulletListBlock

### Task 1: Block class + types (no rendering yet)

**Files:**
- Create: `test/features/documents/blocks/labelled_bullet_list_block_test.dart`
- Create: `lib/features/documents/blocks/labelled_bullet_list_block.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/blocks/labelled_bullet_list_block_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/labelled_bullet_list_block.dart';

void main() {
  test('LabelledBulletListBlock stores items', () {
    const block = LabelledBulletListBlock(items: [
      LabelledBulletItem(leadBold: 'Standard', body: 'The standard body.'),
      LabelledBulletItem(leadBold: 'Finding', body: 'The finding body.'),
    ]);
    expect(block.items.length, 2);
    expect(block.items.first.leadBold, 'Standard');
    expect(block.items.first.body, 'The standard body.');
    expect(block.items.first.children, isEmpty);
  });

  test('LabelledBulletItem holds nested children', () {
    const item = LabelledBulletItem(
      leadBold: 'Finding',
      body: 'Parent finding.',
      children: [
        LabelledBulletItem(leadBold: 'Detail A', body: 'Body A.'),
        LabelledBulletItem(leadBold: 'Detail B', body: 'Body B.'),
      ],
    );
    expect(item.children.length, 2);
    expect(item.children[0].leadBold, 'Detail A');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/labelled_bullet_list_block_test.dart`

Expected: FAIL — `Target of URI doesn't exist: 'package:payroll_flutter/features/documents/blocks/labelled_bullet_list_block.dart'`.

- [ ] **Step 3: Write minimal implementation (no rendering yet)**

Create `lib/features/documents/blocks/labelled_bullet_list_block.dart`:

```dart
import 'package:pdf/widgets.dart' as pw;
import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

class LabelledBulletItem {
  final String leadBold;
  final String body;
  final List<LabelledBulletItem> children;
  const LabelledBulletItem({
    required this.leadBold,
    required this.body,
    this.children = const [],
  });
}

/// Bullet list where each item has a bold lead label followed by a plain
/// body span. Supports ONE level of nested sub-bullets (rendered with the
/// `○` glyph). Used by Non-Reg findings sections, and reusable by other
/// memo-style HR templates with the same pattern.
class LabelledBulletListBlock extends Block {
  final List<LabelledBulletItem> items;
  const LabelledBulletListBlock({required this.items});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    // Rendering implemented in Task 2.
    return pw.SizedBox.shrink();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/labelled_bullet_list_block_test.dart`

Expected: PASS — both tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/blocks/labelled_bullet_list_block.dart \
        test/features/documents/blocks/labelled_bullet_list_block_test.dart
git commit -m "feat(documents): scaffold LabelledBulletListBlock types"
```

### Task 2: Render flat list to PDF

**Files:**
- Modify: `lib/features/documents/blocks/labelled_bullet_list_block.dart`
- Modify: `test/features/documents/blocks/labelled_bullet_list_block_test.dart`

- [ ] **Step 1: Add failing render test**

Append to `test/features/documents/blocks/labelled_bullet_list_block_test.dart`, inside the existing `main()` block:

```dart
  test('flat list renders without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const LabelledBulletListBlock(items: [
        LabelledBulletItem(leadBold: 'Standard', body: 'Body 1'),
        LabelledBulletItem(leadBold: 'Finding', body: 'Body 2'),
      ]).toPdf(theme),
      returnsNormally,
    );
  });

  test('flat list produces a Column with one row per top-level item', () {
    final theme = PdfTheme.testStub();
    final widget = const LabelledBulletListBlock(items: [
      LabelledBulletItem(leadBold: 'A', body: 'a'),
      LabelledBulletItem(leadBold: 'B', body: 'b'),
      LabelledBulletItem(leadBold: 'C', body: 'c'),
    ]).toPdf(theme);
    expect(widget, isA<pw.Column>());
    final col = widget as pw.Column;
    expect(col.children.length, 3);
  });
```

You will need to add this import at the top of the test file:

```dart
import 'package:pdf/widgets.dart' as pw;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/labelled_bullet_list_block_test.dart`

Expected: FAIL — the new "produces a Column" test fails because `toPdf` returns `SizedBox.shrink()`.

- [ ] **Step 3: Implement flat-list rendering**

Replace the `toPdf` method in `lib/features/documents/blocks/labelled_bullet_list_block.dart`:

```dart
  @override
  pw.Widget toPdf(PdfTheme theme) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final item in items) _row(theme, item, nested: false),
      ],
    );
  }

  pw.Widget _row(PdfTheme theme, LabelledBulletItem item,
      {required bool nested}) {
    final glyph = nested ? '○' : '•';
    final indent = nested ? 36.0 : 12.0;
    return pw.Padding(
      padding: pw.EdgeInsets.only(left: indent, bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 14,
            child: pw.Text(
              glyph,
              style: pw.TextStyle(
                fontSize: theme.bodySize,
                color: theme.textColor,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: pw.TextStyle(
                  fontSize: theme.bodySize,
                  color: theme.textColor,
                ),
                children: [
                  pw.TextSpan(
                    text: '${item.leadBold}: ',
                    style:
                        pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.TextSpan(text: item.body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/labelled_bullet_list_block_test.dart`

Expected: PASS — all four tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/blocks/labelled_bullet_list_block.dart \
        test/features/documents/blocks/labelled_bullet_list_block_test.dart
git commit -m "feat(documents): render flat LabelledBulletListBlock to PDF"
```

### Task 3: Render nested sub-bullets (one level)

**Files:**
- Modify: `lib/features/documents/blocks/labelled_bullet_list_block.dart`
- Modify: `test/features/documents/blocks/labelled_bullet_list_block_test.dart`

- [ ] **Step 1: Add failing nested-render test**

Append to `test/features/documents/blocks/labelled_bullet_list_block_test.dart`:

```dart
  test('nested children flatten into the column under the parent', () {
    final theme = PdfTheme.testStub();
    final widget = const LabelledBulletListBlock(items: [
      LabelledBulletItem(
        leadBold: 'Finding',
        body: 'Parent body.',
        children: [
          LabelledBulletItem(leadBold: 'Sub A', body: 'a'),
          LabelledBulletItem(leadBold: 'Sub B', body: 'b'),
        ],
      ),
    ]).toPdf(theme);
    final col = widget as pw.Column;
    // 1 parent row + 2 child rows = 3 entries.
    expect(col.children.length, 3);
  });

  test('depth-2 grandchildren are ignored (one-level nesting limit)', () {
    final theme = PdfTheme.testStub();
    final widget = const LabelledBulletListBlock(items: [
      LabelledBulletItem(
        leadBold: 'Finding',
        body: 'Parent.',
        children: [
          LabelledBulletItem(
            leadBold: 'Sub A',
            body: 'a',
            // These deeper-level children must NOT appear in output.
            children: [
              LabelledBulletItem(leadBold: 'Deeper', body: 'd'),
            ],
          ),
        ],
      ),
    ]).toPdf(theme);
    final col = widget as pw.Column;
    // 1 parent + 1 child = 2 entries; grandchild dropped.
    expect(col.children.length, 2);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/labelled_bullet_list_block_test.dart`

Expected: FAIL — "nested children flatten" expects 3 children but the current Column has 1 (children are stored but not rendered).

- [ ] **Step 3: Implement nested rendering**

Replace the `toPdf` method in `lib/features/documents/blocks/labelled_bullet_list_block.dart`:

```dart
  @override
  pw.Widget toPdf(PdfTheme theme) {
    final rows = <pw.Widget>[];
    for (final item in items) {
      rows.add(_row(theme, item, nested: false));
      // One-level nesting: walk children; grandchildren are intentionally
      // not rendered. See spec §"New blocks" — Non-Reg sources have at
      // most 2 levels.
      for (final child in item.children) {
        rows.add(_row(theme, child, nested: true));
      }
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows,
    );
  }
```

The existing `_row` helper is unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/labelled_bullet_list_block_test.dart`

Expected: PASS — all six tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/blocks/labelled_bullet_list_block.dart \
        test/features/documents/blocks/labelled_bullet_list_block_test.dart
git commit -m "feat(documents): render nested sub-bullets in LabelledBulletListBlock"
```

---

## Phase 2 — Extend LetterMetaBlock

### Task 4: Add optional `position` row

**Files:**
- Modify: `lib/features/documents/blocks/letter_meta_block.dart`
- Modify: `test/features/documents/blocks/letterhead_blocks_test.dart`

- [ ] **Step 1: Add failing test for `position` field**

Add this test to `test/features/documents/blocks/letterhead_blocks_test.dart` inside the existing `main()`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/letterhead_blocks_test.dart`

Expected: FAIL — `The named parameter 'position' isn't defined`.

- [ ] **Step 3: Add `position` field**

In `lib/features/documents/blocks/letter_meta_block.dart`, edit the class to:

```dart
class LetterMetaBlock extends Block {
  final DateTime date;
  final LetterParty to;
  final String? position;
  final LetterParty from;
  final String subject;
  const LetterMetaBlock({
    required this.date,
    required this.to,
    this.position,
    required this.from,
    required this.subject,
  });
```

In the `toPdf` method, locate the existing block of `row(...)` calls:

```dart
        row('Date:', value(formatter.format(date))),
        row('To:', partyValue(to)),
        row('From:', partyValue(from)),
        row('Subject:', value(subject)),
```

and insert the position row between `'To:'` and `'From:'`:

```dart
        row('Date:', value(formatter.format(date))),
        row('To:', partyValue(to)),
        if (position != null && position!.isNotEmpty)
          row('Position:', value(position!)),
        row('From:', partyValue(from)),
        row('Subject:', value(subject)),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/letterhead_blocks_test.dart`

Expected: PASS — all tests including the original three remain green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/blocks/letter_meta_block.dart \
        test/features/documents/blocks/letterhead_blocks_test.dart
git commit -m "feat(documents): LetterMetaBlock — add optional Position row"
```

### Task 5: Make `subject` nullable; suppress row when null

**Files:**
- Modify: `lib/features/documents/blocks/letter_meta_block.dart`
- Modify: `test/features/documents/blocks/letterhead_blocks_test.dart`

- [ ] **Step 1: Add failing test for null subject**

Add to `test/features/documents/blocks/letterhead_blocks_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/letterhead_blocks_test.dart`

Expected: FAIL — `The argument type 'Null' can't be assigned to the parameter type 'String'`.

- [ ] **Step 3: Make `subject` nullable**

In `lib/features/documents/blocks/letter_meta_block.dart`, change the field:

```dart
  final String? subject;
```

Change the constructor parameter from `required this.subject` to `this.subject`:

```dart
  const LetterMetaBlock({
    required this.date,
    required this.to,
    this.position,
    required this.from,
    this.subject,
  });
```

Update the Subject row to guard on null/empty:

```dart
        if (subject != null && subject!.isNotEmpty)
          row('Subject:', value(subject!)),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/letterhead_blocks_test.dart`

Expected: PASS.

- [ ] **Step 5: Verify NTE template still compiles**

The NTE template passes `subject: i.finalSubject` (a non-null String). Run the full test suite to ensure nothing else broke:

Run: `flutter test test/features/documents/`

Expected: PASS — all existing tests remain green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/blocks/letter_meta_block.dart \
        test/features/documents/blocks/letterhead_blocks_test.dart
git commit -m "feat(documents): LetterMetaBlock — nullable subject"
```

### Task 6: Add `showDividers` flag

**Files:**
- Modify: `lib/features/documents/blocks/letter_meta_block.dart`
- Modify: `test/features/documents/blocks/letterhead_blocks_test.dart`

- [ ] **Step 1: Add failing test**

Add to `test/features/documents/blocks/letterhead_blocks_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/letterhead_blocks_test.dart`

Expected: FAIL — `The named parameter 'showDividers' isn't defined`.

- [ ] **Step 3: Add `showDividers` field**

In `lib/features/documents/blocks/letter_meta_block.dart`:

```dart
  final bool showDividers;
  const LetterMetaBlock({
    required this.date,
    required this.to,
    this.position,
    required this.from,
    this.subject,
    this.showDividers = true,
  });
```

In `toPdf`, replace the existing `divider` declaration with a conditional and guard the two `divider` widgets in the Column:

```dart
    final divider = showDividers
        ? pw.Divider(color: PdfColors.grey400, height: 1)
        : pw.SizedBox.shrink();
```

(The two `divider` calls in the existing `pw.Column` children list remain — they become `SizedBox.shrink()` when off.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/letterhead_blocks_test.dart`

Expected: PASS.

- [ ] **Step 5: Verify nothing else broke**

Run: `flutter test test/features/documents/`

Expected: PASS — all existing tests remain green (NTE's `MemoHeaderBlock` doesn't pass `showDividers`, defaults to `true`, behavior unchanged).

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/blocks/letter_meta_block.dart \
        test/features/documents/blocks/letterhead_blocks_test.dart
git commit -m "feat(documents): LetterMetaBlock — optional dividers"
```

---

## Phase 3 — Extend SignatureBlock

### Task 7: Make `date` nullable with hand-fill rendering

**Files:**
- Modify: `lib/features/documents/blocks/signature_block.dart`
- Modify: `test/features/documents/blocks/signature_blocks_test.dart`

- [ ] **Step 1: Add failing test**

Add to `test/features/documents/blocks/signature_blocks_test.dart` inside `main()`:

```dart
  test('SignatureBlock accepts null date', () {
    const b = SignatureBlock(name: 'Donald', role: 'Employee', date: null);
    expect(b.date, isNull);
    expect(b.name, 'Donald');
  });

  test('SignatureBlock renders with null date without throwing', () {
    final theme = PdfTheme.testStub();
    expect(
      () => const SignatureBlock(name: 'X', role: '', date: null).toPdf(theme),
      returnsNormally,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/blocks/signature_blocks_test.dart`

Expected: FAIL — `The argument type 'Null' can't be assigned to the parameter type 'DateTime'`.

- [ ] **Step 3: Make `date` nullable**

In `lib/features/documents/blocks/signature_block.dart`:

```dart
class SignatureBlock extends Block {
  final String? name;
  final String? role;
  final DateTime? date;
  const SignatureBlock({this.name, this.role, this.date});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final fmt = DateFormat('MMMM d, yyyy');
    final dateLine = date == null
        ? 'Date: _______________________'
        : 'Date: ${fmt.format(date!)}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 220,
          padding: const pw.EdgeInsets.only(bottom: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
            ),
          ),
          child: pw.Text(
            name ?? '',
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              color: theme.textColor,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        if (role != null && role!.isNotEmpty)
          pw.Text(
            role!,
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              fontWeight: pw.FontWeight.bold,
              color: theme.textColor,
            ),
          ),
        pw.Text(
          dateLine,
          style: pw.TextStyle(
            fontSize: theme.bodySize,
            color: theme.textColor,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/blocks/signature_blocks_test.dart`

Expected: PASS.

- [ ] **Step 5: Verify nothing else broke**

Run: `flutter test test/features/documents/`

Expected: PASS — Quitclaim/COE/NTE all pass non-null dates, behavior unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/blocks/signature_block.dart \
        test/features/documents/blocks/signature_blocks_test.dart
git commit -m "feat(documents): SignatureBlock — nullable date for hand-fill lines"
```

---

## Phase 4 — NonRegInputs

### Task 8: Create the input model

**Files:**
- Create: `lib/features/documents/templates/non_reg_inputs.dart`

- [ ] **Step 1: Write the file directly (no test — this is a pure type file used by every later test)**

Create `lib/features/documents/templates/non_reg_inputs.dart`:

```dart
import 'document_template.dart';

class SubFinding {
  final String title;
  final String body;
  const SubFinding({required this.title, required this.body});
}

class FindingSection {
  final String title;
  final String standard;
  final String finding;
  final List<SubFinding> subFindings;
  const FindingSection({
    required this.title,
    required this.standard,
    required this.finding,
    this.subFindings = const [],
  });
}

class NonRegInputs extends TemplateInputs {
  final String employeeId;
  final String employeeFullName;
  final String employeeLastName;
  final String employeePosition;
  final String companyId;
  final String companyName;
  final String? companyAddress;
  final String? hrManagerName;
  final DateTime dateIssued;
  final DateTime? probationaryStart;
  final DateTime? probationaryEnd;
  final DateTime? effectiveEndDate;
  final String salutationName;
  final String noteOnScope;
  final List<FindingSection> findings;
  final String witnessName;

  NonRegInputs({
    required this.employeeId,
    required this.employeeFullName,
    required this.employeeLastName,
    required this.employeePosition,
    required this.companyId,
    required this.companyName,
    this.companyAddress,
    this.hrManagerName,
    required this.dateIssued,
    this.probationaryStart,
    this.probationaryEnd,
    this.effectiveEndDate,
    required this.salutationName,
    this.noteOnScope = '',
    required this.findings,
    this.witnessName = '',
  });

  NonRegInputs copyWith({
    String? employeeId,
    String? employeeFullName,
    String? employeeLastName,
    String? employeePosition,
    String? companyId,
    String? companyName,
    String? companyAddress,
    String? hrManagerName,
    DateTime? dateIssued,
    DateTime? probationaryStart,
    DateTime? probationaryEnd,
    DateTime? effectiveEndDate,
    String? salutationName,
    String? noteOnScope,
    List<FindingSection>? findings,
    String? witnessName,
  }) =>
      NonRegInputs(
        employeeId: employeeId ?? this.employeeId,
        employeeFullName: employeeFullName ?? this.employeeFullName,
        employeeLastName: employeeLastName ?? this.employeeLastName,
        employeePosition: employeePosition ?? this.employeePosition,
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        companyAddress: companyAddress ?? this.companyAddress,
        hrManagerName: hrManagerName ?? this.hrManagerName,
        dateIssued: dateIssued ?? this.dateIssued,
        probationaryStart: probationaryStart ?? this.probationaryStart,
        probationaryEnd: probationaryEnd ?? this.probationaryEnd,
        effectiveEndDate: effectiveEndDate ?? this.effectiveEndDate,
        salutationName: salutationName ?? this.salutationName,
        noteOnScope: noteOnScope ?? this.noteOnScope,
        findings: findings ?? this.findings,
        witnessName: witnessName ?? this.witnessName,
      );

  @override
  Map<String, dynamic> toDebugMap() => {
        'employeeId': employeeId,
        'companyId': companyId,
        'findingCount': findings.length,
        'subFindingCount':
            findings.fold<int>(0, (n, f) => n + f.subFindings.length),
      };
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/documents/templates/non_reg_inputs.dart`

Expected: `No issues found!` (or analyzer prints `info` only — no warnings or errors).

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/templates/non_reg_inputs.dart
git commit -m "feat(documents): NonRegInputs — typed input model"
```

---

## Phase 5 — Validation

### Task 9: Required fields + findings minimum

**Files:**
- Create: `test/features/documents/templates/non_reg_validate_test.dart`
- Create: `lib/features/documents/templates/non_reg_validate.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/templates/non_reg_validate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_validate.dart';

void main() {
  NonRegInputs valid() => NonRegInputs(
        employeeId: 'e1',
        employeeFullName: 'Jamaica Vidal',
        employeeLastName: 'Vidal',
        employeePosition: 'HR Assistant',
        companyId: 'c1',
        companyName: 'LUXIUM TRADING CO.',
        hrManagerName: 'Brixter Del Mundo',
        dateIssued: DateTime(2025, 12, 3),
        probationaryStart: DateTime(2025, 6, 9),
        probationaryEnd: DateTime(2025, 12, 6),
        effectiveEndDate: DateTime(2025, 12, 5),
        salutationName: 'Ms. Vidal',
        findings: [
          const FindingSection(
            title: 'Failure to Meet Performance Standards',
            standard: 'Annex B requires demonstrating skills.',
            finding: 'Output has been substandard.',
            subFindings: [
              SubFinding(
                title: 'Lack of Core Competency',
                body: 'You failed to demonstrate working knowledge.',
              ),
            ],
          ),
        ],
      );

  test('valid inputs produce no errors', () {
    expect(validateNonReg(valid()), isEmpty);
  });

  test('empty employeeId flagged', () {
    final i = valid().copyWith(employeeId: '');
    expect(validateNonReg(i).any((e) => e.field == 'employee'), true);
  });

  test('empty companyId flagged', () {
    final i = valid().copyWith(companyId: '');
    expect(validateNonReg(i).any((e) => e.field == 'company'), true);
  });

  test('missing hrManagerName flagged', () {
    final i = valid().copyWith(hrManagerName: '');
    expect(
      validateNonReg(i).any((e) => e.field == 'hrManagerName'),
      true,
    );
  });

  test('empty findings list flagged', () {
    final i = valid().copyWith(findings: const []);
    expect(validateNonReg(i).any((e) => e.field == 'findings'), true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/non_reg_validate_test.dart`

Expected: FAIL — `Target of URI doesn't exist: 'package:payroll_flutter/features/documents/templates/non_reg_validate.dart'`.

- [ ] **Step 3: Implement validation**

Create `lib/features/documents/templates/non_reg_validate.dart`:

```dart
import 'document_template.dart';
import 'non_reg_inputs.dart';

List<ValidationError> validateNonReg(NonRegInputs i) {
  final errs = <ValidationError>[];
  if (i.employeeId.isEmpty) {
    errs.add(const ValidationError('employee', 'Select an employee.'));
  }
  if (i.companyId.isEmpty) {
    errs.add(const ValidationError('company', 'Select a hiring entity.'));
  }
  if (i.hrManagerName == null || i.hrManagerName!.trim().isEmpty) {
    errs.add(const ValidationError(
        'hrManagerName', 'HR manager name is required.'));
  }
  if (i.salutationName.trim().isEmpty) {
    errs.add(const ValidationError(
        'salutationName', 'Salutation cannot be empty.'));
  }
  if (i.probationaryStart == null) {
    errs.add(const ValidationError(
        'probationaryStart', 'Probationary start date is required.'));
  }
  if (i.probationaryEnd == null) {
    errs.add(const ValidationError(
        'probationaryEnd', 'Probationary end date is required.'));
  }
  if (i.effectiveEndDate == null) {
    errs.add(const ValidationError(
        'effectiveEndDate', 'Effective end date is required.'));
  }
  if (i.findings.isEmpty) {
    errs.add(const ValidationError(
        'findings', 'Add at least one finding section.'));
  }
  return errs;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/non_reg_validate_test.dart`

Expected: PASS — all five tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/non_reg_validate.dart \
        test/features/documents/templates/non_reg_validate_test.dart
git commit -m "feat(documents): NonRegInputs validation — required fields"
```

### Task 10: Per-finding + per-sub-finding validation

**Files:**
- Modify: `lib/features/documents/templates/non_reg_validate.dart`
- Modify: `test/features/documents/templates/non_reg_validate_test.dart`

- [ ] **Step 1: Add failing tests**

Append inside `main()` in `test/features/documents/templates/non_reg_validate_test.dart`:

```dart
  test('empty finding title flagged', () {
    final i = valid().copyWith(findings: const [
      FindingSection(title: '', standard: 's', finding: 'f'),
    ]);
    expect(
      validateNonReg(i).any((e) => e.field == 'findings[0].title'),
      true,
    );
  });

  test('empty finding standard flagged', () {
    final i = valid().copyWith(findings: const [
      FindingSection(title: 'T', standard: '', finding: 'f'),
    ]);
    expect(
      validateNonReg(i).any((e) => e.field == 'findings[0].standard'),
      true,
    );
  });

  test('empty finding finding-body flagged', () {
    final i = valid().copyWith(findings: const [
      FindingSection(title: 'T', standard: 's', finding: ''),
    ]);
    expect(
      validateNonReg(i).any((e) => e.field == 'findings[0].finding'),
      true,
    );
  });

  test('empty sub-finding title flagged', () {
    final i = valid().copyWith(findings: const [
      FindingSection(
        title: 'T',
        standard: 's',
        finding: 'f',
        subFindings: [SubFinding(title: '', body: 'b')],
      ),
    ]);
    expect(
      validateNonReg(i)
          .any((e) => e.field == 'findings[0].subFindings[0].title'),
      true,
    );
  });

  test('empty sub-finding body flagged', () {
    final i = valid().copyWith(findings: const [
      FindingSection(
        title: 'T',
        standard: 's',
        finding: 'f',
        subFindings: [SubFinding(title: 't', body: '')],
      ),
    ]);
    expect(
      validateNonReg(i)
          .any((e) => e.field == 'findings[0].subFindings[0].body'),
      true,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/non_reg_validate_test.dart`

Expected: FAIL — none of the per-finding errors are produced.

- [ ] **Step 3: Implement per-finding validation**

Append to `validateNonReg` in `lib/features/documents/templates/non_reg_validate.dart`, right before `return errs;`:

```dart
  for (var fi = 0; fi < i.findings.length; fi++) {
    final f = i.findings[fi];
    if (f.title.trim().isEmpty) {
      errs.add(ValidationError(
          'findings[$fi].title', 'Finding title is required.'));
    }
    if (f.standard.trim().isEmpty) {
      errs.add(ValidationError(
          'findings[$fi].standard', 'Standard body is required.'));
    }
    if (f.finding.trim().isEmpty) {
      errs.add(ValidationError(
          'findings[$fi].finding', 'Finding body is required.'));
    }
    for (var si = 0; si < f.subFindings.length; si++) {
      final s = f.subFindings[si];
      if (s.title.trim().isEmpty) {
        errs.add(ValidationError(
          'findings[$fi].subFindings[$si].title',
          'Sub-finding title is required.',
        ));
      }
      if (s.body.trim().isEmpty) {
        errs.add(ValidationError(
          'findings[$fi].subFindings[$si].body',
          'Sub-finding body is required.',
        ));
      }
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/non_reg_validate_test.dart`

Expected: PASS — all 10 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/non_reg_validate.dart \
        test/features/documents/templates/non_reg_validate_test.dart
git commit -m "feat(documents): NonRegInputs validation — per-finding fields"
```

### Task 11: Date-ordering validation

**Files:**
- Modify: `lib/features/documents/templates/non_reg_validate.dart`
- Modify: `test/features/documents/templates/non_reg_validate_test.dart`

- [ ] **Step 1: Add failing tests**

Append inside `main()`:

```dart
  test('probationaryEnd before probationaryStart flagged', () {
    final i = valid().copyWith(
      probationaryStart: DateTime(2025, 12, 6),
      probationaryEnd: DateTime(2025, 6, 9),
    );
    expect(
      validateNonReg(i).any((e) => e.field == 'probationaryEnd'),
      true,
    );
  });

  test('effectiveEndDate before probationaryStart flagged', () {
    final i = valid().copyWith(
      effectiveEndDate: DateTime(2025, 6, 1),
    );
    expect(
      validateNonReg(i).any((e) => e.field == 'effectiveEndDate'),
      true,
    );
  });

  test('effectiveEndDate well after probationaryEnd flagged', () {
    final i = valid().copyWith(
      probationaryEnd: DateTime(2025, 12, 6),
      effectiveEndDate: DateTime(2026, 1, 1),
    );
    expect(
      validateNonReg(i).any((e) => e.field == 'effectiveEndDate'),
      true,
    );
  });

  test('effectiveEndDate within 7-day grace of probationaryEnd OK', () {
    final i = valid().copyWith(
      probationaryEnd: DateTime(2025, 12, 6),
      effectiveEndDate: DateTime(2025, 12, 12), // +6 days = within grace
    );
    expect(
      validateNonReg(i).any((e) => e.field == 'effectiveEndDate'),
      false,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/non_reg_validate_test.dart`

Expected: FAIL — the new date-ordering tests fail.

- [ ] **Step 3: Implement date-ordering rules**

Append to `validateNonReg`, right before `return errs;`:

```dart
  final ps = i.probationaryStart;
  final pe = i.probationaryEnd;
  final ee = i.effectiveEndDate;
  if (ps != null && pe != null && pe.isBefore(ps)) {
    errs.add(const ValidationError(
        'probationaryEnd',
        'Probationary end must be on or after the probationary start.'));
  }
  if (ps != null && ee != null && ee.isBefore(ps)) {
    errs.add(const ValidationError(
        'effectiveEndDate',
        'Effective end date must be on or after the probationary start.'));
  }
  if (pe != null && ee != null) {
    final limit = pe.add(const Duration(days: 7));
    if (ee.isAfter(limit)) {
      errs.add(const ValidationError(
          'effectiveEndDate',
          'Effective end date must be on or before probationary end + 7 days.'));
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/non_reg_validate_test.dart`

Expected: PASS — all 14 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/non_reg_validate.dart \
        test/features/documents/templates/non_reg_validate_test.dart
git commit -m "feat(documents): NonRegInputs validation — date ordering"
```

---

## Phase 6 — NonRegTemplate scaffold

### Task 12: Template skeleton (id, name, gates, emptyInputs)

**Files:**
- Create: `lib/features/documents/templates/non_reg_template.dart`
- Create: `test/features/documents/templates/non_reg_autofill_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/templates/non_reg_autofill_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  test('template metadata', () {
    const t = NonRegTemplate();
    expect(t.id, 'non_reg');
    expect(t.name, 'Notice of Non-Regularization');
    expect(t.version, 1);
  });

  test('emptyInputs has today as dateIssued and empty findings', () {
    const t = NonRegTemplate();
    final i = t.emptyInputs();
    expect(i.findings, isEmpty);
    expect(i.employeeId, isEmpty);
    expect(i.companyId, isEmpty);
  });
}
```

Note: `gates()` is not unit-tested here because constructing an `AutofillContext` requires a real `WidgetRef`. The implementation returns `const []` and is exercised end-to-end by the picker rendering in manual testing (Task 22).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/non_reg_autofill_test.dart`

Expected: FAIL — `Target of URI doesn't exist: 'package:payroll_flutter/features/documents/templates/non_reg_template.dart'`.

- [ ] **Step 3: Write the template skeleton**

Create `lib/features/documents/templates/non_reg_template.dart`:

```dart
import 'package:flutter/material.dart' show Icons, IconData;

import '../blocks/block.dart';
import 'document_template.dart';
import 'non_reg_inputs.dart';
import 'non_reg_validate.dart';

class NonRegTemplate extends DocumentTemplate<NonRegInputs> {
  const NonRegTemplate();

  @override
  String get id => 'non_reg';
  @override
  String get name => 'Notice of Non-Regularization';
  @override
  String get description =>
      'Issued when a probationary employee fails to regularize.';
  @override
  IconData get icon => Icons.person_off_outlined;
  @override
  int get version => 1;

  @override
  NonRegInputs emptyInputs() {
    final today = DateTime.now();
    return NonRegInputs(
      employeeId: '',
      employeeFullName: '',
      employeeLastName: '',
      employeePosition: '',
      companyId: '',
      companyName: '',
      dateIssued: today,
      salutationName: '',
      findings: const [],
    );
  }

  @override
  Future<NonRegInputs> autofill(AutofillContext ctx) async => emptyInputs();

  @override
  List<Gate> gates(AutofillContext ctx) => const [];

  @override
  List<ValidationError> validate(NonRegInputs inputs) =>
      validateNonReg(inputs);

  @override
  List<Block> build(NonRegInputs i) => const [];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/non_reg_autofill_test.dart`

Expected: PASS — both tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/non_reg_template.dart \
        test/features/documents/templates/non_reg_autofill_test.dart
git commit -m "feat(documents): NonRegTemplate scaffold (metadata + empty build)"
```

### Task 13: Autofill (employee + company + HR manager)

**Files:**
- Modify: `lib/features/documents/templates/non_reg_template.dart`
- Modify: `test/features/documents/templates/non_reg_autofill_test.dart`

- [ ] **Step 1: Add failing test using a fake AutofillContext**

The existing autofill tests for Quitclaim/COE rely on real Riverpod providers. For Non-Reg we test pure-function behavior by constructing inputs directly: this task's `autofill` does NOT read providers (only Task 14 will).

Replace the body of `test/features/documents/templates/non_reg_autofill_test.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/features/documents/templates/document_template.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  test('template metadata', () {
    const t = NonRegTemplate();
    expect(t.id, 'non_reg');
    expect(t.name, 'Notice of Non-Regularization');
    expect(t.version, 1);
  });

  test('emptyInputs has empty findings and today as dateIssued', () {
    const t = NonRegTemplate();
    final i = t.emptyInputs();
    expect(i.findings, isEmpty);
    expect(i.employeeId, isEmpty);
  });

  testWidgets('autofill with employee + company copies basic fields',
      (tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (_, ref, __) {
          capturedRef = ref;
          return const SizedBox();
        }),
      ),
    );
    final emp = Employee(
      id: 'e1',
      firstName: 'Jamaica',
      middleName: null,
      lastName: 'Vidal',
      employeeNumber: null,
      hiringEntityId: 'c1',
      remittanceHiringEntityId: null,
      birthDate: null,
      hireDate: DateTime(2025, 6, 9),
      employmentStatus: 'PROBATIONARY',
    );
    final co = HiringEntity(
      id: 'c1',
      name: 'LUXIUM TRADING CO.',
      hrManagerName: 'Brixter Del Mundo',
    );
    const t = NonRegTemplate();
    final filled = await t.autofill(
      AutofillContext(employee: emp, company: co, ref: capturedRef),
    );
    expect(filled.employeeId, 'e1');
    expect(filled.employeeFullName, 'Jamaica Vidal');
    expect(filled.employeeLastName, 'Vidal');
    expect(filled.companyId, 'c1');
    expect(filled.companyName, 'LUXIUM TRADING CO.');
    expect(filled.hrManagerName, 'Brixter Del Mundo');
    expect(filled.salutationName, 'Vidal');
  });
}
```

**Important:** The `Employee` and `HiringEntity` constructors above use the field names from the real models. If the engineer finds the constructors require additional params (e.g., other fields that became required since this plan was written), supplement with the smallest valid set — do NOT change models to fit the test. Run `flutter analyze test/features/documents/templates/non_reg_autofill_test.dart` to discover any missing required params and add them with sensible defaults (null/empty strings).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/non_reg_autofill_test.dart`

Expected: FAIL — `filled.employeeId` is `''` (empty), not `'e1'`, because `autofill` still returns `emptyInputs()`.

- [ ] **Step 3: Implement basic autofill (no events yet)**

Replace `autofill` in `lib/features/documents/templates/non_reg_template.dart`:

```dart
  @override
  Future<NonRegInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();
    return NonRegInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeLastName: emp.lastName,
      employeePosition: '', // Employee model has no `position` field; HR fills.
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      hrManagerName: co?.hrManagerName,
      dateIssued: today,
      salutationName: emp.lastName,
      findings: const [],
    );
  }
```

Add this private helper at the bottom of `non_reg_template.dart` (same pattern used by `nte_template.dart` and `coe_template.dart`):

```dart
String _addressOf(dynamic co) {
  final parts = [
    co.addressLine1,
    co.addressLine2,
    [co.city, co.province, co.zipCode]
        .where((s) => s != null && (s as String).isNotEmpty)
        .join(', '),
  ].where((s) => s != null && (s as String).isNotEmpty).cast<String>().toList();
  return parts.join(' · ');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/non_reg_autofill_test.dart`

Expected: PASS — all three tests green. If the `Employee` or `HiringEntity` constructors required more parameters, the test setup adapted to that and the test now passes with autofill working.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/non_reg_template.dart \
        test/features/documents/templates/non_reg_autofill_test.dart
git commit -m "feat(documents): NonRegTemplate.autofill — basic employee + company"
```

### Task 14: Autofill probationary dates from HIRE event

**Files:**
- Modify: `lib/features/documents/templates/non_reg_template.dart`
- Modify: `test/features/documents/templates/non_reg_autofill_test.dart`

- [ ] **Step 1: Add failing test for date defaults**

Append to the test file inside `main()`:

```dart
  test('probationaryEnd defaults to start + 6 months when start known', () {
    // Pure function test — call a helper directly. The plan adds
    // `defaultProbationaryEnd(DateTime)` as a top-level function in
    // non_reg_template.dart to enable this test without Riverpod.
    final start = DateTime(2025, 6, 9);
    final end = defaultProbationaryEnd(start);
    expect(end, DateTime(2025, 12, 9));
  });
```

Add the import at the top of the test file:

```dart
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart'
    show NonRegTemplate, defaultProbationaryEnd;
```

(The existing `import '...non_reg_template.dart';` line should be replaced with the `show`-form above to keep `defaultProbationaryEnd` callable without leaking the entire library.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/non_reg_autofill_test.dart`

Expected: FAIL — `Undefined name 'defaultProbationaryEnd'`.

- [ ] **Step 3: Implement the helper and wire autofill**

In `lib/features/documents/templates/non_reg_template.dart`, **above** the `NonRegTemplate` class, add:

```dart
/// PH Labor Code default: probationary period is six months from the
/// hire date. HR can override via the lock/unlock toggle if a longer
/// period was stipulated in the employment contract.
DateTime defaultProbationaryEnd(DateTime start) {
  // Add 6 calendar months. Dart's DateTime does this safely: if the
  // target month has no equivalent day-of-month, the constructor wraps
  // into the next month (e.g. Aug 31 + 6 mo → Mar 3 the next year). For
  // a probation-end calculation that overshoot is acceptable and rare.
  return DateTime(start.year, start.month + 6, start.day);
}
```

Then in `autofill`, after building `co`, add the event read. Replace the `autofill` body with:

```dart
  @override
  Future<NonRegInputs> autofill(AutofillContext ctx) async {
    final emp = ctx.employee;
    if (emp == null) return emptyInputs();
    final co = ctx.company;
    final today = DateTime.now();
    // Pull the latest HIRE event; fall back to employee.hireDate (already
    // on the Employee model) if no event row exists.
    final hireRow = await ctx.ref.read(latestEmploymentEventProvider(
            (employeeId: emp.id, eventType: 'HIRE'))
        .future);
    DateTime? eventDate(Map<String, dynamic>? r) {
      if (r == null) return null;
      final v = r['event_date'] as String?;
      return v == null ? null : DateTime.parse(v);
    }
    final probStart = eventDate(hireRow) ?? emp.hireDate;
    final probEnd =
        probStart == null ? null : defaultProbationaryEnd(probStart);
    return NonRegInputs(
      employeeId: emp.id,
      employeeFullName: emp.fullName,
      employeeLastName: emp.lastName,
      employeePosition: '',
      companyId: co?.id ?? '',
      companyName: co?.name ?? '',
      companyAddress: co == null ? null : _addressOf(co),
      hrManagerName: co?.hrManagerName,
      dateIssued: today,
      probationaryStart: probStart,
      probationaryEnd: probEnd,
      effectiveEndDate: probEnd,
      salutationName: emp.lastName,
      findings: const [],
    );
  }
```

Add the import at the top of `non_reg_template.dart`:

```dart
import '../providers.dart';
```

(If `Employee` does not expose `hireDate`, drop the `?? emp.hireDate` fallback — `probStart` becomes simply `eventDate(hireRow)`. The Employee model in this codebase as of plan-write date has `hireDate` per migration `20260414000005_employees.sql`; verify by running `flutter analyze`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/non_reg_autofill_test.dart`

Expected: PASS — the `defaultProbationaryEnd` test passes. The pre-existing autofill test continues to pass; the HIRE-event provider returns null in the test (no DB), so `probStart` falls back to `null` or `emp.hireDate`. If the test fails because `emp.hireDate` is `null` and you want non-null assertions, update the seeded `emp` to include a hire date — but the test as written only asserts string fields, so it should remain green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/non_reg_template.dart \
        test/features/documents/templates/non_reg_autofill_test.dart
git commit -m "feat(documents): NonRegTemplate.autofill — probationary dates from HIRE"
```

---

## Phase 7 — Canonical copy + build()

### Task 15: Add canonical legal-copy const strings

**Files:**
- Modify: `lib/features/documents/templates/non_reg_template.dart`

- [ ] **Step 1: Lift legal copy verbatim from the source PDF**

The source PDF is `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/NOTICE OF NON-REGULARIZATION_VIDAL - Google Docs.pdf`. The relevant copy blocks (with `{placeholder}` markers replacing the JAM employee's specifics) are:

- **Intro 1:** "This letter serves as formal notification regarding the status of your probationary employment, which commenced on **{probationaryStart}** and is scheduled to end on **{probationaryEnd}**."
- **Intro 2:** "As stipulated in **Section 4 (Probationary Evaluation)** of your Employment Contract, the Company has evaluated your performance against the **Standards for Regularization** (Annex B). After a comprehensive review, we regret to inform you that you have not met the reasonable standards required to qualify for regular employment."
- **Note (optional):** "**Note on Scope of Evaluation:** {noteOnScope}"
- **Specifically lead-in:** "Specifically, you failed to meet the agreed-upon standards in the following areas:"
- **Decision:** "In view of the foregoing, your probationary employment will not be regularized and will cease effective at the close of business hours on **{effectiveEndDate}**."
- **Final pay:** "Please arrange to return your Company ID, access keys, and any other company property currently in your possession. Your Final Pay, including your pro-rated 13th-month pay, will be processed in accordance with **Section 14 (Final Pay)** of your contract and released upon completion of the clearance process."
- **Closing:** "We thank you for the time spent with the company and wish you the best in your future endeavors."
- **Acknowledgment:** "I acknowledge receipt of this notice. I understand that my signature attests only to the receipt of this letter and not necessarily my agreement with its contents."

Add these as `const String` near the top of `lib/features/documents/templates/non_reg_template.dart`, **directly above the `NonRegTemplate` class** (matching the pattern used in `nte_template.dart` and `coe_template.dart`):

```dart
// Canonical legal copy lifted verbatim from
// `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/NOTICE OF
// NON-REGULARIZATION_VIDAL - Google Docs.pdf`. Confirm wording with the
// user before merge (see Task 22).
const _specificallyLead =
    'Specifically, you failed to meet the agreed-upon standards in the '
    'following areas:';
const _finalPayText =
    'Please arrange to return your Company ID, access keys, and any other '
    'company property currently in your possession. Your Final Pay, '
    'including your pro-rated 13th-month pay, will be processed in '
    'accordance with Section 14 (Final Pay) of your contract and released '
    'upon completion of the clearance process.';
const _closingText =
    'We thank you for the time spent with the company and wish you the '
    'best in your future endeavors.';
const _acknowledgmentText =
    'I acknowledge receipt of this notice. I understand that my signature '
    'attests only to the receipt of this letter and not necessarily my '
    'agreement with its contents.';
```

Note that **intro 1**, **intro 2**, **note**, and **decision** contain inline bold spans, so they will NOT be plain strings — they are built as `EmphasisParagraphBlock` span lists in Task 16's `build()` body.

- [ ] **Step 2: Run analyzer to confirm no errors**

Run: `flutter analyze lib/features/documents/templates/non_reg_template.dart`

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/templates/non_reg_template.dart
git commit -m "feat(documents): canonical NonReg legal copy as const strings"
```

### Task 16: Build the block tree

**Files:**
- Modify: `lib/features/documents/templates/non_reg_template.dart`
- Create: `test/features/documents/templates/non_reg_build_test.dart`

- [ ] **Step 1: Write the failing build test**

Create `test/features/documents/templates/non_reg_build_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/labelled_bullet_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/letter_meta_block.dart';
import 'package:payroll_flutter/features/documents/blocks/page_break_block.dart';
import 'package:payroll_flutter/features/documents/blocks/section_heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_block.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  NonRegInputs seed({
    List<FindingSection> findings = const [],
    String noteOnScope = '',
    String witnessName = '',
  }) =>
      NonRegInputs(
        employeeId: 'e1',
        employeeFullName: 'Jamaica Vidal',
        employeeLastName: 'Vidal',
        employeePosition: 'HR Assistant',
        companyId: 'c1',
        companyName: 'LUXIUM TRADING CO.',
        hrManagerName: 'Brixter Del Mundo',
        dateIssued: DateTime(2025, 12, 3),
        probationaryStart: DateTime(2025, 6, 9),
        probationaryEnd: DateTime(2025, 12, 6),
        effectiveEndDate: DateTime(2025, 12, 5),
        salutationName: 'Ms. Vidal',
        noteOnScope: noteOnScope,
        findings: findings,
        witnessName: witnessName,
      );

  test('build starts with LetterMetaBlock', () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    expect(blocks.first, isA<LetterMetaBlock>());
  });

  test('build contains SUBJECT heading after meta', () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    final heading = blocks
        .whereType<HeadingBlock>()
        .firstWhere((h) => h.text.startsWith('SUBJECT'));
    expect(heading.text, 'SUBJECT: NOTICE OF NON-REGULARIZATION');
  });

  test('each finding produces SectionHeadingBlock + LabelledBulletListBlock',
      () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'A', standard: 's1', finding: 'f1'),
      FindingSection(title: 'B', standard: 's2', finding: 'f2'),
    ]));
    final headings = blocks.whereType<SectionHeadingBlock>().toList();
    final lists = blocks.whereType<LabelledBulletListBlock>().toList();
    expect(headings.length, 2);
    expect(lists.length, 2);
    expect(headings[0].number, 1);
    expect(headings[1].number, 2);
    expect(headings[0].title, 'A');
  });

  test('DECISION heading present after findings', () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    expect(
      blocks.whereType<HeadingBlock>().any((h) => h.text == 'DECISION'),
      true,
    );
  });

  test('PageBreakBlock separates main body from acknowledgment', () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    expect(blocks.whereType<PageBreakBlock>().length, 1);
  });

  test('ACKNOWLEDGMENT OF RECEIPT heading + 2 signature lines on page 2',
      () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    final pbIndex = blocks.indexWhere((b) => b is PageBreakBlock);
    final afterBreak = blocks.sublist(pbIndex + 1);
    expect(
      afterBreak.whereType<HeadingBlock>().any(
            (h) => h.text == 'ACKNOWLEDGMENT OF RECEIPT',
          ),
      true,
    );
    // HR signature (Sincerely, ...) is BEFORE the break; employee +
    // witness signatures are AFTER.
    expect(afterBreak.whereType<SignatureBlock>().length, 2);
  });

  test('noteOnScope conditionally inserted', () {
    const t = NonRegTemplate();
    final without = t.build(seed(findings: const [
      FindingSection(title: 'T', standard: 's', finding: 'f'),
    ]));
    final with_ = t.build(seed(
      findings: const [FindingSection(title: 'T', standard: 's', finding: 'f')],
      noteOnScope: 'Reassigned to LCT bazaar.',
    ));
    // Adding a non-empty noteOnScope inserts ONE extra block
    // (EmphasisParagraphBlock).
    expect(with_.length, without.length + 1);
  });

  test('sub-findings render as nested children in LabelledBulletListBlock',
      () {
    const t = NonRegTemplate();
    final blocks = t.build(seed(findings: const [
      FindingSection(
        title: 'T',
        standard: 's',
        finding: 'f',
        subFindings: [
          SubFinding(title: 'A', body: 'a'),
          SubFinding(title: 'B', body: 'b'),
        ],
      ),
    ]));
    final list = blocks.whereType<LabelledBulletListBlock>().first;
    // Two top-level items: Standard, Finding. Finding has 2 children.
    expect(list.items.length, 2);
    expect(list.items[1].children.length, 2);
    expect(list.items[1].children[0].leadBold, 'A');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/templates/non_reg_build_test.dart`

Expected: FAIL — `build()` currently returns `const []`; every assertion fails.

- [ ] **Step 3: Implement `build()`**

In `lib/features/documents/templates/non_reg_template.dart`, replace `build` with:

```dart
  @override
  List<Block> build(NonRegInputs i) {
    final fmt = DateFormat('MMMM d, yyyy');
    final blocks = <Block>[];

    // 1-2. Meta + spacer.
    blocks.add(LetterMetaBlock(
      date: i.dateIssued,
      to: LetterParty(name: i.employeeFullName),
      position: i.employeePosition.isEmpty ? null : i.employeePosition,
      from: LetterParty(name: i.hrManagerName ?? ''),
      subject: null,
      showDividers: false,
    ));
    blocks.add(const SpacerBlock(16));

    // 3-4. Subject heading + spacer.
    blocks.add(const HeadingBlock('SUBJECT: NOTICE OF NON-REGULARIZATION'));
    blocks.add(const SpacerBlock(12));

    // 5-6. Salutation + spacer.
    blocks.add(ParagraphBlock('Dear ${i.salutationName},'));
    blocks.add(const SpacerBlock(8));

    // 7. Intro paragraph 1 — bold dates inline.
    final ps = i.probationaryStart;
    final pe = i.probationaryEnd;
    blocks.add(EmphasisParagraphBlock(spans: [
      const EmphasisSpan(
          'This letter serves as formal notification regarding the status '
          'of your probationary employment, which commenced on '),
      EmphasisSpan(ps == null ? '—' : fmt.format(ps), bold: true),
      const EmphasisSpan(' and is scheduled to end on '),
      EmphasisSpan(pe == null ? '—' : fmt.format(pe), bold: true),
      const EmphasisSpan('.'),
    ]));

    // 8. Intro paragraph 2 — bold Section 4 + Annex B references inline.
    blocks.add(const EmphasisParagraphBlock(spans: [
      EmphasisSpan('As stipulated in '),
      EmphasisSpan('Section 4 (Probationary Evaluation)', bold: true),
      EmphasisSpan(
          ' of your Employment Contract, the Company has evaluated your '
          'performance against the '),
      EmphasisSpan('Standards for Regularization', bold: true),
      EmphasisSpan(
          ' (Annex B). After a comprehensive review, we regret to inform '
          'you that you have not met the reasonable standards required to '
          'qualify for regular employment.'),
    ]));

    // 9. Optional note on scope.
    if (i.noteOnScope.trim().isNotEmpty) {
      blocks.add(EmphasisParagraphBlock(spans: [
        const EmphasisSpan('Note on Scope of Evaluation: ', bold: true),
        EmphasisSpan(i.noteOnScope.trim()),
      ]));
    }

    // 10. Specifically lead-in.
    blocks.add(const ParagraphBlock(_specificallyLead));

    // 11. Findings loop.
    for (var idx = 0; idx < i.findings.length; idx++) {
      final f = i.findings[idx];
      blocks.add(const SpacerBlock(12));
      blocks.add(SectionHeadingBlock(number: idx + 1, title: f.title));
      blocks.add(LabelledBulletListBlock(items: [
        LabelledBulletItem(leadBold: 'Standard', body: f.standard),
        LabelledBulletItem(
          leadBold: 'Finding',
          body: f.finding,
          children: [
            for (final s in f.subFindings)
              LabelledBulletItem(leadBold: s.title, body: s.body),
          ],
        ),
      ]));
    }

    // 12-13. Decision heading + spacer.
    blocks.add(const SpacerBlock(16));
    blocks.add(const HeadingBlock('DECISION'));

    // 14. Decision paragraph with bold effectiveEndDate.
    final ee = i.effectiveEndDate;
    blocks.add(EmphasisParagraphBlock(spans: [
      const EmphasisSpan(
          'In view of the foregoing, your probationary employment will '
          'not be regularized and will cease effective at the close of '
          'business hours on '),
      EmphasisSpan(ee == null ? '—' : fmt.format(ee), bold: true),
      const EmphasisSpan('.'),
    ]));

    // 15-16. Final pay + closing.
    blocks.add(const ParagraphBlock(_finalPayText));
    blocks.add(const ParagraphBlock(_closingText));

    // 17-20. Sincerely + HR signature.
    blocks.add(const SpacerBlock(24));
    blocks.add(const ParagraphBlock('Sincerely,'));
    blocks.add(const SpacerBlock(40));
    blocks.add(SignatureBlock(
      name: i.hrManagerName,
      role: 'HR Manager\n${i.companyName}',
      date: i.dateIssued,
    ));

    // 21-30. Acknowledgment page.
    blocks.add(const PageBreakBlock());
    blocks.add(const HeadingBlock('ACKNOWLEDGMENT OF RECEIPT'));
    blocks.add(const SpacerBlock(8));
    blocks.add(const ParagraphBlock(_acknowledgmentText));
    blocks.add(const SpacerBlock(40));
    blocks.add(SignatureBlock(name: i.employeeFullName, role: '', date: null));
    blocks.add(const SpacerBlock(24));
    blocks.add(const ParagraphBlock('Witnessed by:'));
    blocks.add(const SpacerBlock(40));
    blocks.add(SignatureBlock(
      name: i.witnessName.isEmpty ? null : i.witnessName,
      role: '',
      date: null,
    ));

    return blocks;
  }
```

Add the necessary imports at the top of `non_reg_template.dart`:

```dart
import 'package:intl/intl.dart';

import '../blocks/emphasis_paragraph_block.dart';
import '../blocks/heading_block.dart';
import '../blocks/labelled_bullet_list_block.dart';
import '../blocks/letter_meta_block.dart';
import '../blocks/page_break_block.dart';
import '../blocks/paragraph_block.dart';
import '../blocks/section_heading_block.dart';
import '../blocks/signature_block.dart';
import '../blocks/spacer_block.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/templates/non_reg_build_test.dart`

Expected: PASS — all 8 build tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/non_reg_template.dart \
        test/features/documents/templates/non_reg_build_test.dart
git commit -m "feat(documents): NonRegTemplate.build — full block tree"
```

---

## Phase 8 — Form widget

### Task 17: Findings editor widget

**Files:**
- Create: `lib/features/documents/inputs/findings_editor.dart`

- [ ] **Step 1: Write the editor**

The findings editor follows the exact pattern of `charges_editor.dart` (NTE) — a `StatelessWidget` that takes the current `List<FindingSection>` and an `onChanged` callback. No tests at this layer (the v1 templates don't unit-test their editors; coverage is achieved via the integration smoke flow and end-to-end goldens).

Create `lib/features/documents/inputs/findings_editor.dart`:

```dart
import 'package:flutter/material.dart';

import '../templates/non_reg_inputs.dart';

class FindingsEditor extends StatelessWidget {
  final List<FindingSection> findings;
  final ValueChanged<List<FindingSection>> onChanged;
  const FindingsEditor({
    super.key,
    required this.findings,
    required this.onChanged,
  });

  void _addFinding() {
    onChanged([
      ...findings,
      const FindingSection(title: '', standard: '', finding: ''),
    ]);
  }

  void _removeFinding(int idx) {
    final next = [...findings]..removeAt(idx);
    onChanged(next);
  }

  void _setFinding(int idx, FindingSection f) {
    final next = [...findings];
    next[idx] = f;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < findings.length; i++)
          _FindingCard(
            index: i,
            finding: findings[i],
            onChanged: (f) => _setFinding(i, f),
            onRemove: () => _removeFinding(i),
          ),
        TextButton.icon(
          onPressed: _addFinding,
          icon: const Icon(Icons.add),
          label: const Text('Add finding section'),
        ),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  final int index;
  final FindingSection finding;
  final ValueChanged<FindingSection> onChanged;
  final VoidCallback onRemove;
  const _FindingCard({
    required this.index,
    required this.finding,
    required this.onChanged,
    required this.onRemove,
  });

  void _setTitle(String s) => onChanged(FindingSection(
        title: s,
        standard: finding.standard,
        finding: finding.finding,
        subFindings: finding.subFindings,
      ));

  void _setStandard(String s) => onChanged(FindingSection(
        title: finding.title,
        standard: s,
        finding: finding.finding,
        subFindings: finding.subFindings,
      ));

  void _setFinding(String s) => onChanged(FindingSection(
        title: finding.title,
        standard: finding.standard,
        finding: s,
        subFindings: finding.subFindings,
      ));

  void _addSub() => onChanged(FindingSection(
        title: finding.title,
        standard: finding.standard,
        finding: finding.finding,
        subFindings: [
          ...finding.subFindings,
          const SubFinding(title: '', body: ''),
        ],
      ));

  void _setSub(int i, SubFinding s) {
    final next = [...finding.subFindings];
    next[i] = s;
    onChanged(FindingSection(
      title: finding.title,
      standard: finding.standard,
      finding: finding.finding,
      subFindings: next,
    ));
  }

  void _removeSub(int i) {
    final next = [...finding.subFindings]..removeAt(i);
    onChanged(FindingSection(
      title: finding.title,
      standard: finding.standard,
      finding: finding.finding,
      subFindings: next,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: finding.title,
                  decoration: InputDecoration(
                    labelText: 'Section ${index + 1} title',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _setTitle,
                ),
              ),
              IconButton(
                tooltip: 'Remove section',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: finding.standard,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Standard',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _setStandard,
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: finding.finding,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Finding',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _setFinding,
          ),
          const SizedBox(height: 8),
          Text(
            'Sub-findings (optional)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          for (var si = 0; si < finding.subFindings.length; si++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: finding.subFindings[si].title,
                      decoration: const InputDecoration(
                        labelText: 'Sub-finding title',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (s) => _setSub(
                        si,
                        SubFinding(
                          title: s,
                          body: finding.subFindings[si].body,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: finding.subFindings[si].body,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Sub-finding body',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (s) => _setSub(
                        si,
                        SubFinding(
                          title: finding.subFindings[si].title,
                          body: s,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove sub-finding',
                    onPressed: () => _removeSub(si),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: _addSub,
            icon: const Icon(Icons.add),
            label: const Text('Add sub-finding'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/documents/inputs/findings_editor.dart`

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/inputs/findings_editor.dart
git commit -m "feat(documents): FindingsEditor widget — findings + sub-findings repeater"
```

### Task 18: NonReg form pane

**Files:**
- Create: `lib/features/documents/forms/non_reg_form.dart`

- [ ] **Step 1: Write the form**

Create `lib/features/documents/forms/non_reg_form.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../inputs/findings_editor.dart';
import '../templates/non_reg_inputs.dart';

class NonRegForm extends ConsumerStatefulWidget {
  final NonRegInputs initial;
  final bool employeeLocked;
  final ValueChanged<NonRegInputs> onChanged;
  const NonRegForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
  });

  @override
  ConsumerState<NonRegForm> createState() => _NonRegFormState();
}

class _NonRegFormState extends ConsumerState<NonRegForm> {
  late NonRegInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _set(NonRegInputs n) {
    setState(() => _i = n);
    widget.onChanged(n);
  }

  Widget _label(String s) =>
      Text(s, style: const TextStyle(fontWeight: FontWeight.w600));

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        primary: false,
        padding: const EdgeInsets.all(16),
        children: [
          _label('Employee'),
          const SizedBox(height: 4),
          EmployeePicker(
            selectedId: _i.employeeId.isEmpty ? null : _i.employeeId,
            locked: widget.employeeLocked,
            onChanged: (id) {
              if (id != null) _set(_i.copyWith(employeeId: id));
            },
          ),
          const SizedBox(height: 16),
          _label('Position'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.employeePosition,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (s) => _set(_i.copyWith(employeePosition: s)),
          ),
          const SizedBox(height: 16),
          _label('Company'),
          const SizedBox(height: 4),
          CompanyPicker(
            selectedId: _i.companyId.isEmpty ? null : _i.companyId,
            locked: false,
            onChanged: (id) {
              if (id != null) _set(_i.copyWith(companyId: id));
            },
          ),
          const SizedBox(height: 16),
          _label('HR Manager Name'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.hrManagerName ?? '',
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (s) =>
                _set(_i.copyWith(hrManagerName: s.isEmpty ? null : s)),
          ),
          const SizedBox(height: 16),
          _label('Date Issued'),
          const SizedBox(height: 4),
          DateField(
            value: _i.dateIssued,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(dateIssued: d));
            },
          ),
          const SizedBox(height: 16),
          _label('Probationary Start'),
          const SizedBox(height: 4),
          DateField(
            value: _i.probationaryStart,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(probationaryStart: d)),
          ),
          const SizedBox(height: 16),
          _label('Probationary End'),
          const SizedBox(height: 4),
          DateField(
            value: _i.probationaryEnd,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(probationaryEnd: d)),
          ),
          const SizedBox(height: 16),
          _label('Effective End Date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.effectiveEndDate,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(effectiveEndDate: d)),
          ),
          const SizedBox(height: 16),
          _label('Salutation Name'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.salutationName,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'e.g., Ms. Vidal',
            ),
            onChanged: (s) => _set(_i.copyWith(salutationName: s)),
          ),
          const SizedBox(height: 16),
          _label('Note on Scope of Evaluation (optional)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.noteOnScope,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText:
                  'If duties were reassigned during probation, briefly note here.',
            ),
            onChanged: (s) => _set(_i.copyWith(noteOnScope: s)),
          ),
          const SizedBox(height: 16),
          _label('Findings'),
          const SizedBox(height: 4),
          FindingsEditor(
            findings: _i.findings,
            onChanged: (next) => _set(_i.copyWith(findings: next)),
          ),
          const SizedBox(height: 16),
          _label('Witness Name (optional)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.witnessName,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'Pre-fills the witness signature line.',
            ),
            onChanged: (s) => _set(_i.copyWith(witnessName: s)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/documents/forms/non_reg_form.dart`

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/documents/forms/non_reg_form.dart
git commit -m "feat(documents): NonRegForm — form pane wiring autofilled inputs"
```

---

## Phase 9 — Wire into picker + generate screen

### Task 19: Register in template_registry

**Files:**
- Modify: `lib/features/documents/templates/template_registry.dart`

- [ ] **Step 1: Add the import and registry entry**

Replace the entire content of `lib/features/documents/templates/template_registry.dart`:

```dart
import 'coe_template.dart';
import 'document_template.dart';
import 'non_reg_template.dart';
import 'nte_template.dart';
import 'quitclaim_template.dart';

/// Registry of all document templates. The picker reads this list directly.
const List<DocumentTemplate> kTemplates = [
  QuitclaimTemplate(),
  CoeTemplate(),
  NteTemplate(),
  NonRegTemplate(),
];

DocumentTemplate? findTemplateById(String id) {
  for (final t in kTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/documents/templates/template_registry.dart`

Expected: `No issues found!`

- [ ] **Step 3: Run full document test suite**

Run: `flutter test test/features/documents/`

Expected: PASS — adding the registry entry does not affect any existing test.

- [ ] **Step 4: Commit**

```bash
git add lib/features/documents/templates/template_registry.dart
git commit -m "feat(documents): register NonRegTemplate in kTemplates"
```

### Task 20: Wire the generate screen

**Files:**
- Modify: `lib/features/documents/generate_screen.dart`

- [ ] **Step 1: Add the imports**

In `lib/features/documents/generate_screen.dart`, add these imports next to the existing template imports near the top of the file:

```dart
import 'forms/non_reg_form.dart';
import 'templates/non_reg_inputs.dart';
import 'templates/non_reg_template.dart';
```

- [ ] **Step 2: Add the state field**

In the `_GenerateScreenState` class, alongside `_quitclaim`, `_coe`, `_nte`, add:

```dart
  NonRegInputs? _nonReg;
```

- [ ] **Step 3: Add the autofill branch**

In `_runAutofill`, after the existing `if (tpl is NteTemplate) { ... }` block and before the `if (tpl is! QuitclaimTemplate) { ... }` block, insert:

```dart
    if (tpl is NonRegTemplate) {
      if (eId == null) {
        setState(() {
          _nonReg = tpl.emptyInputs();
          _autofillDone = true;
        });
        return;
      }
      final emp = await ref.read(documentEmployeeProvider(eId).future);
      final co = (emp == null || emp.hiringEntityId == null)
          ? null
          : await ref
              .read(hiringEntityByIdProvider(emp.hiringEntityId!).future);
      final ctx = AutofillContext(employee: emp, company: co, ref: ref);
      final filled = await tpl.autofill(ctx);
      setState(() {
        _nonReg = filled;
        _autofillDone = true;
      });
      return;
    }
```

- [ ] **Step 4: Add the form branch**

In `_formFor`, before the trailing `return const Center(child: Text('Form not implemented'));`, add:

```dart
    if (tpl is NonRegTemplate && _nonReg != null) {
      return NonRegForm(
        initial: _nonReg!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() => _nonReg = next),
      );
    }
```

- [ ] **Step 5: Add the preview branch**

In `_previewFor`, before the trailing `return const Center(child: Text('Preview not implemented'));`, add:

```dart
    if (tpl is NonRegTemplate && _nonReg != null) {
      final inputs = _nonReg!;
      final errors = tpl.validate(inputs);
      final filename = filenameForDocument(
        templateId: 'non_reg',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateIssued,
      );
      final who = inputs.employeeFullName.trim().isNotEmpty
          ? inputs.employeeFullName.trim()
          : (inputs.employeeId.isEmpty
              ? '(unknown employee)'
              : inputs.employeeId);
      return _previewWithBanner(
        errors,
        filename,
        (format) async {
          final theme = await PdfTheme.defaults();
          return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
        },
        onExported: (action) {
          ref.read(auditRepositoryProvider).logExport(
            description: 'Non-Reg PDF $action: $who',
            entityType: 'document_template_pdf',
            metadata: {
              'template_id': 'non_reg',
              'employee_id':
                  inputs.employeeId.isEmpty ? null : inputs.employeeId,
              'file_name': filename,
              'action': action,
            },
          );
        },
      );
    }
```

- [ ] **Step 6: Verify it compiles**

Run: `flutter analyze lib/features/documents/generate_screen.dart`

Expected: `No issues found!`

- [ ] **Step 7: Run full document test suite**

Run: `flutter test test/features/documents/`

Expected: PASS — all existing tests + the new validate / autofill / build tests remain green.

- [ ] **Step 8: Commit**

```bash
git add lib/features/documents/generate_screen.dart
git commit -m "feat(documents): wire NonRegTemplate into generate screen"
```

---

## Phase 10 — End-to-end pagination golden

### Task 21: Pagination smoke test

**Files:**
- Create: `test/features/documents/goldens/non_reg_pagination_test.dart`

- [ ] **Step 1: Write the pagination test**

Create `test/features/documents/goldens/non_reg_pagination_test.dart`:

```dart
// Renders a Non-Reg with enough findings to force pagination, then asserts
// the PDF bytes contain valid PDF magic and exceed a reasonable byte
// threshold for a 2+ page document. Full text-extraction verification of
// the "Page X of Y" footer is covered by the unit test in
// test/core/pdf/page_footer_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/pdf/pdf_builder.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  test('Non-Reg with 5 findings × 3 sub-findings produces multi-page PDF',
      () async {
    final theme = PdfTheme.testStub();
    final inputs = NonRegInputs(
      employeeId: 'e1',
      employeeFullName: 'Jamaica Phomela Litang Vidal',
      employeeLastName: 'Vidal',
      employeePosition: 'HR Assistant',
      companyId: 'c1',
      companyName: 'LUXIUM TRADING CO.',
      hrManagerName: 'Brixter Del Mundo',
      dateIssued: DateTime(2025, 12, 3),
      probationaryStart: DateTime(2025, 6, 9),
      probationaryEnd: DateTime(2025, 12, 6),
      effectiveEndDate: DateTime(2025, 12, 5),
      salutationName: 'Ms. Vidal',
      noteOnScope:
          'While your primary title is HR Assistant, your evaluation '
          'encompasses your assigned sales support duties during the LCT '
          'Bazaar.',
      findings: [
        for (var i = 0; i < 5; i++)
          FindingSection(
            title: 'Finding section ${i + 1} — long descriptive title for '
                'pagination testing',
            standard:
                'Annex B requires the employee to demonstrate the necessary '
                'role-specific skills and knowledge to perform their job '
                'effectively without excessive supervision. Lorem ipsum '
                'dolor sit amet, consectetur adipiscing elit.',
            finding:
                'You have failed to demonstrate the required level of '
                'engagement and focus expected of this role. Duis ac '
                'fermentum erat. Donec pulvinar lacinia magna.',
            subFindings: [
              for (var s = 0; s < 3; s++)
                SubFinding(
                  title: 'Sub-finding ${s + 1}',
                  body: 'Detailed body text for sub-finding ${s + 1}. '
                      'Lorem ipsum dolor sit amet, consectetur adipiscing '
                      'elit. Pellentesque habitant morbi tristique.',
                ),
            ],
          ),
      ],
    );
    const t = NonRegTemplate();
    final bytes =
        await buildDocumentPdf(blocks: t.build(inputs), theme: theme);

    // PDF magic header
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');

    // Reasonable byte threshold for a multi-page Non-Reg with 5 findings,
    // intro paragraphs, decision, and acknowledgment page.
    expect(bytes.length, greaterThan(3000));
  });
}
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/features/documents/goldens/non_reg_pagination_test.dart`

Expected: PASS — PDF bytes start with `%PDF` and exceed 3KB.

- [ ] **Step 3: Run the entire test suite**

Run: `flutter test`

Expected: PASS — every test in the project remains green. If any unrelated test fails, do NOT proceed — diagnose the failure (it likely indicates a regression caused by one of the block extensions).

- [ ] **Step 4: Commit**

```bash
git add test/features/documents/goldens/non_reg_pagination_test.dart
git commit -m "test(documents): NonReg multi-page pagination sanity golden"
```

---

## Phase 11 — Source-copy review pass

### Task 22: User confirmation of canonical legal copy

**Files:**
- Modify (possibly): `lib/features/documents/templates/non_reg_template.dart`

- [ ] **Step 1: Generate a sample PDF for the user**

Open the app locally:

```bash
flutter run -d linux
```

Sign in as an admin (HR-manage permission). Navigate to **Documents → Notice of Non-Regularization**. Pick a probationary employee. Fill the form with a minimum viable Non-Reg (1 finding + 1 sub-finding). Click **Download** to save the PDF.

Place the generated PDF side-by-side with the source `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/NOTICE OF NON-REGULARIZATION_VIDAL - Google Docs.pdf`.

- [ ] **Step 2: Diff legal copy**

Compare the rendered output paragraph-by-paragraph against the JAM source PDF. Surface ANY of the following to the user before merging:

- Wording differences in `_specificallyLead`, `_finalPayText`, `_closingText`, `_acknowledgmentText`.
- Wording differences in the inline `EmphasisParagraphBlock` span lists (intro 1, intro 2, decision).
- Punctuation, spacing, or bold-emphasis placement that differs from the source.

Ask the user explicitly: *"Here is the rendered Non-Reg side-by-side with the JAM source. Should I adjust any of the canonical wording before merging?"*

- [ ] **Step 3: Apply any requested corrections**

If the user requests changes, edit the relevant `const String` literals or `EmphasisSpan` lists in `non_reg_template.dart`. Run the full test suite again:

```bash
flutter test
```

Expected: PASS. If a build test in `non_reg_build_test.dart` breaks because of the wording change, update the test to match the new copy.

- [ ] **Step 4: Commit (if changes were applied)**

```bash
git add lib/features/documents/templates/non_reg_template.dart \
        test/features/documents/templates/non_reg_build_test.dart
git commit -m "fix(documents): NonReg canonical copy — apply user-confirmed wording"
```

If no changes were needed, skip this commit.

- [ ] **Step 5: Final smoke test**

Manually verify:

- [ ] Picker shows the Non-Reg card with the right icon, name, description.
- [ ] Tapping the card opens `/documents/generate/non_reg`.
- [ ] Opening from an employee profile (`?employeeId=...`) autofills the employee + company + HR Manager + probationary dates.
- [ ] Required-field banner appears when findings list is empty.
- [ ] Download + Print actions disabled when validation has errors; enabled once the form is filled.
- [ ] PDF renders 2+ pages with "Page X of Y" footer.
- [ ] Acknowledgment page renders on its own page with employee + witness hand-fill signature lines.

If anything is off, file a follow-up task; do NOT block merge on minor visual polish that can be addressed in a follow-up PR.

