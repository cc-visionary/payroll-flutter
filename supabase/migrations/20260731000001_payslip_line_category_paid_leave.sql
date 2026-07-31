-- Add PAID_LEAVE to payslip_line_category. Paid leave (e.g. SIL) covered by
-- an approved leave request is paid as a distinct earning line for daily/
-- hourly employees; monthly employees carry a zero-amount info line (the day
-- is already paid via basic). `add value if not exists` is idempotent and
-- cannot run inside a txn block with other enum uses, so it stands alone.
alter type payslip_line_category add value if not exists 'PAID_LEAVE';
