-- Per-benefit statutory eligibility overrides for probationary / non-regular
-- employees. The engine's default rule is: only REGULAR employees (or
-- non-regular past their regularization_date) get SSS / PhilHealth /
-- Pag-IBIG contributions. These three flags let Admin/HR force-enrol
-- a specific employee in a specific benefit independently of that rule.
--
-- Semantics:
--   false (default) → use the default employment-type / regularization gate.
--   true            → force-enrol this employee in the named benefit,
--                     even while still probationary.
--
-- The flags are checked PER-BENEFIT, not combined — admin chooses which
-- benefits to enable when starting contributions partway through probation
-- (common when an employee asks to start SSS early to keep coverage).

alter table employees
  add column sss_eligibility_override        boolean not null default false,
  add column philhealth_eligibility_override boolean not null default false,
  add column pagibig_eligibility_override    boolean not null default false;
