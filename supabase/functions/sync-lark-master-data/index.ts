// Edge Function: sync-lark-master-data
//
// Pulls the Lark "Employee Information" onboarding Base and enriches app
// employees with the fields the employee entered in the form (personal details,
// statutory IDs, disbursement accounts). ONE-WAY, Lark-primary, matched by the
// row's "Lark Profile" person field -> employees.lark_user_id.
//
// Smart merge (master_data_merge.ts): a field HR edited in the app is never
// overwritten; a blank in Lark never wipes an app value; Lark still corrects
// untouched fields. Per-employee `lark_master_snapshot` drives the 3-way merge.
//
// v1 is ENRICH-ONLY: it updates employees that already exist and are linked
// (their lark_user_id is stamped by sync-lark-employees). Rows with no Lark
// Profile, or whose profile matches no app employee, are skipped and reported.
// Department / Position / Status / Start Date / Contract Link are HR-managed in
// the Base and never synced — the app owns role/employment.
//
// Input (POST JSON): { company_id?: string, dry_run?: boolean }
//   - dry_run: read + map + compute the merge, but write nothing. Returns
//     aggregate change counts by field key (never record values / PII).
//   - company_id: required for a real run (labels the lark_sync_logs entry);
//     matching itself is org-wide by lark_user_id.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  resolveWikiNode,
  listBaseTables,
  listBaseRecords,
  logSyncStart,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
} from '../_shared/lark.ts';
import { mergeRecord } from '../_shared/master_data_merge.ts';
import {
  LARK_TABLE_EMPLOYEE_INFO,
  mapEmployeeInfoRecord,
  routeKey,
} from '../_shared/master_data_map.ts';

interface Body {
  company_id?: string;
  dry_run?: boolean;
}

// Wiki node for the onboarding Base (overridable via secret).
const WIKI_TOKEN = Deno.env.get('LARK_EMPLOYEE_BASE_WIKI_TOKEN') ??
  'TNQSwJcM0iN16SkYCpllZvfIgdf';

