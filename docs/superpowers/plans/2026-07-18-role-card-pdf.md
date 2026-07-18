# Role Card → PDF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export a role scorecard as an employee-facing PDF (mission, responsibilities, KPIs, skills, behaviors — no compensation), reachable from the role scorecard detail screen and the employee review detail screen.

**Architecture:** Reuse the existing document PDF stack end to end. A pure function maps a `RoleScorecard` to a `List<Block>`; a thin `ConsumerWidget` hands those blocks to `buildDocumentPdf` inside the shared `PdfPreviewScaffold` (which already provides print/download/share). One new route and a by-id provider tie it together. Nothing is persisted — the PDF is regenerated from the live card on every open.

**Tech Stack:** Flutter, Riverpod, GoRouter, the `pdf`/`printing` packages already in `pubspec.yaml`, and the block library under `lib/features/documents/blocks/`.

## Global Constraints

- Gate on `flutter analyze` only — the repo has mixed formatter styles; do NOT run `dart format`. Match the surrounding file's style.
- No new packages. Reuse `buildDocumentPdf`, `PdfPreviewScaffold`, `PdfTheme`, `loadCompanyLogoBytes`, `hiringEntityByIdProvider`, and existing blocks.
- The PDF is employee-facing: **never render compensation** (salary range, base salary, wage type, hours).
- Render the current card only — no version/snapshot logic.
- In-app action buttons use the single Luxium purple CTA per `PRODUCT.md`; the PDF inherits `PdfTheme` (no new colors/fonts).
- Empty sections are omitted, never rendered as blank headings.

---

### Task 1: `roleCardBlocks` — map a role scorecard to PDF blocks

**Files:**
- Create: `lib/features/responsibility_cards/role_card_pdf.dart`
- Test: `test/features/responsibility_cards/role_card_pdf_test.dart`

**Interfaces:**
- Consumes: `RoleScorecard` and its nested `ResponsibilityArea` / `KpiItem` / `RequiredSkill` / `BehavioralExpectation` (from `lib/data/models/role_scorecard.dart`); the block classes listed in the implementation.
- Produces: `List<Block> roleCardBlocks(RoleScorecard card, {Uint8List? logoBytes, String companyName = '', String? companyAddress})` — consumed by Task 2.

- [ ] **Step 1: Write the failing test**

Create `test/features/responsibility_cards/role_card_pdf_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/documents/blocks/section_heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/table_block.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';
import 'package:payroll_flutter/features/responsibility_cards/role_card_pdf.dart';

RoleScorecard buildCard({
  String mission = 'Own the storefront experience.',
  List<ResponsibilityArea> responsibilities = const [
    ResponsibilityArea(area: 'Merchandising', tasks: ['Curate weekly drops']),
  ],
  List<KpiItem> kpis = const [
    KpiItem(
        name: 'Conversion',
        measurement: 'CVR %',
        target: '3%',
        frequency: 'Monthly'),
  ],
  List<RequiredSkill> skills = const [
    RequiredSkill(name: 'Excel', description: 'Pivot tables'),
  ],
  List<BehavioralExpectation> behaviors = const [
    BehavioralExpectation(name: 'Ownership', description: 'Sees issues through'),
  ],
}) =>
    RoleScorecard(
      id: 'card-1',
      companyId: 'co-1',
      jobTitle: 'Brand Associate',
      missionStatement: mission,
      responsibilities: responsibilities,
      kpis: kpis,
      requiredSkills: skills,
      behavioralExpectations: behaviors,
      wageType: 'MONTHLY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'MON_FRI',
      isActive: true,
      effectiveDate: DateTime(2026, 1, 1),
    );

void main() {
  test('a populated card renders every section in order', () {
    final blocks = roleCardBlocks(buildCard());
    expect(blocks.whereType<TitleBlock>().length, 1);
    final headings =
        blocks.whereType<SectionHeadingBlock>().map((b) => b.title).toList();
    expect(headings, [
      'Mission',
      'Key Responsibilities',
      'Key Performance Indicators',
      'Required Skills',
      'Behavioral Expectations',
    ]);
    expect(
      blocks.whereType<SectionHeadingBlock>().map((b) => b.number).toList(),
      [1, 2, 3, 4, 5],
    );
    expect(blocks.whereType<TableBlock>().length, 1);
  });

  test('empty sections are omitted and numbering stays sequential', () {
    final blocks = roleCardBlocks(buildCard(
      mission: '',
      kpis: const [],
      skills: const [],
      behaviors: const [],
    ));
    final headings =
        blocks.whereType<SectionHeadingBlock>().map((b) => b.title).toList();
    expect(headings, ['Key Responsibilities']);
    expect(blocks.whereType<SectionHeadingBlock>().single.number, 1);
    expect(blocks.whereType<TableBlock>(), isEmpty);
  });

  test('with no branding the first block is the title, not a letterhead', () {
    final blocks = roleCardBlocks(buildCard());
    expect(blocks.first, isA<TitleBlock>());
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/responsibility_cards/role_card_pdf_test.dart`
Expected: FAIL — `role_card_pdf.dart` / `roleCardBlocks` does not exist (compile error).

