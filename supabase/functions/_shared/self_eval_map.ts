// Maps a Lark self-evaluation Base record → app-shaped response.
//
// The onboarding self-eval forms (1st/3rd/6th month; a quarterly regular form
// later) have VARIABLE questions, so answers are kept as a flexible map keyed by
// question text — any form fits without a schema change. Two Base system fields
// are treated as metadata, not answers:
//   "Submitted on"  (created time)  -> submittedAt
//   "Respondents"   (created by)    -> respondentLarkUserId (the match key)
// Records must be read with user_id_type=user_id so "Respondents" resolves to a
// tenant user_id that lines up with employees.lark_user_id.
// See docs/superpowers/specs/2026-07-29-self-eval-response-sync-design.md.

import { baseCellText } from './lark.ts';
import { larkPersonId } from './master_data_map.ts';

export const META_SUBMITTED = 'Submitted on';
export const META_RESPONDENTS = 'Respondents';

export interface MappedSelfEval {
  /** Lark user_id of the submitter (from "Respondents"); null => unmatchable. */
  respondentLarkUserId: string | null;
  /** ISO instant from "Submitted on"; null if absent. */
  submittedAt: string | null;
  /** Every non-meta field as text, keyed by question text. */
  answers: Record<string, string>;
  /** The numeric (1-5) questions, keyed by question text. */
  ratings: Record<string, number>;
}

/** Convert a Lark created-time cell (epoch ms, or ms-as-string) to an ISO
 *  instant. Unlike a date field this is a real timestamp, so no tz shift. */
export function larkMsToISO(v: unknown): string | null {
  const ms = typeof v === 'number'
    ? v
    : typeof v === 'string' && /^\d+$/.test(v)
    ? Number(v)
    : NaN;
  if (!Number.isFinite(ms) || ms <= 0) return null;
  return new Date(ms).toISOString();
}

export function mapSelfEvalRecord(fields: Record<string, unknown>): MappedSelfEval {
  const answers: Record<string, string> = {};
  const ratings: Record<string, number> = {};
  let respondentLarkUserId: string | null = null;
  let submittedAt: string | null = null;

  for (const [key, raw] of Object.entries(fields)) {
    if (key === META_RESPONDENTS) {
      respondentLarkUserId = larkPersonId(raw);
      continue;
    }
    if (key === META_SUBMITTED) {
      submittedAt = larkMsToISO(raw);
      continue;
    }
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      ratings[key] = raw;
      answers[key] = String(raw);
      continue;
    }
    const text = baseCellText(raw);
    if (text != null) answers[key] = text;
  }

  return { respondentLarkUserId, submittedAt, answers, ratings };
}
