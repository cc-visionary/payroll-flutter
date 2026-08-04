# Employee Signatories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flag employees as HR/Legal signatories so generated documents and payslips auto-fill the signatory's printed name, title, and transparent-PNG signature image.

**Architecture:** Four new columns on `employees` (flags + title + base64 PNG) with per-company partial unique indexes. A resolved `SignatoryInfo` rides into `AutofillContext`; templates prefer it over hiring-entity text defaults and snapshot the PNG (base64 string) into their inputs JSON so saved documents re-render as signed at generation time. PDF signature blocks gain an optional `Uint8List signatureImage` rendered sitting on the sign line. The payslip's hardcoded "Brixter Del Mundo" block is replaced by the resolved HR signatory.

**Tech Stack:** Flutter (Riverpod, `pdf` package), Supabase Postgres. Spec: `docs/superpowers/specs/2026-08-01-employee-signatories-design.md`.

## Global Constraints

- Gate on `flutter analyze` (run from the repo root). Do NOT run `dart format` — this repo mixes formatter styles; match the surrounding style of each file.
- Column names exactly: `is_hr_signatory`, `is_legal_signatory`, `signatory_title`, `signature_png` (base64 text).
- Inputs-JSON field name exactly `companySignaturePngB64` in every template inputs class.
- Only company-side signature lines get the image. Employee/counterparty/witness lines NEVER get it.
- Hiring-entity text defaults (`hrManagerName`, `legalSignatoryName`, `legalSignatoryRole`) remain as fallback — never removed.
- No new pub dependencies (`file_picker` is already a dependency).
- Signature uploads: PNG only, max 1 MB.
- The migration is written in Task 1 but only applied to prod in Task 10 (user-confirmed checkpoint). All app code must behave sanely against a DB without the columns until then (`fromRow` defaults cover this).
- Run tests with `flutter test <path>` from the repo root: `/home/ccvisionary/Documents/Work/[07] Projects/payroll-flutter`.

---

### Task 1: Migration + Employee model fields

**Files:**
- Create: `supabase/migrations/20260801000001_employee_signatories.sql`
- Modify: `lib/data/models/employee.dart`
- Test: `test/data/employee_signatory_fields_test.dart`

**Interfaces:**
- Produces: `Employee.isHrSignatory` (bool), `Employee.isLegalSignatory` (bool), `Employee.signatoryTitle` (String?), `Employee.signaturePngB64` (String?) — all later tasks read these.

- [ ] **Step 1: Write the failing test**

Create `test/data/employee_signatory_fields_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';

Map<String, dynamic> _baseRow() => {
      'id': 'E1',
      'company_id': 'C1',
      'employee_number': 'EMP-001',
      'first_name': 'Brixter',
      'last_name': 'Del Mundo',
      'employment_type': 'REGULAR',
      'employment_status': 'ACTIVE',
      'hire_date': '2024-01-01',
    };

void main() {
  test('fromRow parses signatory fields', () {
    final e = Employee.fromRow({
      ..._baseRow(),
      'is_hr_signatory': true,
      'is_legal_signatory': false,
      'signatory_title': 'HR Manager',
      'signature_png': 'QUJD',
    });
    expect(e.isHrSignatory, isTrue);
    expect(e.isLegalSignatory, isFalse);
    expect(e.signatoryTitle, 'HR Manager');
    expect(e.signaturePngB64, 'QUJD');
  });

  test('fromRow defaults signatory fields when columns are absent', () {
    final e = Employee.fromRow(_baseRow());
    expect(e.isHrSignatory, isFalse);
    expect(e.isLegalSignatory, isFalse);
    expect(e.signatoryTitle, isNull);
    expect(e.signaturePngB64, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/employee_signatory_fields_test.dart`
Expected: FAIL — compile error, `isHrSignatory` not defined on `Employee`.

- [ ] **Step 3: Add the model fields**

In `lib/data/models/employee.dart`:

Add after the `larkUserId` field declaration (line ~58):

```dart
  /// Authorized-signatory flags. At most one employee per company holds each
  /// capacity (partial unique indexes, migration 20260801000001). The title
  /// is what documents PRINT (e.g. 'HR Manager'), independent of jobTitle.
  final bool isHrSignatory;
  final bool isLegalSignatory;
  final String? signatoryTitle;
  /// Transparent-PNG signature, base64. Rendered onto generated documents.
  final String? signaturePngB64;
```

Add to the constructor (after `this.larkUserId,`):

```dart
    this.isHrSignatory = false,
    this.isLegalSignatory = false,
    this.signatoryTitle,
    this.signaturePngB64,
```

Add to `fromRow` (after the `larkUserId:` line):

```dart
        isHrSignatory: r['is_hr_signatory'] as bool? ?? false,
        isLegalSignatory: r['is_legal_signatory'] as bool? ?? false,
        signatoryTitle: r['signatory_title'] as String?,
        signaturePngB64: r['signature_png'] as String?,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/employee_signatory_fields_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Write the migration**

Create `supabase/migrations/20260801000001_employee_signatories.sql`:

```sql
-- Employee signatories: flag employees as the company's authorized
-- signatory per signing capacity (HR / Legal). Generated documents and
-- payslips auto-fill the flagged employee's name, printed title, and
-- transparent-PNG signature.
-- Spec: docs/superpowers/specs/2026-08-01-employee-signatories-design.md

ALTER TABLE employees
  ADD COLUMN is_hr_signatory boolean NOT NULL DEFAULT false,
  ADD COLUMN is_legal_signatory boolean NOT NULL DEFAULT false,
  ADD COLUMN signatory_title text,
  ADD COLUMN signature_png text;

COMMENT ON COLUMN employees.signatory_title IS
  'Title printed on generated documents (e.g. HR Manager) — independent of job_title.';
COMMENT ON COLUMN employees.signature_png IS
  'Base64 transparent PNG rendered onto generated documents'' sign lines.';

-- At most one signatory per capacity per company.
CREATE UNIQUE INDEX employees_one_hr_signatory
  ON employees (company_id) WHERE is_hr_signatory;
CREATE UNIQUE INDEX employees_one_legal_signatory
  ON employees (company_id) WHERE is_legal_signatory;
```

Do NOT apply it yet (Task 10 checkpoint).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260801000001_employee_signatories.sql lib/data/models/employee.dart test/data/employee_signatory_fields_test.dart
git commit -m "feat(employees): signatory flags, title, and signature PNG on employee model"
```