- [ ] **Step 3: Write the implementation**

Create `lib/features/responsibility_cards/role_card_pdf.dart`:

```dart
import 'dart:typed_data';

import '../../data/models/role_scorecard.dart';
import '../documents/blocks/block.dart';
import '../documents/blocks/key_value_block.dart';
import '../documents/blocks/labelled_bullet_list_block.dart';
import '../documents/blocks/letterhead_block.dart';
import '../documents/blocks/paragraph_block.dart';
import '../documents/blocks/section_heading_block.dart';
import '../documents/blocks/spacer_block.dart';
import '../documents/blocks/table_block.dart';
import '../documents/blocks/title_block.dart';

/// Maps a role scorecard to the ordered PDF blocks for an employee-facing role
/// reference. Pure — no I/O. Empty sections are omitted so a sparse card never
/// renders a blank heading. Section numbers are assigned in render order, so
/// omitting a section does not leave a gap in the numbering.
List<Block> roleCardBlocks(
  RoleScorecard card, {
  Uint8List? logoBytes,
  String companyName = '',
  String? companyAddress,
}) {
  final blocks = <Block>[];
  var section = 0;

  if (logoBytes != null || companyName.isNotEmpty) {
    blocks.add(LetterheadBlock(
      logoBytes: logoBytes,
      companyName: companyName,
      companyAddress:
          (companyAddress?.isEmpty ?? true) ? null : companyAddress,
    ));
    blocks.add(const SpacerBlock(16));
  }

  blocks.add(TitleBlock(card.jobTitle));
  blocks.add(KeyValueBlock([
    KeyValueRow(
      'Effective date',
      card.effectiveDate.toIso8601String().substring(0, 10),
    ),
    KeyValueRow('Status', card.isActive ? 'Active' : 'Inactive'),
  ]));

  if (card.missionStatement.trim().isNotEmpty) {
    blocks.add(SectionHeadingBlock(number: ++section, title: 'Mission'));
    blocks.add(ParagraphBlock(card.missionStatement));
  }

  if (card.responsibilities.isNotEmpty) {
    blocks.add(SectionHeadingBlock(
        number: ++section, title: 'Key Responsibilities'));
    blocks.add(LabelledBulletListBlock(
      items: [
        for (final area in card.responsibilities)
          LabelledBulletItem(
            leadBold: area.area,
            body: '',
            children: [
              for (final task in area.tasks)
                LabelledBulletItem(leadBold: '', body: task),
            ],
          ),
      ],
    ));
  }

  if (card.kpis.isNotEmpty) {
    blocks.add(SectionHeadingBlock(
        number: ++section, title: 'Key Performance Indicators'));
    blocks.add(TableBlock(
      headers: const ['KPI', 'Measurement', 'Target', 'Frequency'],
      rows: [
        for (final kpi in card.kpis)
          [kpi.name, kpi.measurement, kpi.target, kpi.frequency],
      ],
    ));
  }

  if (card.requiredSkills.isNotEmpty) {
    blocks.add(
        SectionHeadingBlock(number: ++section, title: 'Required Skills'));
    blocks.add(LabelledBulletListBlock(
      items: [
        for (final skill in card.requiredSkills)
          LabelledBulletItem(leadBold: skill.name, body: skill.description),
      ],
    ));
  }

  if (card.behavioralExpectations.isNotEmpty) {
    blocks.add(SectionHeadingBlock(
        number: ++section, title: 'Behavioral Expectations'));
    blocks.add(LabelledBulletListBlock(
      items: [
        for (final behavior in card.behavioralExpectations)
          LabelledBulletItem(
              leadBold: behavior.name, body: behavior.description),
      ],
    ));
  }

  return blocks;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/responsibility_cards/role_card_pdf_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify analyze is clean**

Run: `flutter analyze lib/features/responsibility_cards/role_card_pdf.dart test/features/responsibility_cards/role_card_pdf_test.dart`
Expected: No errors (info/warnings only, if any).

- [ ] **Step 6: Commit**

```bash
git add lib/features/responsibility_cards/role_card_pdf.dart test/features/responsibility_cards/role_card_pdf_test.dart
git commit -m "feat(role-card): map role scorecard to PDF blocks"
```

---

### Task 2: `RoleCardPdfScreen` + by-id provider + route

**Files:**
- Create: `lib/features/responsibility_cards/role_card_pdf_screen.dart`
- Modify: `lib/app/router.dart` (add one import + one route)
- Test: `test/features/responsibility_cards/role_card_pdf_screen_test.dart`

**Interfaces:**
- Consumes: `roleCardBlocks(...)` (Task 1); `roleScorecardByIdProvider` — a `FutureProvider.family<RoleScorecard?, String>` that ALREADY EXISTS in `lib/features/documents/providers.dart` (delegates to `RoleScorecardRepository.byId`); `hiringEntityByIdProvider` (same file, `lib/features/documents/providers.dart`); `loadCompanyLogoBytes(HiringEntity?)` (in `lib/features/documents/brand_logo.dart`); `buildDocumentPdf({required List<Block> blocks, required PdfTheme theme})` (in `lib/features/documents/pdf/pdf_builder.dart`); `PdfPreviewScaffold({required buildPdf, required filename})` (in `lib/core/pdf/pdf_preview_scaffold.dart`); `PdfTheme.defaults()` (in `lib/core/pdf/pdf_theme.dart`).
- Produces: `RoleCardPdfScreen({required String cardId})` — consumed by Task 3 and the router.

- [ ] **Step 1: Reuse the existing by-id provider (no new provider)**

`roleScorecardByIdProvider` — `FutureProvider.family<RoleScorecard?, String>` delegating to `roleScorecardRepositoryProvider.byId(id)` — already exists in `lib/features/documents/providers.dart`. **Do not add a duplicate** (a second top-level provider with the same name causes an `ambiguous_import` compile error). The screen created in Step 4 already imports `../documents/providers.dart` (for `hiringEntityByIdProvider`), so the provider is in scope with no change. This step is a no-op; proceed to Step 2.

- [ ] **Step 2: Write the failing widget test (not-found path)**

Create `test/features/responsibility_cards/role_card_pdf_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:payroll_flutter/features/responsibility_cards/role_card_pdf_screen.dart';

