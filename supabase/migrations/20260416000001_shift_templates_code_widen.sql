-- Lark shift_name maps directly to shift_templates.code, but Lark allows
-- names well past 20 chars. Widen to match the sibling name column so the
-- sync-lark-shifts function stops failing with
-- "value too long for type character varying(20)".
alter table shift_templates alter column code type varchar(100);
