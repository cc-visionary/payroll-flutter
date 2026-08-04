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