---

### Task 2: Repository signatory lookup + setters + providers

**Files:**
- Modify: `lib/data/repositories/employee_repository.dart`

**Interfaces:**
- Consumes: `Employee` fields from Task 1.
- Produces:
  - `Future<Employee?> EmployeeRepository.signatoryFor({required bool hr})`
  - `Future<void> EmployeeRepository.setSignatoryCapacity({required String employeeId, required bool hr, required bool enabled})`
  - `Future<void> EmployeeRepository.setSignatoryTitle(String employeeId, String? title)`
  - `Future<void> EmployeeRepository.setSignaturePng(String employeeId, String? pngB64)`
  - `final hrSignatoryProvider = FutureProvider<Employee?>` and `legalSignatoryProvider` (same type)

No unit test — these are thin Supabase calls and there is no local Supabase for this repo (ports 54321/54322 belong to other projects). Verification is `flutter analyze` + the Task 10 GUI smoke.

- [ ] **Step 1: Add the repository methods**

In `lib/data/repositories/employee_repository.dart`, add inside `EmployeeRepository` (after `updateReportsTo`):

```dart
  /// The single employee flagged for a signing capacity, or null when nobody
  /// is flagged. At most one row per company carries each flag (partial
  /// unique indexes, migration 20260801000001) and RLS scopes rows to the
  /// caller's company, so `maybeSingle` is safe.
  Future<Employee?> signatoryFor({required bool hr}) async {
    final row = await _client
        .from('employees')
        .select()
        .eq(hr ? 'is_hr_signatory' : 'is_legal_signatory', true)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (row == null) return null;
    return Employee.fromRow(row);
  }

  /// Enable/disable a signing capacity. Enabling clears the current holder
  /// first so the partial unique index never trips; the index is the
  /// backstop against concurrent claims.
  Future<void> setSignatoryCapacity({
    required String employeeId,
    required bool hr,
    required bool enabled,
  }) async {
    final col = hr ? 'is_hr_signatory' : 'is_legal_signatory';
    if (enabled) {
      await _client.from('employees').update({col: false}).eq(col, true);
    }
    await _client.from('employees').update({col: enabled}).eq('id', employeeId);
  }

  Future<void> setSignatoryTitle(String employeeId, String? title) async {
    final t = title?.trim();
    await _client
        .from('employees')
        .update({'signatory_title': (t == null || t.isEmpty) ? null : t})
        .eq('id', employeeId);
  }

  Future<void> setSignaturePng(String employeeId, String? pngB64) async {
    await _client
        .from('employees')
        .update({'signature_png': pngB64})
        .eq('id', employeeId);
  }
```

- [ ] **Step 2: Add the providers**

At the bottom of the same file (after `employeeByIdProvider`):

```dart
/// The employee flagged as HR / Legal signatory (company-scoped via RLS).
final hrSignatoryProvider = FutureProvider<Employee?>(
    (ref) => ref.watch(employeeRepositoryProvider).signatoryFor(hr: true));
final legalSignatoryProvider = FutureProvider<Employee?>(
    (ref) => ref.watch(employeeRepositoryProvider).signatoryFor(hr: false));
```

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/employee_repository.dart
git commit -m "feat(employees): signatory lookup/setters + hr/legal signatory providers"
```

---

### Task 3: PDF blocks — signature image support + decode helper

**Files:**
- Create: `lib/core/pdf/signature_png.dart`
- Create: `lib/features/documents/blocks/signature_image_block.dart`
- Modify: `lib/features/documents/blocks/signature_block.dart`
- Modify: `lib/features/documents/blocks/multi_signature_block.dart`
- Modify: `lib/features/documents/blocks/signature_line_block.dart`
- Test: `test/features/documents/signature_blocks_test.dart`

**Interfaces:**
- Produces:
  - `Uint8List? decodeSignaturePngB64(String? b64)` in `package:payroll_flutter/core/pdf/signature_png.dart`
  - `SignatureBlock({String? name, String? role, DateTime? date, Uint8List? signatureImage})`
  - `SignatoryParty({String? name, String? role, DateTime? date, Uint8List? signatureImage})`
  - `SignatoryLine({String? name, String? role, String? header, Uint8List? signatureImage})`
  - `SignatureImageBlock(Uint8List bytes, {double height = 40, bool centered = true})` extends `Block`
- All constructors stay `const`-compatible.

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/signature_blocks_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/core/pdf/signature_png.dart';
import 'package:payroll_flutter/features/documents/blocks/block.dart';
import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_image_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_line_block.dart';

/// 1x1 fully-transparent PNG.
const kTransparentPng1x1B64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

Future<List<int>> _render(Block block) async {
  final theme = PdfTheme.testStub();
  final doc = pw.Document();
  doc.addPage(pw.Page(build: (_) => block.toPdf(theme)));
  return doc.save();
}

void main() {
  final png = base64Decode(kTransparentPng1x1B64);

  test('decodeSignaturePngB64 decodes, and nulls on garbage/empty', () {
    expect(decodeSignaturePngB64(kTransparentPng1x1B64), isNotNull);
    expect(decodeSignaturePngB64(null), isNull);
    expect(decodeSignaturePngB64(''), isNull);
    expect(decodeSignaturePngB64('!!!not-base64!!!'), isNull);
  });

  test('SignatureBlock renders with and without signature image', () async {
    expect(
        (await _render(SignatureBlock(
                name: 'Brixter Del Mundo',
                role: 'HR Manager',
                signatureImage: png)))
            .length,
        greaterThan(500));
    expect(
        (await _render(const SignatureBlock(name: 'Brixter Del Mundo')))
            .length,
        greaterThan(500));
  });

  test('MultiSignatureBlock renders a signed party', () async {
    final bytes = await _render(MultiSignatureBlock([
      SignatoryParty(name: 'Brixter', role: 'HR Manager', signatureImage: png),
      const SignatoryParty(name: 'Juan', role: 'Employee (Acknowledged)'),
    ]));
    expect(bytes.length, greaterThan(500));
  });

  test('SignatureLineBlock renders a signed line', () async {
    final bytes = await _render(SignatureLineBlock(
      [
        SignatoryLine(
            header: 'For the Company',
            name: 'Clinton Xu',
            role: 'CEO',
            signatureImage: png),
        const SignatoryLine(header: 'Recipient', name: 'Juan'),
      ],
      row: true,
      showDate: true,
    ));
    expect(bytes.length, greaterThan(500));
  });

  test('SignatureImageBlock renders', () async {
    expect((await _render(SignatureImageBlock(png))).length, greaterThan(500));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/signature_blocks_test.dart`
