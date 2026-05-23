# Confidentiality & Non-Disclosure Agreement (NDA) Template — Design

**Date:** 2026-05-23
**Status:** Draft
**Extends:** the doc-templates system (6th template). Reuses the block library, `DocumentTemplate` interface, registry, generate-screen wiring, autofill pattern, justified single-spaced paragraphs, and `SignatureLineBlock`.

## Goal
Add **Confidentiality & Non-Disclosure Agreement** (NDA, signed upon employment) as the 6th template. 5-page agreement: a data-driven §1 PARTIES block, then 16 numbered sections of canonical legal text (mostly fixed), and a two-column "For the Company / Recipient" signature block. Source: `~/Downloads/Confidentiality and Non-Disclosure Agreement (Upon Employment).pdf`.

Mostly canonical boilerplate; only PARTIES + signatory names are data-driven. No logo (source has none). No gates.

## Inputs (`NdaInputs`)
```
employeeId, employeeFullName, employeePosition, employeeHomeAddress (String)
companyId, companyName, companyAddress (String)
effectiveDate (DateTime?)               // start of employment (hire date)
authorizedSignatoryName, authorizedSignatoryRole (String)
```
`emptyInputs`: blanks, effectiveDate null, authorizedSignatoryRole default 'Authorized Signatory'.

## Autofill
- employeeFullName ← emp.fullName; employeePosition ← emp.jobTitle ?? ''; employeeHomeAddress ← composed emp address (line1, line2, city, province, zip joined ', ')
- companyName ← co.name; companyAddress ← composed co address
- effectiveDate ← latest HIRE event date ?? emp.hireDate
- authorizedSignatoryName ← co.legalSignatoryName?.isNotEmpty == true ? co.legalSignatoryName : (co.hrManagerName ?? '')
- authorizedSignatoryRole ← co.legalSignatoryRole?.isNotEmpty == true ? co.legalSignatoryRole : 'Authorized Signatory'

## Validation
Required: employeeId, companyId, employeeFullName, employeePosition, employeeHomeAddress, companyName, companyAddress, effectiveDate (non-null), authorizedSignatoryName.

## Block tree
- `TitleBlock('Confidentiality & Non-Disclosure Agreement', centered: true)` + SpacerBlock(16)
- §1 PARTIES: `SectionHeadingBlock(1, 'PARTIES')` + intro paragraph + Employer line (EmphasisParagraph: "Employer  " bold-ish label then company bold + address) + Individual lines (Name / Position / Home Address filled) + "Effective Date: {date} (Start Date of Employment)". (Render the Parties sub-fields as EmphasisParagraphBlocks with bold labels + the filled values.)
- §2–§16: SectionHeadingBlock(n, TITLE) + canonical body (ParagraphBlock / EmphasisParagraphBlock for inline bold + BulletListBlock / LetteredListBlock as noted). §5 has sub-headings 5.1–5.5 (use HeadingBlock for sub-sections).
- Signature: "IN WITNESS WHEREOF, the Parties have executed this Agreement on the date first written above." then a two-column block: "For the Company" (Authorized Signatory, signature line + role + Date) and "Recipient" (Signature over Printed Name, signature line + Date). Use `SignatureLineBlock` with `row: true` and the "sign above printed name" format; captions "Authorized Signatory" + "Date: ___" and "Signature over Printed Name" + "Date: ___". (May need a small caption tweak — acceptable to render the company side with authorizedSignatoryName + role, recipient side blank/employee name.)

Justified single-spaced (the shared ParagraphBlock/EmphasisParagraphBlock already do justify + lineSpacing 1.0). Footer page numbers via the standard MultiPage footer.

## Canonical section text (verbatim from source)

**§1 PARTIES** intro: "This Confidentiality and Non-Disclosure Agreement (\"Agreement\") is entered into by and between:"
- Employer: "{companyName}, a corporation duly organized and existing under Philippine laws, with principal office at {companyAddress} (\"Company\")." (companyName bold, "Company" bold)
- Individual: "Name: {employeeFullName}", "Position/Role: {employeePosition}", "Home Address: {employeeHomeAddress} (\"Employee\")."
- "Effective Date: {effectiveDate} (Start Date of Employment)"

**§2 PURPOSE**:
- P1: "In the course of employment, the Employee will have access to confidential, proprietary, and sensitive information belonging to the Company, its affiliates, clients, customers, suppliers, and partners."
- P2 (bold "during employment and after the termination of employment"): "This Agreement defines the Employee's obligation to protect such information **during employment and after the termination of employment**, regardless of the cause or manner of separation."

**§3 DEFINITION OF CONFIDENTIAL INFORMATION**:
- intro: "\"Confidential Information\" refers to any non-public information, whether oral, written, electronic, visual, or in any other form, disclosed to or accessed by the Employee by reason of employment, including but not limited to:"
- bullets: [
  "Business strategies, plans, financial data, pricing, margins, forecasts, analytics, and reports",
  "Supplier lists, sourcing arrangements, contracts, inventory, logistics, and procurement data",
  "Customer and client information, databases, marketing plans, advertising accounts, voucher codes, and campaign results",
  "Product designs, specifications, formulas, prototypes, systems, software, source code, technical documentation, and workflows",
  "Trade secrets, know-how, SOPs, manuals, training materials, scripts, internal policies, and internal communications",
  "Employment, payroll, compensation, and human resources information",
  "Any information that a reasonable person would understand to be confidential or proprietary",
  ]
- closing: "Confidential Information need not be novel, patentable, copyrightable, or constitute a trade secret to be protected."

