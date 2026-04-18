-- Publish payroll_runs, payslips, and payslip_lines to Supabase Realtime
-- so the Payroll Run detail screen can live-refresh after a recompute
-- (or any other admin editing the same run concurrently).
alter publication supabase_realtime add table payroll_runs;
alter publication supabase_realtime add table payslips;
alter publication supabase_realtime add table payslip_lines;
