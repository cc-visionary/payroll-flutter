-- Service Incentive Leave is the one kind of leave this company pays for.
--
-- `20260815000001_leave_types_unpaid_by_default.sql` fixed the trap that made
-- EVERY Lark-imported type paid: the column defaulted to true and
-- `sync-lark-leaves` never named it. That migration flipped all Lark-created
-- rows to unpaid and changed the default, which was right — an importer that
-- does not know the answer must not guess an expensive one.
--
-- It deliberately did not say which types ARE paid, because that is a company
-- policy decision and no migration had standing to make it. This one records
-- the decision the owner made (2026-08-22): paid leave means SIL, and nothing
-- else. Personal, Sick and Emergency leave stay unpaid.
--
-- Why a migration rather than just the toggle in Settings ▸ Leave Types (which
-- is still the right place to change it later): SIL is statutory. If this
-- database is ever rebuilt from migrations, the flag coming back false would
-- silently underpay every SIL day, and nothing in the app would say so.
--
-- Matching is on `lark_leave_type_id`, not `code`: `leave_types.code` is
-- varchar(20) and Lark's i18n token is longer than that, so every imported
-- code on this database is a truncated prefix ('@I18N@73687188425723'). The
-- lark id is stored whole and is the only exact key available.
--
-- Scope of the change, checked against prod before writing this: the four
-- approved SIL requests on record (Mar–May 2026, EMP002 ×2, EMP004, EMP005)
-- all fall inside RELEASED runs, and a released run cannot be recomputed from
-- the UI. So this moves no money already paid; it decides SIL approved from
-- here on.

do $$
declare
  v_matched int;
begin
  update leave_types
     set is_paid = true
   where lark_leave_type_id = '@i18n@7368718842572341279'  -- Service Incentive Leave
     and not is_paid;

  get diagnostics v_matched = row_count;

  if v_matched = 0 then
    -- Either already paid (a re-run — this migration is idempotent) or this
    -- database has no SIL row, which on a fresh environment is expected: leave
    -- types only exist once Lark leave has been synced. Say so rather than
    -- passing silently, so nobody assumes SIL is paid here when it is not.
    raise notice
      'leave_types: no unpaid Service Incentive Leave row matched — already '
      'paid, or this database has not synced Lark leave yet. Set it in '
      'Settings > Leave Types once the type exists.';
  else
    raise notice 'leave_types: Service Incentive Leave is now paid (% row).', v_matched;
  end if;
end $$;