Expected: FAIL — `signature_png.dart` / `signature_image_block.dart` don't exist, `signatureImage` param undefined.

- [ ] **Step 3: Create the decode helper**

Create `lib/core/pdf/signature_png.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

/// Decode a base64 signature PNG. Null/empty/garbage → null so a corrupt
/// upload degrades to a blank sign line instead of crashing the render.
Uint8List? decodeSignaturePngB64(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 4: Create SignatureImageBlock**

Create `lib/features/documents/blocks/signature_image_block.dart`:

```dart
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';
import 'block.dart';

/// A standalone signature image (transparent PNG) for templates that print
/// the signatory as a plain name paragraph instead of a line block (COE).
class SignatureImageBlock extends Block {
  final Uint8List bytes;
  final double height;
  final bool centered;
  const SignatureImageBlock(this.bytes, {this.height = 40, this.centered = true});

  @override
  pw.Widget toPdf(PdfTheme theme) {
    final img = pw.Image(pw.MemoryImage(bytes), height: height, fit: pw.BoxFit.contain);
    return centered ? pw.Center(child: img) : img;
  }
}
```

- [ ] **Step 5: Add signatureImage to SignatureBlock**

In `lib/features/documents/blocks/signature_block.dart`:

Add `import 'dart:typed_data';` at the top. Change the class head to:

```dart
class SignatureBlock extends Block {
  final String? name;
  final String? role;
  final DateTime? date;
  /// Transparent-PNG signature rendered above the printed name, sitting on
  /// the sign line. Company-side signatories only.
  final Uint8List? signatureImage;
  const SignatureBlock({this.name, this.role, this.date, this.signatureImage});
```

In `toPdf`, replace the underlined container's `child: pw.Text(...)` with a column holding the image (bottom-aligned so it sits on the line) above the name:

```dart
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (signatureImage != null)
                pw.Container(
                  height: 40,
                  alignment: pw.Alignment.bottomLeft,
                  child: pw.Image(pw.MemoryImage(signatureImage!),
                      height: 38, fit: pw.BoxFit.contain),
                ),
              pw.Text(
                name ?? '',
                style: pw.TextStyle(
                  fontSize: theme.bodySize,
                  fontWeight: pw.FontWeight.bold,
                  color: theme.textColor,
                ),
              ),
            ],
          ),
```

(Keep the surrounding `pw.Container` width/border decoration exactly as-is.)

- [ ] **Step 6: Add signatureImage to SignatoryParty / MultiSignatureBlock**

In `lib/features/documents/blocks/multi_signature_block.dart`:

Add `import 'dart:typed_data';`. Change `SignatoryParty` to:

```dart
class SignatoryParty {
  final String? name;
  final String? role;
  final DateTime? date;
  final Uint8List? signatureImage;
  const SignatoryParty({this.name, this.role, this.date, this.signatureImage});
}
```

In the `one(SignatoryParty s)` builder, apply the same underlined-container change as Step 5 (column with bottom-aligned 40pt image above the name text, using `s.signatureImage` and `s.name`).

- [ ] **Step 7: Add signatureImage to SignatoryLine / SignatureLineBlock**

In `lib/features/documents/blocks/signature_line_block.dart`:

Add `import 'dart:typed_data';`. Change `SignatoryLine` to:

```dart
class SignatoryLine {
  final String? name;
  final String? role;

  /// Optional caption rendered BOLD above the signature line, e.g.
  /// "For the Company" / "Recipient".
  final String? header;

  /// Transparent-PNG signature rendered in the wet-signature space, sitting
  /// on the line. Company-side signatories only.
  final Uint8List? signatureImage;
  const SignatoryLine({this.name, this.role, this.header, this.signatureImage});
}
```

In `_one`, replace the underlined container's `child: pw.SizedBox(height: 24)` with:

```dart
          child: s.signatureImage == null
              ? pw.SizedBox(height: 24)
              : pw.Container(
                  height: 40,
                  alignment: pw.Alignment.bottomCenter,
                  child: pw.Image(pw.MemoryImage(s.signatureImage!),
                      height: 38, fit: pw.BoxFit.contain),
                ),
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/features/documents/signature_blocks_test.dart`
Expected: PASS (5 tests). Then `flutter analyze` — no new issues.

- [ ] **Step 9: Commit**

```bash
git add lib/core/pdf/signature_png.dart lib/features/documents/blocks/ test/features/documents/signature_blocks_test.dart
git commit -m "feat(documents): signature-image support in PDF signature blocks"
```

---

### Task 4: Payslip — resolved HR signatory replaces hardcoded name

**Files:**
- Modify: `lib/features/payroll/payslips/payslip_pdf.dart` (input class + `_signatureBlock`, line ~476)
- Modify: `lib/features/payroll/payslips/payslip_pdf_context.dart`
- Modify: `lib/features/payroll/payslips/payslip_preview_screen.dart` (input construction, line ~123)
- Test: `test/engine/payslip_pdf_test.dart` (extend)

**Interfaces:**
- Consumes: `EmployeeRepository.signatoryFor(hr: true)` (Task 2), `decodeSignaturePngB64` (Task 3), `Employee.signatoryTitle`/`signaturePngB64` (Task 1).
- Produces: `PayslipPdfInput.hrSignatoryName` (String?), `.hrSignatoryTitle` (String?), `.hrSignaturePng` (Uint8List?) — same three on `PayslipPdfContext`.

- [ ] **Step 1: Write the failing test**

In `test/engine/payslip_pdf_test.dart`, add inside `main()` a second test that clones the existing fixture construction (copy the `emp`/`ps` fixtures from the existing test verbatim) and builds with signatory fields:

```dart
  test('payslip PDF: renders resolved HR signatory with signature image',
      () async {
    // ... same `emp` and `ps` fixtures as the test above ...
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
    final bytes = await buildPayslipPdf(PayslipPdfInput(
      payslip: ps,
      employee: emp,
      companyName: 'Luxium Trading Inc.',
      periodStart: DateTime.utc(2026, 1, 1),
      periodEnd: DateTime.utc(2026, 1, 15),
      payDate: DateTime.utc(2026, 1, 20),
      hrSignatoryName: 'Brixter Del Mundo',
      hrSignatoryTitle: 'HR Manager',
      hrSignaturePng: png,
    ));
    expect(bytes.length, greaterThan(1000));
  });

  test('payslip PDF: builds with no signatory at all (blank sign line)',
      () async {
    // ... same fixtures ...
    final bytes = await buildPayslipPdf(PayslipPdfInput(
      payslip: ps,
      employee: emp,
      companyName: 'Luxium Trading Inc.',
      periodStart: DateTime.utc(2026, 1, 1),
      periodEnd: DateTime.utc(2026, 1, 15),
      payDate: DateTime.utc(2026, 1, 20),
    ));
    expect(bytes.length, greaterThan(1000));
  });