// The employees columns the sync may read/write (Lark-owned form fields only).
const EMP_COLS = [
  'first_name',
  'middle_name',
  'last_name',
  'birth_date',
  'personal_email',
  'present_address_line1',
  'civil_status',
  'phone_number',
  'emergency_contact_name',
  'emergency_contact_number',
  'emergency_contact_relationship',
];

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  let body: Body = {};
  try { body = await req.json(); } catch (_) { /* empty body */ }
  const dryRun = body.dry_run === true;
  const companyId = body.company_id;
  if (!dryRun && !companyId) return json({ error: 'company_id required' }, 400);

  const errors: string[] = [];
  let logId: string | null = null;
  if (!dryRun) {
    logId = await logSyncStart(supabase, {
      companyId: companyId!,
      syncType: 'MASTER_DATA',
      syncedById: userIdFromAuthHeader(req),
    });
  }

  try {
    // 1. Resolve the wiki-wrapped Base and read the Employee Information table.
    const auth = authFromEnv();
    const node = await resolveWikiNode(auth, WIKI_TOKEN);
    const appToken = node.obj_token;
    const tables = await listBaseTables(auth, appToken);
    const infoTable = tables.find((t) => t.name === LARK_TABLE_EMPLOYEE_INFO);
    if (!infoTable) throw new Error(`Table "${LARK_TABLE_EMPLOYEE_INFO}" not found in Base`);
    const records = await listBaseRecords(auth, appToken, infoTable.table_id, {
      userIdType: 'user_id',
    });

    // 2. Build the lark_user_id -> employee lookup (org-wide, linked + live).
    const { data: emps, error: empErr } = await supabase
      .from('employees')
      .select(`id, company_id, lark_user_id, lark_master_snapshot, ${EMP_COLS.join(', ')}`)
      .not('lark_user_id', 'is', null)
      .is('deleted_at', null);
    if (empErr) throw new Error(`load employees: ${empErr.message}`);
    const byLarkId = new Map<string, Record<string, unknown>>();
    for (const e of emps ?? []) {
      const key = (e.lark_user_id as string).trim();
      if (key && !byLarkId.has(key)) byLarkId.set(key, e);
    }

    // 3. Process each Base row.
    let matched = 0, updated = 0, skippedUnlinked = 0, skippedUnmatched = 0, noop = 0;
    const changedFieldCounts: Record<string, number> = {};

    for (const rec of records) {
      let mapped;
      try {
        mapped = mapEmployeeInfoRecord(rec.fields);
      } catch (e) {
        errors.push(`map ${rec.record_id}: ${String(e)}`);
        continue;
      }
      if (!mapped.larkUserId) { skippedUnlinked++; continue; }
      const emp = byLarkId.get(mapped.larkUserId.trim());
      if (!emp) { skippedUnmatched++; continue; }
      matched++;
      const employeeId = emp.id as string;

      // Current statutory + bank values for this employee.
      const [{ data: statRows }, { data: bankRows }] = await Promise.all([
        supabase.from('employee_statutory_ids')
          .select('id, id_type, id_number').eq('employee_id', employeeId),
        supabase.from('employee_bank_accounts')
          .select('id, bank_code, account_number, is_primary')
          .eq('employee_id', employeeId).is('deleted_at', null),
      ]);
      const statByType = new Map((statRows ?? []).map((r) => [r.id_type as string, r]));
      const bankByCode = new Map((bankRows ?? []).map((r) => [r.bank_code as string, r]));

      // Assemble `current` keyed the same way as `incoming`.
      const current: Record<string, string | null> = {};
      for (const key of Object.keys(mapped.incoming)) {
        const r = routeKey(key);
        if (r.kind === 'employee') {
          const v = emp[r.column];
          current[key] = v == null ? null : String(v);
        } else if (r.kind === 'statutory') {
          current[key] = (statByType.get(r.idType)?.id_number as string | undefined) ?? null;
        } else {
          current[key] = (bankByCode.get(r.bankCode)?.account_number as string | undefined) ?? null;
        }
      }

      const oldSnapshot = (emp.lark_master_snapshot as Record<string, string | null>) ?? {};
      const { updates, snapshot: newSnapshot } = mergeRecord(current, oldSnapshot, mapped.incoming);
      const changedKeys = Object.keys(updates);
      for (const k of changedKeys) changedFieldCounts[k] = (changedFieldCounts[k] ?? 0) + 1;

      const snapshotChanged = JSON.stringify(oldSnapshot) !== JSON.stringify(newSnapshot);
      if (changedKeys.length === 0 && !snapshotChanged) { noop++; continue; }

      if (dryRun) { if (changedKeys.length) updated++; else noop++; continue; }

      // Route the merged updates to the right tables.
      try {
        const empPayload: Record<string, unknown> = {};
        for (const [key, val] of Object.entries(updates)) {
          const r = routeKey(key);
          if (r.kind === 'employee') {
            empPayload[r.column] = val;
          } else if (r.kind === 'statutory') {
            if (val != null) {
              const { error } = await supabase.from('employee_statutory_ids').upsert(
                { employee_id: employeeId, id_type: r.idType, id_number: val },
                { onConflict: 'employee_id,id_type' },
              );
              if (error) throw new Error(`statutory ${r.idType}: ${error.message}`);
            }
          } else if (val != null) {
            const existing = bankByCode.get(r.bankCode);
            if (existing) {
              const { error } = await supabase.from('employee_bank_accounts')
                .update({ account_number: val }).eq('id', existing.id);
              if (error) throw new Error(`bank ${r.bankCode}: ${error.message}`);
            } else {
              const hasPrimary = [...bankByCode.values()].some((b) => b.is_primary === true);
              const accountName = mapped.fullName ||
                `${emp.first_name ?? ''} ${emp.last_name ?? ''}`.trim() || 'N/A';
              const { error } = await supabase.from('employee_bank_accounts').insert({
                employee_id: employeeId,
                bank_code: r.bankCode,
                bank_name: r.bankName,
                account_number: val,
                account_name: accountName,
                is_primary: r.isPrimary || !hasPrimary,
              });
              if (error) throw new Error(`bank ${r.bankCode}: ${error.message}`);
            }
          }
        }
        if (snapshotChanged) empPayload.lark_master_snapshot = newSnapshot;
        if (Object.keys(empPayload).length > 0) {
          const { error } = await supabase.from('employees').update(empPayload).eq('id', employeeId);
          if (error) throw new Error(`employees update: ${error.message}`);
        }
        if (changedKeys.length) updated++; else noop++;
      } catch (e) {
        errors.push(`apply ${employeeId}: ${String(e)}`);
      }
    }

    const summary = {
      total: records.length,
      matched,
      updated,
      noop,
      skipped_unlinked: skippedUnlinked,
      skipped_unmatched: skippedUnmatched,
      errors,
      ...(dryRun ? { dry_run: true, changed_field_counts: changedFieldCounts } : {}),
    };

    if (!dryRun && logId) {
      await logSyncFinish(supabase, logId, {
        total: records.length,
        created: 0,
        updated,
        skipped: skippedUnlinked + skippedUnmatched + noop,
        errors,
      });
    }
    return json({ ok: true, ...summary });
  } catch (e) {
    if (!dryRun && logId) {
      await logSyncFinish(supabase, logId, {
        total: 0, created: 0, updated: 0, skipped: 0, errors: [String(e)],
      });
    }
    return json({ ok: false, error: String(e) }, 200);
  }
});
