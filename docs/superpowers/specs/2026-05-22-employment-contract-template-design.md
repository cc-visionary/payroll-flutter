# Employment Contract Template — Design

**Date:** 2026-05-22
**Status:** Draft, awaiting review
**Owner:** Donald
**Extends:** [`2026-05-05-document-templates-design.md`](2026-05-05-document-templates-design.md) and the Non-Reg follow-on. Adds the 5th template to the doc-templates system, reusing the block library, `DocumentTemplate` interface, registry, generate-screen, autofill pattern, brand logo, and shared autocomplete inputs.

## Goal

Add **Employment Contract** as the 5th document template. It is the largest template — an 8-9 page probationary employment agreement: preamble (parties), WITNESSETH recitals, 17 numbered clauses, signature page with two witnesses, and **Annex A** (Duties, Responsibilities, Work Hours, KPIs, Evaluation Timeline).

Canonical text is lifted verbatim from `[06] LUXIUM/[02] HR/[02] Employee Records/JAM/Employment Contract Template_Vidal.pdf` (8 pages). Final copy confirmed with the user before merge.

**Maximize autofill** (user decision): employee identity + address, company identity + address + representative (from hiring-entity Document Defaults), dates (hire + probation end), compensation + work hours (from the employee's Role Scorecard), position, and Annex A duties/KPIs (from the Role Scorecard) all pre-fill. Everything stays editable. Manual entry only where no record exists.

**Annex A** (user decision): auto-populated from the employee's assigned `RoleScorecard` (`missionStatement`, `responsibilities` [area + tasks], `kpis` [metric + frequency], `workHoursPerDay`, `workDaysPerWeek`, `baseSalary`), rendered as the annex, editable before generating.

## Non-goals

Same as the v1 doc-templates spec: ephemeral generation (no DB writes / storage), no e-signature, no HR-authored templates, no bulk issuance.

Additionally:
- **Annex B (Standards for Regularization)** is referenced by the contract body but NOT generated here — it's a separate document. The contract only mentions it.
- **Per-clause rich-text editing.** Clause bodies are fixed legal `const` text with `{placeholder}` interpolation, not freely editable. Annex A's responsibilities/KPIs ARE editable (structured fields), but the 17 clauses are fixed wording (only their placeholders vary).

## Data sources (autofill)

| Field | Source |
|---|---|
| `employeeFullName` | `Employee.fullName` |
| `employeeAddress` | composed from `Employee.addressLine1/2`, `city`, `province`, `zipCode` |
| `companyName` | `HiringEntity.name` |
| `companyAddress` | composed from `HiringEntity.addressLine1/2`, `city`, `province`, `zipCode` |
| `representativeName` | `HiringEntity.hrManagerName` (the "represented by its … " party) |
| `representativeRole` | `HiringEntity.legalSignatoryRole` if set, else default `'People Manager'` |
| `place` | `"{HiringEntity.city}, {HiringEntity.province}, Philippines"` |
| `dateEntered` | default today (contract execution date) |
| `industry` | manual, default `'Retail Industry'` (not stored on any record) |
| `position` | `Employee.jobTitle` (fallback to Role Scorecard `jobTitle`) |
| `probationStart` | latest `HIRE` event date, else `Employee.hireDate` |
| `probationEnd` | `probationStart + 6 months` (PH Labor Code default), editable |
| `monthlySalary` | Role Scorecard `baseSalary`, else `Employee.declaredWageOverride`, else manual |
| `workHoursPerDay` | Role Scorecard `workHoursPerDay` (default 8) |
| `workDaysPerWeek` | Role Scorecard `workDaysPerWeek` (default `'Monday to Saturday'`) |
| `nonCompeteMonths` | fixed default `24`, editable |
| `employerSignatoryName` / `Role` | `representativeName` / `representativeRole` (same as preamble) |
| `witness1Name` / `Role`, `witness2Name` / `Role` | manual (not stored). Form uses `EmployeeNameField` + `RoleTitleField`. |
| Annex A `missionStatement`, `responsibilities`, `kpis` | employee's `RoleScorecard` (via `Employee.roleScorecardId`) |
| `logoBytes` | `loadBrandLogoBytes(companyName, code)` — same as other templates |

Role scorecard fetched via the employee's `roleScorecardId`. Add a `roleScorecardByIdProvider` in `lib/features/documents/providers.dart` if one doesn't already exist (the `roleScorecardRepositoryProvider.byId` exists; wrap it in a `FutureProvider.family`). All scorecard reads are best-effort (try/catch → empty), like the other autofills.

## Architecture

A single new `DocumentTemplate<EmploymentContractInputs>` following the established pattern. Reuses the existing block library plus **two new blocks**:

### New blocks

**`LetteredListBlock`** — list with `a. b. c.` markers (lower-alpha). Section 13 (Termination) uses lettered grounds a-f. Mirrors `NumberedListBlock` but with alpha markers.

```dart
class LetteredListBlock extends Block {
  final List<String> items;
  const LetteredListBlock(this.items);
  // renders 'a.', 'b.', … 'z.' then falls back to numbers past 26.
}
```

**`PartyBlock`** — the preamble's indented party description: a left-indented paragraph that supports embedded bold spans (party name) and italic spans (address). Used twice (EMPLOYER, EMPLOYEE). Reuses `EmphasisSpan` from `emphasis_paragraph_block.dart` but adds a left indent (~110pt) to match the source's block-quote layout.

```dart
class PartyBlock extends Block {
  final List<EmphasisSpan> spans; // bold name, normal/italic body
  final double leftIndent;        // default 110
  const PartyBlock({required this.spans, this.leftIndent = 110});
}
```

(`EmphasisSpan` gains an optional `italic` flag if it doesn't have one — check `emphasis_paragraph_block.dart`; if it only has `bold`, add `final bool italic;` defaulting false, and render italic when set. Backward-compatible.)

Everything else reuses existing blocks: `LogoBlock`, `TitleBlock` (centered), `ParagraphBlock`, `EmphasisParagraphBlock`, `SectionHeadingBlock`, `BulletListBlock`, `NumberedListBlock`, `NestedNumberedListBlock`, `LabelledBulletListBlock`, `MultiSignatureBlock`, `SignatureBlock`, `HeadingBlock`, `PageBreakBlock`, `SpacerBlock`.

### File layout

```
lib/features/documents/
├── blocks/
│   ├── lettered_list_block.dart        # NEW
│   ├── party_block.dart                # NEW
│   └── emphasis_paragraph_block.dart   # EXTEND: optional italic on EmphasisSpan
├── templates/
│   ├── employment_contract_inputs.dart # NEW
│   ├── employment_contract_validate.dart # NEW
│   ├── employment_contract_template.dart # NEW
│   └── template_registry.dart          # ADD EmploymentContractTemplate()
├── forms/
│   └── employment_contract_form.dart   # NEW
├── inputs/
│   └── annex_a_editor.dart             # NEW — responsibilities + KPIs repeater
└── providers.dart                      # ADD roleScorecardByIdProvider
```

Plus `generate_screen.dart` wiring (state field + autofill branch + form branch + preview branch + ValueKey), mirroring the other four templates.

## Typed inputs

```dart
class ContractResponsibility {
  final String area;
  final List<String> tasks;
  const ContractResponsibility({required this.area, required this.tasks});
}

class ContractKpi {
  final String metric;
  final String frequency;
  const ContractKpi({required this.metric, required this.frequency});
}

class EmploymentContractInputs extends TemplateInputs {
  // Parties
  final String employeeId;
  final String employeeFullName;
  final String employeeAddress;
  final String companyId;
  final String companyName;
  final String companyAddress;
  final String representativeName;   // "represented by its … "
  final String representativeRole;   // default "People Manager"
  // Recitals / clauses
  final String place;                // "Binondo, Metro Manila, Philippines"
  final DateTime dateEntered;        // execution date
  final String industry;             // "Retail Industry"
  final String position;             // job title
  final DateTime? probationStart;
  final DateTime? probationEnd;
  final String monthlySalary;        // formatted string, e.g. "17,000" (PHP)
  final int workHoursPerDay;         // default 8
  final String workDaysPerWeek;      // "Monday to Saturday"
  final int nonCompeteMonths;        // default 24
  // Signatories
  final String employerSignatoryName;
  final String employerSignatoryRole;
  final String witness1Name;
  final String witness1Role;
  final String witness2Name;
  final String witness2Role;
  // Annex A (from Role Scorecard, editable)
  final String missionStatement;
  final List<ContractResponsibility> responsibilities;
  final List<ContractKpi> kpis;
  // Branding
  final Uint8List? logoBytes;

  // + const constructor, copyWith (standard `?? this.x` style), toDebugMap
}
```

`emptyInputs()` returns blanks with `dateEntered = today`, `workHoursPerDay = 8`, `workDaysPerWeek = 'Monday to Saturday'`, `nonCompeteMonths = 24`, `representativeRole = 'People Manager'`, empty lists.

## Gates

None.

## Validation (`validateEmploymentContract`)

Required (each → field-keyed `ValidationError`):
- `employeeId`, `companyId`
- `employeeFullName`, `employeeAddress`
- `companyName`, `companyAddress`
- `representativeName`, `representativeRole`
- `place`, `industry`, `position`
- `probationStart`, `probationEnd` (both non-null; `probationEnd >= probationStart`)
- `monthlySalary` non-empty
- `employerSignatoryName`, `employerSignatoryRole`
- `responsibilities` min 1 (Annex A must have content); each responsibility `area` non-empty with min 1 task
- `workHoursPerDay > 0`, `workDaysPerWeek` non-empty, `nonCompeteMonths > 0`

Witnesses are optional (the printed contract can be hand-filled). Mission statement optional. KPIs optional.

## Canonical clause text

Committed as `const String` in `employment_contract_template.dart`. Placeholders in `{braces}` interpolated via the shared `interpolate(template, vars, lenient: true)` helper. Verbatim from the source PDF:

- **Preamble intro:** `"This Agreement entered into this {dateEntered}, at {place}, by and between:"`
- **EMPLOYER party:** `"{companyName}, a company duly organized and registered under the laws of the Philippines, with principal office address at {companyAddress} herein represented by its {representativeRole}, {representativeName}, herein referred to as the \"EMPLOYER\""` (companyName bold, address italic)
- **EMPLOYEE party:** `"{employeeFullName}, of legal age, with address at {employeeAddress}, hereinafter referred to as the \"EMPLOYEE\"."` (name bold, address italic)
- **Recitals (3 WHEREAS, numbered):**
  1. `"WHEREAS, the EMPLOYER is a corporation engaged in {industry};"`
  2. `"WHEREAS, the EMPLOYEE has qualified in the pre-employment requirements conducted by the EMPLOYER;"`
  3. `"WHEREAS, the EMPLOYER is interested in engaging the services of the EMPLOYEE as {position};"`
- **NOW THEREFORE:** `"NOW, THEREFORE, for and in consideration of the foregoing premises, the parties hereby agree as follows:"`
- **§1 PROBATIONARY EMPLOYMENT:** `"Subject to the job performance, the EMPLOYER agrees to employ EMPLOYEE and EMPLOYEE agrees to remain in the employ of EMPLOYER on probation under the terms and conditions hereinafter set forth."`
- **§2 JOB TITLE AND DESCRIPTION:** `"The EMPLOYEE's probationary employment is as a {position}. A more specific description of the EMPLOYEE's duties, responsibilities and work hours is outlined in Annex \"A\" and made an integral part of this contract."`
- **§3 PERIOD OF PROBATIONARY EMPLOYMENT:** two paragraphs — `"The EMPLOYEE is employed on probationary status for a period of 6 months or 180 calendar days beginning on {probationStart} and ending on {probationEnd}. Prior to the expiration of the EMPLOYEE's probationary employment, he/she shall be notified in writing if he/she qualified as a regular employee."` + `"This employment is subject to the standards for regularization, which EMPLOYEE hereby acknowledges to have received and is aware of. These standards are outlined in Annex \"B\" which is made an integral part of this Contract."`
- **§4 PROBATIONARY EVALUATION:** `"The EMPLOYER will evaluate an employee's performance during the probationary period. The EMPLOYEE's immediate superior shall make evaluation or such other representative appointed by the EMPLOYER. The evaluation of the EMPLOYEE shall be made in writing. The EMPLOYEE agrees that it is the prerogative of the EMPLOYER to evaluate his/her performance and decide whether he/she is qualified to be a regular employee. If the EMPLOYEE fails to meet the standards for regularization set forth by the EMPLOYER, the EMPLOYER may terminate this Contract in accordance with the procedure prescribed by law or any applicable rules and regulations."`
- **§5 COMPENSATION:** three paragraphs. P1: `"The EMPLOYEE will be paid a basic salary of PHP {monthlySalary} per month, Philippine Currency payable in two installments, once on the 15th and at the end of the month. The EMPLOYEE's salary will be paid either through ATM, in cash, by a bank check, or by a bank or postal transfer, from which shall be deducted, where applicable, the EMPLOYEE's social security contribution, withholding taxes and other government mandated deductions. Such rate does not include payment for OT during regular, rest day or holidays, which shall be paid separately as incurred."` P2: `"It is hereby further agreed, and the EMPLOYEE hereby acknowledges, that during the period of probationary employment, he/she shall not be entitled to the compensation and benefits extended by the EMPLOYER to its regular employees EXCEPT those herein aforestated and such benefits granted by law."` P3: `"Notwithstanding incidents when the EMPLOYER granted benefits, bonuses or allowance other than those defined in this contract, such incidents are not to be considered as an established practice or precedent and shall not form part of the benefits, bonuses and allowances due and demandable under this Contract of Employment."`
- **§6 WORK HOURS:** `"The EMPLOYEE shall work for a period of {workHoursPerDay} hours per day from {workDaysPerWeek}. In case of unusual volume of work, the EMPLOYER may require the EMPLOYEE to work on Sundays. Any work rendered in excess of {workHoursPerDay} hours per day shall be subject to payment of applicable overtime rate. Management prescribes the work schedule, and it reserves the right to change the schedule as it may deem necessary to meet operational requirements."`
- **§7 ASSIGNMENT OF TASKS:** `"On signing this Contract, the EMPLOYEE recognizes EMPLOYER's right and prerogative, to assign and re-assign him/her to perform such other tasks within EMPLOYER's organization, in any branch or unit, as may be deemed necessary or in the interest of the service."`
- **§8 MEDICAL/DRUG TESTS:** `"By signing this contract, the EMPLOYEE consents and agrees to, upon request from the EMPLOYER, undergo at a government accredited institute to be nominated by the EMPLOYER, a medical/drug tests at the expense of the EMPLOYEE. This is to be carried out for the purposes of determining the EMPLOYEE's physical and mental fitness to perform the functions of his job."`
- **§9 COMPANY RULES AND REGULATIONS:** two paragraphs. P1: `"All existing as well as future rules and regulations issued by the EMPLOYER are hereby deemed incorporated with this Contract. The EMPLOYEE recognizes that by signing this Contract, he/she shall be bound by all such rules and regulations, which the EMPLOYER may issue from time to time."` P2: `"On signing this Contract, the EMPLOYEE acknowledges his/her duty and responsibility to be aware of the EMPLOYER's rules and regulations regarding his/her employment and to fully comply with these in good faith."`
- **§10 DEDUCTIONS FOR COMPANY-INCURRED COSTS:** intro paragraph `"The EMPLOYEE agrees and acknowledges that the EMPLOYER has the right to deduct from the EMPLOYEE's salary any amounts corresponding to costs or expenses incurred by the EMPLOYER as a direct result of the EMPLOYEE's actions, negligence, or non-compliance with company policies, provided that such deductions are reasonable, duly documented, and in accordance with applicable laws and regulations."` + `"This includes, but is not limited to:"` + bullet list: `["Damage to or loss of company property due to the EMPLOYEE's negligence.", "Unauthorized expenses charged to the company.", "Costs arising from failure to return company-issued items such as IDs, uniforms, tools, or equipment upon termination of employment."]` + `"The EMPLOYER will notify the EMPLOYEE in writing before implementing any deductions, providing a detailed account of the costs and the reason for the deduction."`
- **§11 DISCIPLINARY MEASURES:** `"On signing this Contract, the EMPLOYEE hereby recognizes the EMPLOYER's right to impose disciplinary measures or sanctions, which may include, but are not limited to, termination of employment, suspensions, fines, salary deductions, withdrawal of benefits, loss of privileges, for any and all infraction, act or omission, irrespective of whether such infraction, act or omission constitutes a ground for termination."`
- **§12 NON-COMPETE AGREEMENT:** intro `"The EMPLOYEE agrees that for a period of {nonCompeteMonths} months following the termination of their employment, they will not:"` + bullets `["Directly or indirectly engage in any business or activity that competes with the business of the EMPLOYER within the Philippines.", "Solicit or attempt to solicit any of the EMPLOYER's clients, customers, or employees for purposes that would result in competition with the EMPLOYER."]` + P2 `"The EMPLOYEE acknowledges that this non-compete clause is reasonable in scope and duration and is necessary to protect the legitimate business interests of the EMPLOYER, including but not limited to the protection of trade secrets, confidential information, and customer relationships."` + P3 `"If the EMPLOYEE breaches this non-compete clause, the EMPLOYER reserves the right to pursue legal remedies, including but not limited to injunctive relief and damages."`
- **§13 TERMINATION OF EMPLOYMENT:** intro `"Aside from the just and authorized causes for the termination of employment enumerated in Arts. 282 to 284 of the Labor Code, the following acts and/or omissions of the EMPLOYEE shall, without limitation, similarly constitute just and authorized grounds for the termination of employment by the EMPLOYER and/or grounds for the EMPLOYER to impose disciplinary measures on the EMPLOYEE:"` + LetteredListBlock a-f: `["Intentional or unintentional violation of the EMPLOYER's policies, rules, and regulations as embodied in the Code of Discipline;", "Commission of an act which effects a loss of confidence on the part of the EMPLOYER with regard to the EMPLOYEE's ability to satisfactorily perform the duties and requirements of his/her employment", "In the event of the EMPLOYEE being incapacitated by ill health, accident or physical or mental incapacity from fully performing his/her duties with the EMPLOYER for an aggregate period of ninety (90) days in any one calendar year, such incapacity being duly certified as such by the EMPLOYER's appointed doctor;", "Failure of the EMPLOYEE to pass two (2) consecutive evaluations of his/her work performance; and", "Failure of the EMPLOYEE to successfully pass the EMPLOYER's standards for regularization specified under Annex \"B\" hereof and under other rules, regulations, and policies of the EMPLOYER; and", "Other similar acts, omissions, and/or events."]` + closing paragraph `"The Contract of employment may be terminated by the EMPLOYER for any of the foregoing grounds and by observing the due process requirements of the law. In the event that the EMPLOYEE wishes to terminate this Contract of Employment for any reason, he/she must give thirty (30) days written notice to EMPLOYER prior to the effective date of termination. Upon termination of this employment, the EMPLOYEE shall promptly account for, return, and deliver to the EMPLOYER at the EMPLOYER's main office, his/her I.D. Cards, Code of Discipline manual, Employee Handbook and all the EMPLOYER's property, which may have been assigned or entrusted to his/her care or custody."`
- **§14 FINAL PAY:** `"It is also hereby agreed that in case of termination of the EMPLOYEE's employment for whatever causes, the EMPLOYER shall have the right, and the EMPLOYEE hereby authorize the EMPLOYER, to withhold the EMPLOYEE's last salary or any other benefits accrued in the EMPLOYEE's favor, pending liquidation of whatever obligations which the EMPLOYEE may have with the EMPLOYER without prejudice to the right of the EMPLOYER to demand, collect, and recover from the EMPLOYEE any balance remaining thereafter."`
- **§15 CONFIDENTIALITY:** `"It is the EMPLOYEE's responsibility to ensure that no information gained by virtue of employment with the EMPLOYER or by virtue of his/her assignment to the EMPLOYER's clients is disclosed to outsiders unless the disclosure is for necessary business purposes and pursuant to properly approved and written agreements. Confidential information is any information belonging to EMPLOYER or its clients that could be used by people outside the company to the detriment of the EMPLOYER or its clients. The EMPLOYEE should take appropriate steps in handling all EMPLOYER business information in order to minimize the possibility of unauthorized disclosure."`
- **§16 SEPARABILITY CLAUSE:** `"If any provisions of this document shall be construed to be illegal or invalid, they shall not affect the legality, validity, and enforceability of the other provisions of this document; the illegal or invalid provision shall be deleted from this document and no longer incorporated herein but all other provisions of this document shall continue."`
- **§17 ENTIRE AGREEMENT:** `"This Contract represents the entire agreement between the EMPLOYER and the EMPLOYEE and supersedes all previous oral and written communications, representations or agreements between the parties. Any amendments or modifications to this contract must be made in writing and signed by both parties."`
- **Witness clause:** `"IN WITNESS WHEREOF, the parties have executed this document as of the date and place first mentioned."`
- **Annex A header:** `"Annex A: Duties, Responsibilities, and Work Hours"` + `"Position Title: {position}"`

## Block tree

```
1.  if logoBytes: LogoBlock + SpacerBlock(12)
2.  TitleBlock("EMPLOYMENT CONTRACT", centered: true)
3.  SpacerBlock(16)
4.  ParagraphBlock(preambleIntro)                      // date + place
5.  SpacerBlock(12)
6.  PartyBlock(employer spans)                          // bold name + italic address
7.  SpacerBlock(12)
8.  ParagraphBlock("- and -")  (centered via a Container — use a centered TitleBlock-like or a Paragraph with center; simplest: ParagraphBlock with leading/trailing handled — acceptable left-aligned if centering is hard, but prefer centered)
9.  SpacerBlock(12)
10. PartyBlock(employee spans)
11. SpacerBlock(24)
12. HeadingBlock("WITNESSETH THAT:")  (centered preferred)
13. SpacerBlock(8)
14. NumberedListBlock([recital1, recital2, recital3])
15. SpacerBlock(8)
16. ParagraphBlock(nowTherefore)
17. for each of §1..§17:
      SpacerBlock(12)
      SectionHeadingBlock(number: n, title: SECTION_TITLE)
      <one or more ParagraphBlock / EmphasisParagraphBlock / BulletListBlock / LetteredListBlock per the clause spec above>
18. SpacerBlock(24)
19. ParagraphBlock(witnessClause)                       // IN WITNESS WHEREOF
20. SpacerBlock(24)
21. ParagraphBlock(companyName) + ParagraphBlock("By:")  // employer line
22. SpacerBlock(40)
23. MultiSignatureBlock([
      (employerSignatoryName, employerSignatoryRole, null),     // hand-signed
      (employeeFullName, position, null),
    ])
24. SpacerBlock(24)
25. ParagraphBlock("SIGNED IN THE PRESENCE OF:")
26. SpacerBlock(40)
27. MultiSignatureBlock([
      (witness1Name, witness1Role, null),
      (witness2Name, witness2Role, null),
    ])
28. PageBreakBlock()
29. TitleBlock("Annex A: Duties, Responsibilities, and Work Hours")
30. SpacerBlock(12)
31. EmphasisParagraphBlock(["Position Title: " bold, position])
32. if missionStatement: SpacerBlock(8) + ParagraphBlock(missionStatement)
33. SpacerBlock(12) + HeadingBlock("Duties and Responsibilities")
34. for each responsibility:
      SectionHeadingBlock-ish or bold area label + BulletListBlock(tasks)
      (use LabelledBulletListBlock: one item per area with leadBold=area and children=tasks, OR a HeadingBlock(area) + BulletListBlock(tasks))
35. if kpis not empty: SpacerBlock(12) + HeadingBlock("Key Performance Indicators") + a TableBlock or BulletListBlock of "{metric} — {frequency}"
36. SpacerBlock(12) + HeadingBlock("Work Hours") + ParagraphBlock("{workHoursPerDay} hours per day, {workDaysPerWeek}.")
```

Note on centering (steps 8, 12): `TitleBlock` already supports `centered`. For "- and -" and "WITNESSETH THAT:" prefer a centered render. If a plain centered paragraph block doesn't exist, reuse `TitleBlock(text, centered: true)` for "WITNESSETH THAT:" (it's a heading) and a small centered container for "- and -". Acceptable to add an optional `centered` flag to `ParagraphBlock` (backward-compatible, default false) — implementer's choice; keep it minimal.

## Form (`employment_contract_form.dart`)

`ConsumerStatefulWidget` mirroring the other forms (employee picker with optimistic `_set` + `onEmployeeChanged`, `includeArchived: false` — contracts are for active hires). Fields, top to bottom:
- Employee (picker)
- Company (picker)
- Representative Name (`EmployeeNameField`), Representative Role (`RoleTitleField`)
- Place, Industry, Position (`RoleTitleField`)
- Date Entered, Probation Start, Probation End (date fields)
- Monthly Salary (text, numeric)
- Work Hours/Day (numeric), Work Days/Week (text)
- Non-Compete Months (numeric)
- Employer Signatory Name (`EmployeeNameField`) + Role (`RoleTitleField`)
- Witness 1 Name (`EmployeeNameField`) + Role (`RoleTitleField`)
- Witness 2 Name (`EmployeeNameField`) + Role (`RoleTitleField`)
- **Annex A**: mission (text), `AnnexAEditor` (responsibilities repeater: area + tasks list; KPIs repeater: metric + frequency) — mirrors `FindingsEditor` pattern.

Inline validation errors via `validateEmploymentContract`.

## Autofill flow

One-shot at screen open + on picker change (the existing `_onPickerEmployeeChanged` pattern). The template's `autofill(ctx)`:
1. From `ctx.employee`: name, address, position (jobTitle), probationStart (HIRE event ?? hireDate), probationEnd (+6mo).
2. From `ctx.company`: companyName, companyAddress, representativeName (hrManagerName), representativeRole (legalSignatoryRole ?? 'People Manager'), place, employerSignatory (= representative).
3. Role scorecard (via `ctx.ref.read(roleScorecardByIdProvider(emp.roleScorecardId))`, try/catch): missionStatement, responsibilities, kpis, workHoursPerDay, workDaysPerWeek, monthlySalary (baseSalary).
4. `loadBrandLogoBytes`.
5. Defaults: industry 'Retail Industry', nonCompeteMonths 24, dateEntered today.

`generate_screen.dart` gets the 5th branch in `_runAutofill`, `_onPickerEmployeeChanged`, `_formFor`, `_previewFor`, with `ValueKey('employment_contract-$_autofillRev')` and audit log `template_id: 'employment_contract'`. Add `'employment_contract'` case to `pdf_filename.dart` → `'EmploymentContract'`.

## Testing

| Layer | Tests |
|---|---|
| `LetteredListBlock` | stores items; renders a/b/c markers; >26 falls back to numbers |
| `PartyBlock` | stores spans + indent; renders without throwing; italic span honored |
| `EmphasisSpan` italic | bold-only still works (existing goldens pass); italic renders |
| `employment_contract_validate_test.dart` | each required-field error; probation date order; responsibilities min-1 + per-area task min-1; numeric guards |
| `employment_contract_build_test.dart` | block tree shape: starts with TitleBlock (no logo) / LogoBlock (with logo); 17 SectionHeadingBlocks with numbers 1..17; PageBreakBlock present; Annex A TitleBlock after the break; LetteredListBlock present (§13); responsibilities → blocks |
| `employment_contract_autofill_test.dart` | scorecard maps to mission/responsibilities/kpis/hours/salary; missing scorecard → empty Annex A + manual salary; representativeRole falls back to 'People Manager' |
| golden `employment_contract_pagination_test.dart` | full seeded contract → multi-page PDF, `%PDF` magic + byte threshold (mirrors other pagination tests) |

## Dependencies

None new. Reuses `pdf`, `printing`, `intl`, shared autocompletes, `interpolate`, `loadBrandLogoBytes`, `LogoBlock`.

## Implementation phases (for the plan author)

1. `LetteredListBlock` + tests.
2. `PartyBlock` + `EmphasisSpan` italic extension + tests.
3. `roleScorecardByIdProvider` in providers.dart.
4. `EmploymentContractInputs` types.
5. `validateEmploymentContract` + tests.
6. Template scaffold (metadata, emptyInputs, gates=[], validate wiring, stub build).
7. Autofill (employee + company + scorecard + logo) + tests.
8. Canonical clause `const` strings.
9. `build()` block tree + tests.
10. `AnnexAEditor` widget.
11. `employment_contract_form.dart`.
12. Register in `kTemplates` + `pdf_filename.dart` prefix.
13. Wire `generate_screen.dart` (5th branch).
14. Pagination golden.
15. Source-copy review with user before merge.

## Open questions

None at design time. Final clause wording is lifted from the source PDF; confirmed with user in the source-copy review (phase 15). Witness defaults (Christopher Lim/COO, Clinton Xu/CEO in the sample) are NOT hardcoded — they're manual fields, since they're not stored on any record and vary by signing.