```

Add `import 'dart:convert';` to the test file.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/engine/payslip_pdf_test.dart`
Expected: FAIL — `hrSignatoryName` not defined on `PayslipPdfInput`.

- [ ] **Step 3: Extend PayslipPdfInput and rewrite _signatureBlock**

In `lib/features/payroll/payslips/payslip_pdf.dart`, add to `PayslipPdfInput` (fields + constructor params, all optional):

```dart
  /// Resolved HR signatory (from employees.is_hr_signatory, falling back to
  /// the hiring entity's hr_manager_name). Null → blank sign line.
  final String? hrSignatoryName;
  final String? hrSignatoryTitle;
  final Uint8List? hrSignaturePng;
```

Replace `_signatureBlock` (currently hardcodes 'Brixter Del Mundo' / 'HR Manager'):

```dart
pw.Widget _signatureBlock(PayslipPdfInput i) {
  // Employee signature removed — receipt is captured via Lark approval
  // (see send-payslip-approvals edge function). The HR authorized
  // representative is resolved from the employees signatory flags.
  final name = (i.hrSignatoryName ?? '').trim();
  final title = (i.hrSignatoryTitle ?? '').trim();
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    children: [
      pw.SizedBox(
        width: 240,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (i.hrSignaturePng != null)
              pw.Container(
                height: 40,
                alignment: pw.Alignment.bottomCenter,
                child: pw.Image(pw.MemoryImage(i.hrSignaturePng!),
                    height: 38, fit: pw.BoxFit.contain),
              ),
            pw.Container(
              height: 1,
              color: PdfColors.grey500,
              margin: const pw.EdgeInsets.symmetric(horizontal: 12),
            ),
            pw.SizedBox(height: 2),
            if (name.isNotEmpty)
              pw.Text(
                name,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            if (title.isNotEmpty)
              pw.Text(
                title,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/engine/payslip_pdf_test.dart`
Expected: PASS (all tests, including the pre-existing one).

- [ ] **Step 5: Resolve the signatory in the context loader**

In `lib/features/payroll/payslips/payslip_pdf_context.dart`:

1. Add `import '../../../core/pdf/signature_png.dart';`
2. Add the three fields to `PayslipPdfContext` (+ constructor params):

```dart
  final String? hrSignatoryName;
  final String? hrSignatoryTitle;
  final Uint8List? hrSignaturePng;
```

3. In `loadPayslipPdfContext`, after `final emp = await empRepo.byId(...)` block, resolve the signatory (single fetch, reused for every payslip is NOT needed — this loader is per-payslip; keep it simple):

```dart
  final hrSig = await empRepo.signatoryFor(hr: true);
```

4. In the `return PayslipPdfContext(...)` add:

```dart
    hrSignatoryName: hrSig?.fullName ?? entity?.hrManagerName,
    hrSignatoryTitle: hrSig != null
        ? ((hrSig.signatoryTitle?.isNotEmpty ?? false)
            ? hrSig.signatoryTitle
            : 'HR Manager')
        : ((entity?.hrManagerName?.isNotEmpty ?? false) ? 'HR Manager' : null),
    hrSignaturePng: decodeSignaturePngB64(hrSig?.signaturePngB64),
```

5. In `buildPayslipPdfsForIds`, pass the trio through to `PayslipPdfInput`:

```dart
      hrSignatoryName: ctx.hrSignatoryName,
      hrSignatoryTitle: ctx.hrSignatoryTitle,
      hrSignaturePng: ctx.hrSignaturePng,
```

- [ ] **Step 6: Pass through in the preview screen**

In `lib/features/payroll/payslips/payslip_preview_screen.dart` (line ~123), add the same three `hrSignatory*` lines to its `PayslipPdfInput(...)` construction.

- [ ] **Step 7: Verify**

Run: `flutter test test/engine/payslip_pdf_test.dart && flutter analyze`
Expected: tests PASS, no new analyze issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/payroll/payslips/ test/engine/payslip_pdf_test.dart
git commit -m "feat(payroll): payslip signs with resolved HR signatory instead of hardcoded name"
```

---

### Task 5: SignatoryInfo in AutofillContext + loader + wiring

**Files:**
- Modify: `lib/features/documents/templates/document_template.dart`
- Create: `lib/features/documents/signatory_autofill.dart`
- Modify: `lib/features/documents/generate_screen.dart` (`_contextFor`, line ~482)
- Modify: `lib/features/documents/bulk/bulk_generate.dart` (line ~69)
- Modify: `lib/features/hiring/offer_letter_action.dart` (line ~28)

**Interfaces:**
- Consumes: `hrSignatoryProvider` / `legalSignatoryProvider` (Task 2).
- Produces:
  - `class SignatoryInfo { final String name; final String? title; final String? signaturePngB64; }` (in `document_template.dart`)
  - `AutofillContext.hrSignatory` / `.legalSignatory` (both `SignatoryInfo?`, default null)
  - `Future<({SignatoryInfo? hr, SignatoryInfo? legal})> loadAutofillSignatories(WidgetRef ref)` (in `signatory_autofill.dart`)
- Note: `documents_tab.dart`'s `AutofillContext` site only calls `gates()` — leave it unwired (nulls are fine).

No standalone test — pure data plumbing exercised by Task 6/7 tests and `flutter analyze`.

- [ ] **Step 1: Add SignatoryInfo + context fields**

In `lib/features/documents/templates/document_template.dart`, above `AutofillContext`:

```dart
/// Resolved signatory defaults for autofill: the employee flagged for a
/// signing capacity, reduced to what templates print. `title` null →
/// templates keep their per-document default role text.
class SignatoryInfo {
  final String name;
  final String? title;
  final String? signaturePngB64;
  const SignatoryInfo({required this.name, this.title, this.signaturePngB64});
}
```

In `AutofillContext`, add fields + constructor params (both optional):

```dart
  /// Flagged authorized signatories (employees.is_hr_signatory /
  /// is_legal_signatory). Null when unassigned or not loaded — templates
  /// fall back to the hiring entity's text defaults.
  final SignatoryInfo? hrSignatory;
  final SignatoryInfo? legalSignatory;
