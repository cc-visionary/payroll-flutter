-- BIR RR 11-2018 year-end annualisation can produce a REFUND when projected
-- withholding exceeded the true annual tax owed. The refund shows on the
-- earnings side of the payslip (raising net pay), so we need a new enum
-- value rather than a negative TAX_WITHHOLDING line.
alter type payslip_line_category add value if not exists 'TAX_REFUND';
