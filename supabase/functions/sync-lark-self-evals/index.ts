// Edge Function: sync-lark-self-evals
//
// Ingests employee self-evaluation responses from the Lark onboarding Base into
// lark_self_eval_responses. ONE-WAY, matched by each row's "Respondents" (the
// submitter) -> employees.lark_user_id. Variable questions are stored as
// flexible jsonb (answers + numeric ratings). Idempotent: upsert on
// (source_table, Bitable record_id).
//
// Table-driven: add the quarterly regular-employee form to TABLE_TYPES once its
// Base table exists — no other change. Tables not yet present are skipped.
//
// Input (POST JSON): { company_id?: string, dry_run?: boolean }
//   dry_run: read + map + match, write nothing; returns per-type counts + the
//   named "couldn't apply" list (no answer content).
// See docs/superpowers/specs/2026-07-29-self-eval-response-sync-design.md.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  resolveWikiNode,
  listBaseTables,
  listBaseRecords,
  listContactUsers,
  logSyncStart,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
} from '../_shared/lark.ts';
import { mapSelfEvalRecord } from '../_shared/self_eval_map.ts';

interface Body {
  company_id?: string;
  dry_run?: boolean;
}

const WIKI_TOKEN = Deno.env.get('LARK_EMPLOYEE_BASE_WIKI_TOKEN') ??
  'TNQSwJcM0iN16SkYCpllZvfIgdf';

// Base table name -> app review_type. Add the quarterly regular-employee form
// here once it exists in the Base (e.g. "Quarterly Self-Evaluation Form": "QUARTERLY").
const TABLE_TYPES: Record<string, string> = {
  '1st Month Employee Self-Evaluation Form': 'PROBATIONARY_M1',
  '3rd Month Employee Self-Evaluation Form': 'PROBATIONARY_M3',
  '6th Month Employee Self-Evaluation Form': 'PROBATIONARY_M6',
  'Quarterly Check-In': 'QUARTERLY',
};

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
      syncType: 'SELF_EVAL',
      syncedById: userIdFromAuthHeader(req),
    });
  }

  try {
    const auth = authFromEnv();
    const node = await resolveWikiNode(auth, WIKI_TOKEN);
    const appToken = node.obj_token;
    const tables = await listBaseTables(auth, appToken);

    // lark_user_id -> employee (org-wide, linked + live).
    const { data: emps, error: empErr } = await supabase
      .from('employees')
      .select('id, company_id, lark_user_id')
      .not('lark_user_id', 'is', null)
      .is('deleted_at', null);
    if (empErr) throw new Error(`load employees: ${empErr.message}`);
    const byLarkId = new Map<string, { id: string; company_id: string }>();
    for (const e of emps ?? []) {
      const key = (e.lark_user_id as string).trim();
      if (key && !byLarkId.has(key)) byLarkId.set(key, { id: e.id, company_id: e.company_id });
    }

    let total = 0, synced = 0, skippedNoRespondent = 0, skippedUnmatched = 0;
    const byType: Record<string, { matched: number; synced: number }> = {};
    const unmatchedIds = new Set<string>();
    const unapplied: Array<{ name?: string; larkUserId?: string; reason: string; source_table: string }> = [];

    for (const [tableName, reviewType] of Object.entries(TABLE_TYPES)) {
      const t = tables.find((x) => x.name === tableName);
      if (!t) continue; // form not created in the Base yet (e.g. quarterly)
      const records = await listBaseRecords(auth, appToken, t.table_id, { userIdType: 'user_id' });
      byType[reviewType] = byType[reviewType] ?? { matched: 0, synced: 0 };
      total += records.length;

      for (const rec of records) {
        let mapped;
        try {
          mapped = mapSelfEvalRecord(rec.fields);
        } catch (e) {
          errors.push(`map ${rec.record_id}: ${String(e)}`);
          continue;
        }
        if (!mapped.respondentLarkUserId) {
          skippedNoRespondent++;
          unapplied.push({ reason: 'NO_RESPONDENT', source_table: tableName });
          continue;
        }
        const emp = byLarkId.get(mapped.respondentLarkUserId.trim());
        if (!emp) {
          skippedUnmatched++;
          unmatchedIds.add(mapped.respondentLarkUserId.trim());
          unapplied.push({
            larkUserId: mapped.respondentLarkUserId,
            reason: 'NOT_IN_APP',
            source_table: tableName,
          });
          continue;
        }
        byType[reviewType].matched++;
        if (dryRun) { byType[reviewType].synced++; synced++; continue; }

        const { error } = await supabase.from('lark_self_eval_responses').upsert({
          company_id: emp.company_id,
          employee_id: emp.id,
          review_type: reviewType,
          source_table: tableName,
          source_record_id: rec.record_id,
          respondent_lark_user_id: mapped.respondentLarkUserId,
          submitted_at: mapped.submittedAt,
          answers: mapped.answers,
          ratings: mapped.ratings,
        }, { onConflict: 'source_table,source_record_id' });
        if (error) { errors.push(`upsert ${rec.record_id}: ${error.message}`); continue; }
        byType[reviewType].synced++;
        synced++;
      }
    }

    // Best-effort: name the unmatched respondents from the Lark contact directory
    // so the "couldn't apply" list is actionable (these people submitted a form
    // but aren't linked to an app employee yet).
    if (unmatchedIds.size > 0) {
      try {
        const contacts = await listContactUsers(auth);
        const nameById = new Map(contacts.map((u) => [u.user_id, u.name]));
        for (const e of unapplied) {
          if (e.larkUserId && nameById.has(e.larkUserId)) e.name = nameById.get(e.larkUserId);
        }
      } catch (_) { /* names are best-effort */ }
    }

    const summary = {
      total,
      synced,
      skipped_no_respondent: skippedNoRespondent,
      skipped_unmatched: skippedUnmatched,
      by_type: byType,
      unapplied,
      errors,
      ...(dryRun ? { dry_run: true } : {}),
    };

    if (!dryRun && logId) {
      await logSyncFinish(supabase, logId, {
        total,
        created: 0,
        updated: synced,
        skipped: skippedNoRespondent + skippedUnmatched,
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