```

- [ ] **Step 2: Create the loader**

Create `lib/features/documents/signatory_autofill.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/employee.dart';
import '../../data/repositories/employee_repository.dart';
import 'templates/document_template.dart';

SignatoryInfo? _info(Employee? e) => e == null
    ? null
    : SignatoryInfo(
        name: e.fullName,
        title: (e.signatoryTitle?.isNotEmpty ?? false) ? e.signatoryTitle : null,
        signaturePngB64: e.signaturePngB64,
      );

/// Resolve both flagged signatories for document autofill. Errors degrade
/// to nulls so generation still works when the lookup fails (fields fall
/// back to hiring-entity defaults).
Future<({SignatoryInfo? hr, SignatoryInfo? legal})> loadAutofillSignatories(
    WidgetRef ref) async {
  try {
    final hr = await ref.read(hrSignatoryProvider.future);
    final legal = await ref.read(legalSignatoryProvider.future);
    return (hr: _info(hr), legal: _info(legal));
  } catch (_) {
    return (hr: null, legal: null);
  }
}
```

- [ ] **Step 3: Wire the three autofill call sites**

1. `generate_screen.dart` — add `import 'signatory_autofill.dart';` and in `_contextFor`:

```dart
    final sigs = await loadAutofillSignatories(ref);
    return AutofillContext(
      employee: emp,
      company: co,
      ref: ref,
      compensationChangeId: widget.compensationChangeId,
      hrSignatory: sigs.hr,
      legalSignatory: sigs.legal,
    );
```

2. `bulk/bulk_generate.dart` — add `import '../signatory_autofill.dart';`; resolve ONCE before the `for` loop (`final sigs = await loadAutofillSignatories(ref);`) and change the ctx line to:

```dart
    final ctx = AutofillContext(
        employee: emp,
        company: co,
        ref: ref,
        hrSignatory: sigs.hr,
        legalSignatory: sigs.legal);
```

3. `hiring/offer_letter_action.dart` — add `import '../documents/signatory_autofill.dart';`, resolve `final sigs = await loadAutofillSignatories(ref);` before the ctx, and pass `hrSignatory: sigs.hr, legalSignatory: sigs.legal` into its `AutofillContext(...)`.

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/document_template.dart lib/features/documents/signatory_autofill.dart lib/features/documents/generate_screen.dart lib/features/documents/bulk/bulk_generate.dart lib/features/hiring/offer_letter_action.dart
git commit -m "feat(documents): resolved signatories injected into AutofillContext"
```

---

### Task 6: `companySignaturePngB64` on 10 template inputs classes

**Files:**
- Modify (identical mechanical pattern in each):
  - `lib/features/documents/templates/coe_inputs.dart`
  - `lib/features/documents/templates/nte_inputs.dart`
  - `lib/features/documents/templates/non_reg_inputs.dart`
  - `lib/features/documents/templates/nod_inputs.dart`
  - `lib/features/documents/templates/final_pay_inputs.dart`
  - `lib/features/documents/templates/salary_adjustment_inputs.dart`
  - `lib/features/documents/templates/regularization_inputs.dart`
  - `lib/features/documents/templates/resignation_acceptance_inputs.dart`
  - `lib/features/documents/templates/nda_inputs.dart`
  - `lib/features/documents/templates/employment_contract_inputs.dart`
- Test: `test/features/documents/company_signature_roundtrip_test.dart`

Quitclaim and Liability Waiver are EXCLUDED — their sign lines are employee-side only.

**Interfaces:**
- Produces: `String? companySignaturePngB64` on each listed inputs class, wired through constructor, `copyWith`, `toJson`, `fromJson` (default null → old saved docs render unchanged).

- [ ] **Step 1: Write the failing test**

Create `test/features/documents/company_signature_roundtrip_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/coe_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/coe_template.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_template.dart';
import 'package:payroll_flutter/features/documents/templates/nda_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nda_template.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_template.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nte_template.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_template.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_template.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_template.dart';

/// Round-trip: copyWith sets the field, toJson persists it, fromJson reads
/// it back; a JSON WITHOUT the key (legacy saved docs) must yield null.
void main() {
  void roundTrip<T>(
    String label,
    dynamic inputsWithSig,
    T Function(Map<String, dynamic>) fromJson,
    String? Function(T) getSig,
  ) {
    test('$label round-trips companySignaturePngB64', () {
      final json = inputsWithSig.toJson() as Map<String, dynamic>;
      expect(getSig(fromJson(json)), 'QUJD');
      json.remove('companySignaturePngB64');
      expect(getSig(fromJson(json)), isNull);
    });
  }

  roundTrip<CoeInputs>(
      'CoeInputs',
      const CoeTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      CoeInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<NteInputs>(
      'NteInputs',
      const NteTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      NteInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<NonRegInputs>(
      'NonRegInputs',
      const NonRegTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      NonRegInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<NodInputs>(
      'NodInputs',
      const NodTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      NodInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<FinalPayInputs>(
      'FinalPayInputs',
      const FinalPayTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      FinalPayInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<SalaryAdjustmentInputs>(
      'SalaryAdjustmentInputs',
      const SalaryAdjustmentTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      SalaryAdjustmentInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<RegularizationInputs>(
      'RegularizationInputs',
      const RegularizationTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      RegularizationInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<ResignationAcceptanceInputs>(
      'ResignationAcceptanceInputs',
      const ResignationAcceptanceTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      ResignationAcceptanceInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<NdaInputs>(
      'NdaInputs',
      const NdaTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      NdaInputs.fromJson,
      (i) => i.companySignaturePngB64);
  roundTrip<EmploymentContractInputs>(
      'EmploymentContractInputs',
      const EmploymentContractTemplate().emptyInputs().copyWith(companySignaturePngB64: 'QUJD'),
      EmploymentContractInputs.fromJson,
      (i) => i.companySignaturePngB64);
}
```