void main() {
  testWidgets('shows a not-found message when the card is missing',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleScorecardByIdProvider('missing').overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: RoleCardPdfScreen(cardId: 'missing')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Role card not found.'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/responsibility_cards/role_card_pdf_screen_test.dart`
Expected: FAIL — `RoleCardPdfScreen` does not exist (compile error).

- [ ] **Step 4: Write the screen**

Create `lib/features/responsibility_cards/role_card_pdf_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../documents/brand_logo.dart';
import '../documents/pdf/pdf_builder.dart';
import '../documents/providers.dart';
import 'role_card_pdf.dart';

/// Ephemeral, on-the-fly PDF preview of the current role scorecard. Nothing is
/// persisted — the PDF is rebuilt from the live card every time this opens.
class RoleCardPdfScreen extends ConsumerWidget {
  final String cardId;
  const RoleCardPdfScreen({super.key, required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(roleScorecardByIdProvider(cardId));
    return Scaffold(
      appBar: AppBar(title: const Text('Role reference')),
      body: cardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _message(context, 'Could not load the role card.\n$e'),
        data: (card) {
          if (card == null) {
            return _message(context, 'Role card not found.');
          }
          final slug = card.jobTitle
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
              .replaceAll(RegExp(r'(^-|-$)'), '');
          return PdfPreviewScaffold(
            filename: '${slug.isEmpty ? 'role' : slug}-role-card.pdf',
            buildPdf: (format) async {
              final theme = await PdfTheme.defaults();
              final entityId = card.hiringEntityId;
              final entity = (entityId == null || entityId.isEmpty)
                  ? null
                  : await ref.read(hiringEntityByIdProvider(entityId).future);
              final logo = await loadCompanyLogoBytes(entity);
              final address = [entity?.addressLine1, entity?.addressLine2]
                  .whereType<String>()
                  .where((s) => s.isNotEmpty)
                  .join(', ');
              return buildDocumentPdf(
                blocks: roleCardBlocks(
                  card,
                  logoBytes: logo,
                  companyName: entity?.name ?? '',
                  companyAddress: address,
                ),
                theme: theme,
              );
            },
          );
        },
      ),
    );
  }

  Widget _message(BuildContext context, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/responsibility_cards/role_card_pdf_screen_test.dart`
Expected: PASS (1 test).

- [ ] **Step 6: Add the route**

First find where the other `/responsibility-cards` routes are declared:

Run: `grep -n "responsibility-cards" lib/app/router.dart`

In `lib/app/router.dart`, add the import next to the other performance/responsibility imports near the top:

```dart
import '../features/responsibility_cards/role_card_pdf_screen.dart';
```

Then add this route **before** any `/responsibility-cards/:id` route (so `:id/pdf` is matched first), inside the same `ShellRoute` routes list:

```dart
GoRoute(
  path: '/responsibility-cards/:id/pdf',
  builder: (c, s) => RoleCardPdfScreen(cardId: s.pathParameters['id']!),
),
```

If there is no `/responsibility-cards/:id` route, add it anywhere in that routes list; ordering only matters relative to a `:id` sibling.

- [ ] **Step 7: Verify analyze is clean**

Run: `flutter analyze lib/features/responsibility_cards/role_card_pdf_screen.dart lib/app/router.dart`
Expected: No errors.

- [ ] **Step 8: Commit**

```bash
git add lib/features/responsibility_cards/role_card_pdf_screen.dart lib/app/router.dart test/features/responsibility_cards/role_card_pdf_screen_test.dart
git commit -m "feat(role-card): PDF preview screen, by-id provider, and route"
```

---

### Task 3: Entry points on the detail and review screens

**Files:**
- Modify: `lib/features/responsibility_cards/role_scorecard_detail_screen.dart` (AppBar `actions:`, ~line 33)
- Modify: `lib/features/performance/employee_review_detail_screen.dart` (AppBar `actions:`, near the existing "Monthly check-in" / "Reopen" actions)

**Interfaces:**
- Consumes: the route `/responsibility-cards/:id/pdf` (Task 2); `context.push` (go_router, already imported in both files); `cardId` (in scope in the detail screen build) and `review.value!.responsibilityCardId` (in the review screen).
- Produces: nothing consumed downstream — these are leaf navigation actions.

- [ ] **Step 1: Add the detail-screen action**

In `lib/features/responsibility_cards/role_scorecard_detail_screen.dart`, in the `AppBar`'s `actions:` list, add this as the FIRST action (it is available to anyone who can view the card — do NOT wrap it in the `canManage` guard):

```dart
IconButton(
  tooltip: 'Download / Print PDF',
  icon: const Icon(Icons.picture_as_pdf_outlined),
  onPressed: () => context.push('/responsibility-cards/$cardId/pdf'),
),
```

- [ ] **Step 2: Add the review-screen link**

In `lib/features/performance/employee_review_detail_screen.dart`, inside the `AppBar`'s `actions:` list, add this before the existing `const SizedBox(width: 8)` that precedes the "Manager evaluation" button:

```dart
if (review.value != null)
  TextButton.icon(
    onPressed: () => context.push(
      '/responsibility-cards/${review.value!.responsibilityCardId}/pdf',
    ),
    icon: const Icon(Icons.description_outlined),
    label: const Text('Role reference'),
  ),
```

- [ ] **Step 3: Verify analyze is clean**

Run: `flutter analyze lib/features/responsibility_cards/role_scorecard_detail_screen.dart lib/features/performance/employee_review_detail_screen.dart`
Expected: No errors.

- [ ] **Step 4: Manual smoke (navigation has no unit test)**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`
Then: open a Responsibility Card → tap the PDF action → the preview renders with print/download. Open an employee review → tap "Role reference" → the same preview renders for that review's card. Confirm no compensation appears.

- [ ] **Step 5: Run the full suite + analyze**

Run: `flutter test`
Expected: All tests pass (prior count + 4 new).
Run: `flutter analyze`
Expected: Error count unchanged from baseline (0 errors).

- [ ] **Step 6: Commit**

```bash
git add lib/features/responsibility_cards/role_scorecard_detail_screen.dart lib/features/performance/employee_review_detail_screen.dart
git commit -m "feat(role-card): PDF entry points on detail and review screens"
```

---

## Notes for the implementer

- The role card carries `hiringEntityId`; the letterhead resolves from it. When it is null (card has no hiring entity), the PDF renders with no logo and no company name — that path is expected, not an error.
- `PdfPreviewScaffold`'s `buildPdf` closure receives a `PdfPageFormat format` argument that is intentionally unused here — `buildDocumentPdf` uses the theme's page format, exactly as `document_view_screen.dart` does.
- Do not add the role card to the document template registry (`kDocumentCategories`) — that pipeline is employee-scoped and would misplace a role-scoped document. This feature deliberately bypasses it.
