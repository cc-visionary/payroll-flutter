-- Enable Supabase Realtime broadcasts for benefit tables so the desktop
-- Lark Integration screen reflects new cash_advances / reimbursements rows
-- the moment a sync inserts them.

alter publication supabase_realtime add table cash_advances;
alter publication supabase_realtime add table reimbursements;