Adjust ONLY if a template's class/const-ness differs (check `template_registry.dart` for the real constructor names). If an `emptyInputs()` requires args, construct via the registry instance instead.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/documents/company_signature_roundtrip_test.dart`
Expected: FAIL — `companySignaturePngB64` undefined on every inputs class.

- [ ] **Step 3: Apply the mechanical pattern to all 10 inputs classes**

For EACH file, following that file's existing field style exactly:

1. Field (place with the other signatory-ish fields):

```dart
  /// Base64 transparent-PNG signature of the company-side signatory,
  /// snapshotted at generation so saved documents re-render as signed at
  /// the time. Null (incl. legacy saved docs) → blank sign line.
  final String? companySignaturePngB64;
```

2. Constructor: add optional param `this.companySignaturePngB64,`.
3. `copyWith`: add param `String? companySignaturePngB64,` and wire `companySignaturePngB64: companySignaturePngB64 ?? this.companySignaturePngB64,`.
4. `fromJson`: add `companySignaturePngB64: json['companySignaturePngB64'] as String?,`.
5. `toJson`: add `'companySignaturePngB64': companySignaturePngB64,`.
6. If the class has a `toDebugMap`, add `'companySignaturePngB64': companySignaturePngB64 == null ? null : '<png b64, ${companySignaturePngB64!.length} chars>',` — never dump the full blob into logs.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/documents/company_signature_roundtrip_test.dart && flutter analyze`
Expected: PASS (10 tests), no new analyze issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/ test/features/documents/company_signature_roundtrip_test.dart
git commit -m "feat(documents): companySignaturePngB64 snapshot field on 10 template inputs"
```

---

### Task 7: HR-capacity templates — autofill + signed build (8 templates)

**Files:**
- Modify: `lib/features/documents/templates/coe_template.dart`
- Modify: `lib/features/documents/templates/nte_template.dart`
- Modify: `lib/features/documents/templates/non_reg_template.dart`
- Modify: `lib/features/documents/templates/nod_template.dart`
- Modify: `lib/features/documents/templates/final_pay_template.dart`
- Modify: `lib/features/documents/templates/salary_adjustment_template.dart`
- Modify: `lib/features/documents/templates/regularization_template.dart`
- Modify: `lib/features/documents/templates/resignation_acceptance_template.dart`

**Interfaces:**
- Consumes: `ctx.hrSignatory` (Task 5), `companySignaturePngB64` (Task 6), `decodeSignaturePngB64` + block params (Task 3).
- Produces: no new interfaces — behavior only.

**Autofill pattern (every template):** in each `autofill()`, find the assignment of the HR name field (grep `hrManagerName:` — e.g. `coe_template.dart:66` reads `hrManagerName: co?.hrManagerName`) and change the resolution order to signatory-first, entity-fallback:

```dart
      hrManagerName: ctx.hrSignatory?.name ?? co?.hrManagerName,
```

(match nullability — templates whose field is non-nullable use `?? ''` as they do today), and add to the same inputs construction:

```dart
      companySignaturePngB64: ctx.hrSignatory?.signaturePngB64,
```

`salary_adjustment_template.dart` additionally (autofill line ~160) replaces the hardcoded role:

```dart
      signatoryRole: ctx.hrSignatory?.title ?? 'HR Manager',
```

**Build pattern:** each template adds `import '../../../core/pdf/signature_png.dart';` and passes the decoded image to the COMPANY party only.

- [ ] **Step 1: NTE + Non-Reg (SignatureBlock-based)**

`nte_template.dart` (~line 155):

```dart
    blocks.add(SignatureBlock(
      name: i.hrManagerName,
      role: 'HR Manager — ${i.companyName}',
      date: i.dateIssued,
      signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),
    ));
```

`non_reg_template.dart` (~line 254) — FIRST SignatureBlock only (the employee-acknowledgment SignatureBlock at ~line 266 and the witness one at ~line 270 stay untouched):

```dart
    blocks.add(SignatureBlock(
      name: i.hrManagerName,
      role: 'HR Manager\n${i.companyName}',
      date: i.dateIssued,
      signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),
    ));
```

Apply the autofill pattern to both files.

- [ ] **Step 2: NOD, Final Pay, Salary Adjustment, Regularization, Resignation Acceptance (MultiSignatureBlock-based)**

In each build, add `signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),` to the FIRST `SignatoryParty` (the HR one) — e.g. `nod_template.dart` ~line 139:

```dart
      MultiSignatureBlock([
        SignatoryParty(
          name: i.hrManagerName,
          role: 'HR Manager',
          signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),
        ),
        SignatoryParty(
          name: i.employeeFullName,
          role: 'Employee (Acknowledged)',
        ),
      ]),
```

Same change at `final_pay_template.dart` ~192 (keep its `date: i.computedAsOf`), `salary_adjustment_template.dart` ~256 (role stays `i.signatoryRole`), `regularization_template.dart` ~180, `resignation_acceptance_template.dart` ~158. The `SignatoryParty(name: i.employeeFullName, ...)` entries NEVER get an image. Apply the autofill pattern to all five files.

- [ ] **Step 3: COE (centered name paragraph)**

`coe_template.dart`: autofill pattern at line ~66. In `build()`, the signatory renders as `SpacerBlock(48)` then the uppercase-name `EmphasisParagraphBlock` (~line 132). Replace the `const SpacerBlock(48),` with a signed variant (add imports for `signature_image_block.dart` and `signature_png.dart`; the block list can no longer be fully const — use a local):

```dart
      ...(() {
        final sig = decodeSignaturePngB64(i.companySignaturePngB64);
        return sig == null
            ? const [SpacerBlock(48)]
            : [const SpacerBlock(12), SignatureImageBlock(sig), const SpacerBlock(2)];
      })(),
```

If the surrounding list construction makes the spread awkward, restructure to `final blocks = <Block>[ ... ]` with a plain `if/else` insertion — match the file's style.

- [ ] **Step 4: Verify**