**§4 EXCLUDED INFORMATION**:
- intro (bold "not"): "Confidential Information does **not** include information that:"
- lettered (a-d): [
  "Is publicly available through no breach of this Agreement;",
  "Is independently developed by the Employee without use of Company resources or Confidential Information;",
  "Is lawfully obtained from a third party without breach of any duty of confidentiality; or",
  "Was already known to the Employee prior to disclosure, as evidenced by written records.",
  ]

**§5 EMPLOYEE OBLIGATIONS** (sub-sections via HeadingBlock):
- 5.1 Non-Disclosure: "The Employee shall not disclose, publish, transmit, or make available any Confidential Information to any person or entity without the prior written consent of the Company."
- 5.2 Non-Use: "The Employee shall use Confidential Information solely for legitimate Company business purposes and shall not use such information for personal benefit or for the benefit of any third party or competing business."
- 5.3 Safekeeping: "The Employee shall exercise reasonable care, not less than the care used to protect their own confidential information, to prevent unauthorized access, loss, misuse, or disclosure of Confidential Information."
- 5.4 Return or Deletion of Company Property (bold "subject to applicable labor laws"):
  - P1: "Upon request or upon termination of employment, and **subject to applicable labor laws**, the Employee shall immediately return or permanently delete all Company property and Confidential Information, including documents, files, devices, storage media, credentials, access keys, and copies thereof."
  - P2: "The Company may require written certification that no copies remain in the Employee's possession or control."
- 5.5 Notification of Breach: "The Employee shall promptly notify the Company upon discovery of any actual or suspected unauthorized disclosure, loss, or misuse of Confidential Information."

**§6 DURATION OF OBLIGATIONS (SURVIVAL)** (bold "for as long as the Confidential Information remains confidential and proprietary"): "The obligations under this Agreement shall survive the termination of employment **for as long as the Confidential Information remains confidential and proprietary**, and shall cease to apply once such information enters the public domain through no breach of this Agreement."

**§7 USE OF GENERAL SKILLS AND EXPERIENCE**: "Nothing in this Agreement shall be construed to prohibit the Employee from using general skills, knowledge, experience, or expertise acquired during employment, provided that no Confidential Information of the Company is disclosed or misused."

**§8 COMPULSORY OR LEGALLY REQUIRED DISCLOSURE**: "The Employee may disclose Confidential Information if required by law, regulation, court order, or government authority, provided that the Employee, to the extent legally permissible, promptly notifies the Company prior to such disclosure to allow the Company to seek protective measures."

**§9 OWNERSHIP OF INFORMATION**: "All Confidential Information remains the exclusive property of the Company. No license, ownership interest, or other rights are granted to the Employee except as strictly necessary to perform assigned duties during employment."

**§10 RELATIONSHIP TO EMPLOYMENT CONTRACT** (bold "after employment"):
- P1: "This Agreement supplements, and does not replace, any confidentiality obligations under the Employee's Employment Contract or Company policies."
- P2: "In the event of inconsistency, this Agreement shall govern confidentiality obligations **after employment**."

**§11 REMEDIES**:
- P1: "The Employee acknowledges that unauthorized disclosure or misuse of Confidential Information may cause irreparable harm to the Company."
- P2: "Accordingly, the Company shall be entitled to:"
- bullets: ["Injunctive relief", "Damages (actual, consequential, and exemplary where applicable)", "Attorney's fees and costs", "Any other remedies available under law or equity"]
- closing: "without the necessity of posting bond."

**§12 NO WAIVER OF LABOR RIGHTS**: "Nothing in this Agreement shall be interpreted as a waiver of any rights or benefits granted to the Employee under the Labor Code of the Philippines, DOLE issuances, or other applicable labor laws."

**§13 SEVERABILITY**: "If any provision of this Agreement is held to be invalid or unenforceable, the remaining provisions shall remain in full force and effect."

**§14 GOVERNING LAW AND VENUE** (bold "Republic of the Philippines"): "This Agreement shall be governed by and construed in accordance with the laws of the **Republic of the Philippines**. Any dispute arising from this Agreement shall be filed with the proper courts of competent jurisdiction in the Philippines."

**§15 ENTIRE AGREEMENT**: "This Agreement constitutes the entire agreement between the Parties concerning confidentiality obligations during and after employment and supersedes all prior oral or written agreements on this subject."

**§16 ACKNOWLEDGMENT**:
- intro: "By signing below, the Employee acknowledges that he/she:"
- bullets (bold "condition of employment" in last): ["Has read and fully understood this Agreement", "Entered into this Agreement voluntarily", "Had the opportunity to seek independent legal advice", "Understands that execution of this Agreement is a **condition of employment**"]
- witness: "IN WITNESS WHEREOF, the Parties have executed this Agreement on the date first written above."
- signature: two columns — "For the Company" (Authorized Signatory: {authorizedSignatoryName} / {authorizedSignatoryRole}, Date: ___) and "Recipient" (Signature over Printed Name: {employeeFullName}, Date: ___).

## Testing
- `nda_validate_test.dart` — required-field errors.
- `nda_build_test.dart` — 16 SectionHeadingBlocks numbered 1-16; title centered; bullet/lettered lists present; signature row present.
- `nda_pagination_test.dart` — full NDA → multi-page %PDF + byte threshold.

## Wiring
Register `NdaTemplate()` in `kTemplates`; `pdf_filename` prefix 'NDA' for id 'nda'; 6th branch in generate_screen (state, runAutofill, onPickerEmployeeChanged, formFor, previewFor, ValueKey). Form: employee picker (includeArchived false — NDA signed on hire), company picker (re-derive name/address/signatory), position, home address, effective date, authorized signatory name + role. No gates.

## Phases
1. NdaInputs + validate.
2. NdaTemplate scaffold + autofill.
3. Canonical text consts + build (incl. PARTIES + signature).
4. NdaForm.
5. Register + pdf_filename + generate_screen wiring + pagination test.