Run: `flutter test test/features/documents/ test/engine/payslip_pdf_test.dart && flutter analyze`
Expected: all PASS, no new analyze issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/
git commit -m "feat(documents): HR-capacity templates autofill + render the flagged signatory"
```

---

### Task 8: Legal-capacity templates (NDA, Employment Contract) + generate-screen branches

**Files:**
- Modify: `lib/features/documents/templates/nda_template.dart`
- Modify: `lib/features/documents/templates/employment_contract_template.dart`
- Modify: `lib/features/documents/generate_screen.dart` (`_onPickerCompanyChanged`, lines ~638-701)

**Interfaces:**
- Consumes: `ctx.legalSignatory` (Task 5), `legalSignatoryProvider` (Task 2), `companySignaturePngB64` (Task 6), block params (Task 3).

- [ ] **Step 1: NDA autofill + build**

`nda_template.dart` autofill (~line 290) — signatory-first:

```dart
      authorizedSignatoryName: ctx.legalSignatory?.name ??
          ((co?.legalSignatoryName?.isNotEmpty == true)
              ? co!.legalSignatoryName!
              : (co?.hrManagerName ?? '')),
      authorizedSignatoryRole: ctx.legalSignatory?.title ??
          ((co?.legalSignatoryRole?.isNotEmpty == true)
              ? co!.legalSignatoryRole!
              : 'Authorized Signatory'),
      companySignaturePngB64: ctx.legalSignatory?.signaturePngB64,
```

Build (~line 506) — image on the 'For the Company' line only (add the `signature_png.dart` import):

```dart
    blocks.add(SignatureLineBlock(
      [
        SignatoryLine(
          header: 'For the Company',
          name: i.authorizedSignatoryName,
          role: i.authorizedSignatoryRole,
          signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),
        ),
        SignatoryLine(
          header: 'Recipient',
          name: i.employeeFullName,
          role: 'Signature over Printed Name',
        ),
      ],
      row: true,
      showDate: true,
    ));
```

- [ ] **Step 2: Employment contract autofill (both paths) + build**

`employment_contract_template.dart` has TWO autofill paths (applicant ~line 548, employee ~line 658). In BOTH, prefer the resolved legal signatory:

```dart
    final repName = ctx.legalSignatory?.name ?? /* existing expression */;
    final repRole = ctx.legalSignatory?.title ?? /* existing expression */;
```

(keep each path's existing expression verbatim as the fallback) and add `companySignaturePngB64: ctx.legalSignatory?.signaturePngB64,` to both inputs constructions (the fields feed `employerSignatoryName`/`employerSignatoryRole` — trace each path to its inputs construction).

Build (~line 907) — employer line only; employee + witness lines untouched:

```dart
    blocks.add(SignatureLineBlock([
      SignatoryLine(
        name: i.employerSignatoryName,
        role: i.employerSignatoryRole,
        signatureImage: decodeSignaturePngB64(i.companySignaturePngB64),
      ),
      SignatoryLine(name: i.employeeFullName, role: i.position),
    ]));
```

- [ ] **Step 3: Generate-screen company-change branches**

In `generate_screen.dart` `_onPickerCompanyChanged`, the contract branch (~line 650) and NDA branch (~line 695) OVERWRITE signatory names from entity fields on every entity switch — they'd clobber the resolved signatory. At the top of the method (after `final co = await ...`), add:

```dart
    final legalSig = await ref.read(legalSignatoryProvider.future).catchError((_) => null);
```

(import `../../data/repositories/employee_repository.dart` if not already imported). Then:

Contract branch — replace the four signatory lines with:

```dart
          representativeName: legalSig?.fullName ?? co?.hrManagerName ?? '',
          representativeRole: legalSig?.signatoryTitle ??
              ((co?.legalSignatoryRole?.isNotEmpty ?? false)
                  ? co!.legalSignatoryRole!
                  : 'People Manager'),
          employerSignatoryName: legalSig?.fullName ?? co?.hrManagerName ?? '',
          employerSignatoryRole: legalSig?.signatoryTitle ??
              ((co?.legalSignatoryRole?.isNotEmpty ?? false)
                  ? co!.legalSignatoryRole!
                  : 'People Manager'),
```

NDA branch — replace the two signatory lines with:

```dart
          authorizedSignatoryName: legalSig?.fullName ??
              ((co?.legalSignatoryName?.isNotEmpty ?? false)
                  ? co!.legalSignatoryName!
                  : (co?.hrManagerName ?? '')),
          authorizedSignatoryRole: legalSig?.signatoryTitle ??
              ((co?.legalSignatoryRole?.isNotEmpty ?? false)
                  ? co!.legalSignatoryRole!
                  : 'Authorized Signatory'),
```

The HR-name branches (COE/NTE/etc.) already only fill when empty — leave them.

- [ ] **Step 4: Verify**

Run: `flutter test test/features/documents/ && flutter analyze`
Expected: PASS, no new issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/documents/templates/nda_template.dart lib/features/documents/templates/employment_contract_template.dart lib/features/documents/generate_screen.dart
git commit -m "feat(documents): NDA + employment contract sign with resolved legal signatory"
```

---

### Task 9: Profile "Authorized Signatory" card

**Files:**
- Create: `lib/features/employees/profile/widgets/signatory_section.dart`
- Modify: `lib/features/employees/profile/tabs/profile_tab.dart`

**Interfaces:**
- Consumes: repository setters + providers (Task 2), `employeeByIdProvider`, `userProfileProvider.canManageEmployees`.
- Produces: `SignatorySection({required Employee employee})` widget.

No widget test — the section is thin UI over Task 2's repository methods; repo tests need a live Supabase (unavailable). Verified by `flutter analyze` + Task 10 GUI smoke.

- [ ] **Step 1: Create the widget**

Create `lib/features/employees/profile/widgets/signatory_section.dart`:

```dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/employee.dart';
import '../../../../data/repositories/employee_repository.dart';

/// "Authorized Signatory" card on the employee profile. HR/Admin only
/// (caller gates visibility). Lets HR flag the employee as the company's
/// HR / Legal signatory, set the printed title, and upload a transparent
/// PNG signature that is rendered onto generated documents.
class SignatorySection extends ConsumerStatefulWidget {
  final Employee employee;
  const SignatorySection({super.key, required this.employee});

  @override
  ConsumerState<SignatorySection> createState() => _SignatorySectionState();
}

class _SignatorySectionState extends ConsumerState<SignatorySection> {
  late final TextEditingController _title =
      TextEditingController(text: widget.employee.signatoryTitle ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(employeeByIdProvider(widget.employee.id));
    ref.invalidate(hrSignatoryProvider);
    ref.invalidate(legalSignatoryProvider);
  }

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleCapacity({required bool hr, required bool enable}) async {
    final repo = ref.read(employeeRepositoryProvider);
    if (enable) {
      // Transfer confirm when someone else already holds the capacity.
      final holder = await repo.signatoryFor(hr: hr);
      if (holder != null && holder.id != widget.employee.id) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Transfer ${hr ? 'HR' : 'Legal'} Signatory?'),
            content: Text(
                '${holder.fullName} currently holds this capacity. Transfer '
                'it to ${widget.employee.fullName}? New documents will carry '
                'the new signatory; already-generated documents keep the '
                'signature they were issued with.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Transfer')),
            ],
          ),
        );
        if (ok != true) return;
      }
    }
    await _run(() => repo.setSignatoryCapacity(
        employeeId: widget.employee.id, hr: hr, enabled: enable));
  }

  Future<void> _uploadSignature() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return;
    // PNG magic bytes — reject renamed JPEGs etc.; docs need transparency.
    const magic = [0x89, 0x50, 0x4E, 0x47];
    if (bytes.length < 4 ||
        bytes[0] != magic[0] ||
        bytes[1] != magic[1] ||
        bytes[2] != magic[2] ||
        bytes[3] != magic[3]) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Not a PNG file. Upload a transparent PNG.')));
      }
      return;
    }
    if (bytes.length > 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Signature PNG must be 1 MB or smaller.')));
      }
      return;
    }
    await _run(() => ref
        .read(employeeRepositoryProvider)
        .setSignaturePng(widget.employee.id, base64Encode(bytes)));
  }

  @override
  Widget build(BuildContext context) {
    // Watch the fresh row so toggles reflect writes without a manual reload.
    final emp = ref.watch(employeeByIdProvider(widget.employee.id)).asData?.value ??
        widget.employee;
    final sigBytes = emp.signaturePngB64 == null
        ? null
        : base64Decode(emp.signaturePngB64!);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Authorized Signatory',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Documents auto-fill this employee\'s name, title, and signature.',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('HR Signatory'),
            subtitle: const Text('Payslips, COE, NTE, notices, final pay'),
            value: emp.isHrSignatory,
            onChanged: _busy
                ? null
                : (v) => _toggleCapacity(hr: true, enable: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Legal Signatory'),
            subtitle: const Text('Employment contracts, NDA'),
            value: emp.isLegalSignatory,
            onChanged: _busy
                ? null
                : (v) => _toggleCapacity(hr: false, enable: v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Printed Title',
              hintText: 'e.g. HR Manager',
              isDense: true,
            ),
            onSubmitted: (_) => _saveTitle(),
            onTapOutside: (_) => _saveTitle(),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 160,
                height: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: sigBytes != null
                    ? Image.memory(sigBytes, fit: BoxFit.contain)
                    : Center(
                        child: Text('No signature',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).disabledColor))),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonal(
                    onPressed: _busy ? null : _uploadSignature,
                    child: const Text('Upload PNG'),
                  ),
                  if (sigBytes != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => ref
                              .read(employeeRepositoryProvider)
                              .setSignaturePng(widget.employee.id, null)),
                      child: const Text('Remove'),
                    ),
                  Text('Transparent PNG, max 1 MB',
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveTitle() async {
    final current = ref
            .read(employeeByIdProvider(widget.employee.id))
            .asData
            ?.value
            ?.signatoryTitle ??
        widget.employee.signatoryTitle ??
        '';
    if (_title.text.trim() == current.trim()) return;
    await _run(() => ref
        .read(employeeRepositoryProvider)
        .setSignatoryTitle(widget.employee.id, _title.text));
  }
}
```

- [ ] **Step 2: Insert into ProfileTab**

In `lib/features/employees/profile/tabs/profile_tab.dart`, add `import '../widgets/signatory_section.dart';` and append at the END of the `ListView` children (after the last existing `_Section`):

```dart
        if (profile?.canManageEmployees ?? false) ...[
          const SizedBox(height: 16),
          SignatorySection(employee: employee),
        ],
```

(`profile` is already in scope at the top of `build`.)

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: no new issues. (If `firstOrNull` is unresolved, add `import 'package:collection/collection.dart';` — it's already a transitive dependency — or use `result!.files.first` guarded by a null/empty check, matching the hiring-entities logo picker.)

- [ ] **Step 4: Commit**

```bash
git add lib/features/employees/profile/widgets/signatory_section.dart lib/features/employees/profile/tabs/profile_tab.dart
git commit -m "feat(employees): Authorized Signatory card on employee profile"
```

---

### Task 10: Full verification, migration apply (checkpoint), GUI smoke

**Files:**
- No code changes expected (fixes only if verification fails).

- [ ] **Step 1: Full test + analyze pass**

Run: `flutter test && flutter analyze`
Expected: all tests PASS (pre-existing suites included), analyze clean. Fix anything that fails before proceeding.

- [ ] **Step 2: CHECKPOINT — apply the migration to prod**

STOP and confirm with the user before running:

```bash
supabase db push
```

Expected: applies `20260801000001_employee_signatories.sql`. This is prod — user must approve.

- [ ] **Step 3: GUI smoke (with the user / via run skill)**

Launch: `flutter run -d linux --dart-define-from-file=env/prod.json`

Checklist:
1. Employee profile → Brixter → Profile tab: "Authorized Signatory" card visible (HR/Admin login), toggle **HR Signatory** ON, set title "HR Manager", upload a transparent PNG.
2. Payslips → any payslip preview: signature image + "Brixter Del Mundo / HR Manager" replace the old hardcoded text.
3. Documents → generate an NTE: HR name pre-filled, PDF shows the signature on the HR line; employee line stays blank.
4. Flag a Legal signatory; generate an NDA: "For the Company" line signed.
5. Open a PREVIOUSLY saved document (generated before this feature): renders unchanged, no signature, no errors.
6. Save a new document, reopen via /documents/view/:id: signature persists (snapshot in generation_options).
7. Toggle HR Signatory on a second employee: transfer dialog appears; confirm; old docs unchanged.

- [ ] **Step 4: Commit any smoke fixes + wrap up**

```bash
git add -A -- lib/ test/ && git commit -m "fix(signatories): GUI smoke fixes"  # only if fixes were needed
```

Then follow superpowers:finishing-a-development-branch. NOTE: `git push origin main` is blocked for the agent in this repo — the user runs pushes themselves.
